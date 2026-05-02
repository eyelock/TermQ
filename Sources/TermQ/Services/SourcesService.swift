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
            let result = try await CommandRunner.run(
                executable: ynhPath,
                arguments: ["sources", "list", "--format", "json"],
                environment: ynhEnvironment()
            )
            guard result.didSucceed else {
                throw YNHDetectionError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
            }
            sources = try JSONDecoder().decode([YNHSource].self, from: Data(result.stdout.utf8))
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
            let result = try await CommandRunner.run(
                executable: ynhPath,
                arguments: args,
                environment: ynhEnvironment()
            )
            guard result.didSucceed else {
                throw YNHDetectionError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
            }
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
            let result = try await CommandRunner.run(
                executable: ynhPath,
                arguments: ["sources", "remove", name],
                environment: ynhEnvironment()
            )
            guard result.didSucceed else {
                throw YNHDetectionError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
            }
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
