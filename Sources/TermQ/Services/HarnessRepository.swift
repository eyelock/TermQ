import Foundation
import TermQShared

private enum HarnessDetailError: Error {
    case missingYnd
}

private struct YNHErrorResponse: Decodable {
    struct Body: Decodable {
        let code: String?
        let message: String?
    }
    let error: Body
}

/// Extract a human-readable message from YNH stderr output.
/// YNH emits `{"error":{"code":"...","message":"..."}}` on failure.
/// Falls back to the raw trimmed string if the JSON shape doesn't match.
/// Returns nil when stderr is empty.
func ynhErrorMessage(from stderr: String) -> String? {
    let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let data = trimmed.data(using: .utf8),
        let parsed = try? JSONDecoder().decode(YNHErrorResponse.self, from: data)
    {
        let msg = [parsed.error.message, parsed.error.code]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .first
        if let msg { return msg }
    }
    return trimmed
}

/// Repository for querying installed harnesses via `ynh ls --format json`
/// and fetching full detail via `ynh info` + `ynd compose`.
///
/// Modelled as a `@MainActor` singleton (same pattern as `YNHDetector`).
/// The harness list is refreshed on explicit user action, after detection
/// status changes to `.ready`, and when the app regains focus.
///
/// Readiness model: `listState` is the canonical source of truth and uses
/// `LoadState` to distinguish "never loaded" from "loading" from "loaded
/// (possibly empty)" from "errored". Consumers that need to gate UI on
/// actually-having-data must check `listState.isLoaded` rather than looking
/// at `harnesses.isEmpty`.
@MainActor
final class HarnessRepository: ObservableObject {
    static let shared = HarnessRepository()

    /// Canonical readiness/value state for the harness list.
    @Published private(set) var listState: LoadState<[Harness]> = .idle
    /// Capabilities string from the most recent `ynh ls` envelope.
    /// Used by `HarnessDetailViewModel.phase1Capable` to gate Phase 1 affordances.
    @Published private(set) var lastCapabilities: String?
    /// On-disk schema version from the most recent `ynh ls` envelope.
    /// `2` means YNH has migrated to canonical-id shape. Lower values
    /// (or `nil`) signal the migration coordinator should run.
    @Published private(set) var lastSchemaVersion: Int?
    /// The id of the selected harness — `Harness.id` (namespace-qualified
    /// when present, bare name otherwise). Identity is canonical: writers
    /// always pass `harness.id`, never `harness.name`.
    @Published var selectedHarnessId: String?

    /// Full detail for the selected harness (info + composition).
    @Published private(set) var selectedDetail: HarnessDetail?
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var detailError: String?

    /// Per-session cache of fetched details keyed by `Harness.id`.
    private var detailCache: [String: HarnessDetail] = [:]

    private let ynhDetector: any YNHDetectorProtocol
    private let commandRunner: any YNHCommandRunner

    /// Whether `YNHPersistence`'s legacy bare-name → id migration has been
    /// run for this session. Runs at most once after a successful refresh.
    private var didRunIdentityMigration = false

    // MARK: - Convenience accessors

    /// The harnesses currently held in `.loaded`. Empty in any other state.
    /// Use `listState` directly when readiness vs. emptiness matters.
    var harnesses: [Harness] { listState.value ?? [] }

    /// True while a `refresh()` is in flight, regardless of whether a
    /// previously-loaded list is being kept visible (stale-while-revalidate).
    @Published private(set) var isRefreshing = false

    /// True while a `refresh()` is in flight or the list has never loaded.
    /// Consumers showing a "loading..." state should use this; consumers
    /// rendering the harness list itself should use `harnesses` directly,
    /// which keeps the previously-loaded value visible during refresh.
    var isLoading: Bool { isRefreshing || listState.isLoading }

    /// The currently selected harness. Resolved by canonical `Harness.id`.
    /// Returns `nil` when the list is not yet loaded, when no selection is
    /// set, or when the selection does not match an installed harness.
    var selectedHarness: Harness? {
        guard let key = selectedHarnessId else { return nil }
        return harnesses.first { $0.id == key }
    }

    private convenience init() {
        self.init(ynhDetector: YNHDetector.shared)
    }

    init(
        ynhDetector: any YNHDetectorProtocol,
        commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()
    ) {
        self.ynhDetector = ynhDetector
        self.commandRunner = commandRunner
    }

    // MARK: - List

    /// Fetch the installed harnesses list from `ynh ls --format json`.
    ///
    /// Requires `YNHDetector.status` to be `.ready`; clears the list otherwise.
    func refresh() async {
        guard case .ready(let ynhPath, _, _) = ynhDetector.status else {
            listState = .loaded([])
            selectedHarnessId = nil
            return
        }

        // Stale-while-revalidate: only show the .loading state when there
        // is no previously-loaded list to display. Once we have data, we
        // keep it visible across refreshes — the `isRefreshing` flag
        // surfaces the in-flight signal to consumers that want a spinner.
        // Without this, every focus-driven refresh would empty the list,
        // unmount the detail pane, and dismiss any open sheet.
        if !listState.isLoaded {
            listState = .loading
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let env = ynhEnvironment()

        do {
            let result = try await commandRunner.run(
                executable: ynhPath,
                arguments: ["ls", "--format", "json"],
                environment: env
            )
            guard result.didSucceed else {
                throw YNHDetectionError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
            }
            let response = try JSONDecoder().decode(
                HarnessListResponse.self, from: Data(result.stdout.utf8))
            let decoded = response.harnesses
            listState = .loaded(decoded)
            lastCapabilities = response.capabilities
            lastSchemaVersion = response.schemaVersion

            // One-shot migration: rewrite any persisted association whose
            // value is a bare `name` for a now-namespaced harness so that
            // future reads see the canonical `id` form. Safe to run on every
            // session (idempotent); gate to once per session to avoid churn.
            if !didRunIdentityMigration {
                YNHPersistence.shared.migrateLegacyHarnessKeys(using: decoded)
                didRunIdentityMigration = true
            }

            // Clear selection if it does not match a canonical id. Post
            // canonical-id cutover, `selectedHarnessId` is always canonical;
            // anything else is stale state from before migration.
            if let key = selectedHarnessId,
                !decoded.contains(where: { $0.id == key })
            {
                selectedHarnessId = nil
            }
        } catch {
            TermQLogger.ui.error(
                "HarnessRepository: ynh ls failed type=\(type(of: error)) desc=\(String(describing: error).prefix(200))"
            )
            listState = .error("Failed to list harnesses")
        }
    }

    // MARK: - Detail

    /// Fetch the full detail for the named harness.
    ///
    /// Runs `ynh info <name> --format json` then `ynd compose <info.path>`.
    /// Results are cached per session; call ``invalidateDetail(for:)`` after
    /// mutations to force a refetch.
    func fetchDetail(for id: String) async {
        if let cached = detailCache[id] {
            selectedDetail = cached
            detailError = nil
            return
        }

        guard case .ready(let ynhPath, let yndPath, _) = ynhDetector.status else {
            detailError = "YNH toolchain not ready"
            return
        }

        isLoadingDetail = true
        detailError = nil
        defer { isLoadingDetail = false }

        do {
            let detail = try await buildDetail(id: id, ynhPath: ynhPath, yndPath: yndPath)
            detailCache[id] = detail
            selectedDetail = detail
        } catch let error as YNHDetectionError {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.ui.info("HarnessRepository: detail fetch failed error=\(error)")
            } else {
                TermQLogger.ui.info("HarnessRepository: detail fetch failed")
            }
            selectedDetail = nil
            if case .commandFailed(_, let stderr) = error {
                detailError = ynhErrorMessage(from: stderr) ?? "Failed to load harness detail"
            } else {
                detailError = "Failed to load harness detail"
            }
        } catch HarnessDetailError.missingYnd {
            selectedDetail = nil
            detailError = "ynd binary not found — install the YNH dev tools for full detail"
        } catch {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.ui.info("HarnessRepository: detail fetch failed error=\(error)")
            } else {
                TermQLogger.ui.info("HarnessRepository: detail fetch failed")
            }
            selectedDetail = nil
            detailError = "Failed to load harness detail"
        }
    }

    private func buildDetail(id: String, ynhPath: String, yndPath: String?) async throws -> HarnessDetail {
        let env = ynhEnvironment()
        let infoResult = try await commandRunner.run(
            executable: ynhPath,
            arguments: ["info", id, "--format", "json"],
            environment: env
        )
        guard infoResult.didSucceed else {
            throw YNHDetectionError.commandFailed(exitCode: infoResult.exitCode, stderr: infoResult.stderr)
        }
        let infoResponse = try JSONDecoder().decode(
            HarnessInfoResponse.self, from: Data(infoResult.stdout.utf8))
        let info = infoResponse.harness

        guard let yndBinary = yndPath else {
            throw HarnessDetailError.missingYnd
        }
        let composeResult = try await commandRunner.run(
            executable: yndBinary,
            arguments: ["compose", info.path],
            environment: env
        )
        guard composeResult.didSucceed else {
            throw YNHDetectionError.commandFailed(exitCode: composeResult.exitCode, stderr: composeResult.stderr)
        }
        let composition = try JSONDecoder().decode(HarnessComposition.self, from: Data(composeResult.stdout.utf8))
        return HarnessDetail(info: info, composition: composition)
    }

    /// Invalidate cached detail for a specific harness (call after mutations). Pass `harness.id`.
    func invalidateDetail(for id: String) {
        detailCache.removeValue(forKey: id)
        if selectedHarness?.id == id {
            selectedDetail = nil
        }
    }

    /// Invalidate all cached details (call after bulk operations).
    func invalidateAllDetails() {
        detailCache.removeAll()
        selectedDetail = nil
    }

    // MARK: - Helpers

    private func ynhEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = ynhDetector.ynhHomeOverride {
            env["YNH_HOME"] = override
        }
        return env
    }
}
