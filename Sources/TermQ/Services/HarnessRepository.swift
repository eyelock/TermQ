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
@MainActor
final class HarnessRepository: ObservableObject {
    static let shared = HarnessRepository()

    @Published private(set) var harnesses: [Harness] = []
    /// Capabilities string from the most recent `ynh ls` envelope.
    /// Used by `HarnessDetailViewModel.phase1Capable` to gate Phase 1 affordances.
    @Published private(set) var lastCapabilities: String?
    @Published private(set) var isLoading = false
    /// The id of the selected harness (`Harness.id` — namespace-qualified when present).
    @Published var selectedHarnessName: String?

    /// Full detail for the selected harness (info + composition).
    @Published private(set) var selectedDetail: HarnessDetail?
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var detailError: String?

    /// Per-session cache of fetched details keyed by `Harness.id`.
    private var detailCache: [String: HarnessDetail] = [:]

    private let ynhDetector: any YNHDetectorProtocol

    /// The currently selected harness, matched by `Harness.id`.
    var selectedHarness: Harness? {
        guard let id = selectedHarnessName else { return nil }
        return harnesses.first { $0.id == id }
    }

    private convenience init() {
        self.init(ynhDetector: YNHDetector.shared)
    }

    init(ynhDetector: any YNHDetectorProtocol) {
        self.ynhDetector = ynhDetector
    }

    // MARK: - List

    /// Fetch the installed harnesses list from `ynh ls --format json`.
    ///
    /// Requires `YNHDetector.status` to be `.ready`; clears the list otherwise.
    func refresh() async {
        guard case .ready(let ynhPath, _, _) = ynhDetector.status else {
            harnesses = []
            selectedHarnessName = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        let env = ynhEnvironment()

        do {
            let result = try await CommandRunner.run(
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
            harnesses = decoded
            lastCapabilities = response.capabilities

            // Clear selection if the selected harness was removed.
            if let id = selectedHarnessName,
                !decoded.contains(where: { $0.id == id })
            {
                selectedHarnessName = nil
            }
        } catch {
            TermQLogger.ui.error(
                "HarnessRepository: ynh ls failed type=\(type(of: error)) desc=\(String(describing: error).prefix(200))"
            )
            harnesses = []
        }
    }

    // MARK: - Detail

    /// Fetch the full detail for the named harness.
    ///
    /// Runs `ynh info <name> --format json` then `ynd compose <info.path>`.
    /// Results are cached per session; call ``invalidateDetail(for:)`` after
    /// mutations to force a refetch.
    func fetchDetail(for name: String) async {
        if let cached = detailCache[name] {
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
            let detail = try await buildDetail(name: name, ynhPath: ynhPath, yndPath: yndPath)
            detailCache[name] = detail
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

    private func buildDetail(name: String, ynhPath: String, yndPath: String?) async throws -> HarnessDetail {
        let env = ynhEnvironment()
        let infoResult = try await CommandRunner.run(
            executable: ynhPath,
            arguments: ["info", name, "--format", "json"],
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
        let composeResult = try await CommandRunner.run(
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

    /// Invalidate cached detail for a specific harness (call after mutations). Pass `harness.name`.
    func invalidateDetail(for name: String) {
        detailCache.removeValue(forKey: name)
        if selectedHarness?.name == name {
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
