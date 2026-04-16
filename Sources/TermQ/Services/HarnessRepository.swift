import Foundation
import TermQShared

/// Repository for querying installed harnesses via `ynh ls --format json`.
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

    /// The currently selected harness, derived from `selectedHarnessName`.
    var selectedHarness: Harness? {
        guard let name = selectedHarnessName else { return nil }
        return harnesses.first { $0.name == name }
    }

    private init() {}

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

        var env = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride {
            env["YNH_HOME"] = override
        }

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
}
