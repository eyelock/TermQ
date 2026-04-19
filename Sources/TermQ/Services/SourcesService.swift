import Foundation
import TermQShared

/// Manages local harness sources via `ynh sources list|add|remove --format json`.
@MainActor
final class SourcesService: ObservableObject {
    @Published private(set) var sources: [YNHSource] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    func refresh() async {
        guard case .ready(let ynhPath, _, _) = YNHDetector.shared.status else {
            sources = []
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let output = try await YNHDetector.runCommand(
                ynhPath,
                args: ["sources", "list", "--format", "json"],
                environment: ynhEnvironment()
            )
            sources = try JSONDecoder().decode([YNHSource].self, from: Data(output.utf8))
        } catch {
            self.error = error.localizedDescription
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.session.warning("SourcesService: refresh failed: \(error.localizedDescription)")
            } else {
                TermQLogger.session.warning("SourcesService: refresh failed")
            }
            sources = []
        }
    }

    func addSource(path: String, name: String?) async {
        guard case .ready(let ynhPath, _, _) = YNHDetector.shared.status else { return }
        var args = ["sources", "add", path]
        if let name, !name.isEmpty { args.append(contentsOf: ["--name", name]) }
        do {
            _ = try await YNHDetector.runCommand(ynhPath, args: args, environment: ynhEnvironment())
            await refresh()
        } catch {
            self.error = error.localizedDescription
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.session.warning("SourcesService: add source failed: \(error.localizedDescription)")
            } else {
                TermQLogger.session.warning("SourcesService: add source failed")
            }
        }
    }

    func removeSource(name: String) async {
        guard case .ready(let ynhPath, _, _) = YNHDetector.shared.status else { return }
        do {
            _ = try await YNHDetector.runCommand(
                ynhPath,
                args: ["sources", "remove", name],
                environment: ynhEnvironment()
            )
            await refresh()
        } catch {
            self.error = error.localizedDescription
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.session.warning("SourcesService: remove source failed: \(error.localizedDescription)")
            } else {
                TermQLogger.session.warning("SourcesService: remove source failed")
            }
        }
    }

    private func ynhEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride {
            env["YNH_HOME"] = override
        }
        return env
    }
}
