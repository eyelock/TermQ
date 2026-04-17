import Foundation
import TermQShared

private enum HarnessDetailError: Error {
    case missingYnd
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
    @Published private(set) var isLoading = false
    @Published var selectedHarnessName: String?

    /// Full detail for the selected harness (info + composition).
    @Published private(set) var selectedDetail: HarnessDetail?
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var detailError: String?

    /// Per-session cache of fetched details keyed by harness name.
    private var detailCache: [String: HarnessDetail] = [:]

    /// The currently selected harness, derived from `selectedHarnessName`.
    var selectedHarness: Harness? {
        guard let name = selectedHarnessName else { return nil }
        return harnesses.first { $0.name == name }
    }

    private init() {}

    // MARK: - List

    /// Fetch the installed harnesses list from `ynh ls --format json`.
    ///
    /// Requires `YNHDetector.status` to be `.ready`; clears the list otherwise.
    func refresh() async {
        guard case .ready(let ynhPath, _, _) = YNHDetector.shared.status else {
            harnesses = []
            selectedHarnessName = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        let env = ynhEnvironment()

        do {
            let json = try await YNHDetector.runCommand(
                ynhPath,
                args: ["ls", "--format", "json"],
                environment: env
            )
            let decoded = try JSONDecoder().decode([Harness].self, from: Data(json.utf8))
            harnesses = decoded

            // Clear selection if the selected harness was removed.
            if let name = selectedHarnessName,
                !decoded.contains(where: { $0.name == name })
            {
                selectedHarnessName = nil
            }
        } catch {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.ui.info("HarnessRepository: ynh ls failed error=\(error)")
            } else {
                TermQLogger.ui.info("HarnessRepository: ynh ls failed")
            }
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

        guard case .ready(let ynhPath, let yndPath, _) = YNHDetector.shared.status else {
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
            if case .commandFailed(_, let stderr) = error,
                !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                detailError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let infoJSON = try await YNHDetector.runCommand(
            ynhPath,
            args: ["info", name, "--format", "json"],
            environment: env
        )
        let info = try JSONDecoder().decode(HarnessInfo.self, from: Data(infoJSON.utf8))

        guard let yndBinary = yndPath else {
            throw HarnessDetailError.missingYnd
        }
        let composeJSON = try await YNHDetector.runCommand(
            yndBinary,
            args: ["compose", info.path],
            environment: env
        )
        let composition = try JSONDecoder().decode(HarnessComposition.self, from: Data(composeJSON.utf8))
        return HarnessDetail(info: info, composition: composition)
    }

    /// Invalidate cached detail for a specific harness (call after mutations).
    func invalidateDetail(for name: String) {
        detailCache.removeValue(forKey: name)
        if selectedHarnessName == name {
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
        if let override = YNHDetector.shared.ynhHomeOverride {
            env["YNH_HOME"] = override
        }
        return env
    }
}
