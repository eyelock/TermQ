import Foundation
import TermQShared

/// Searches installed registries and local sources via `ynh search <term> --format json`.
@MainActor
final class HarnessSearchService: ObservableObject {
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var error: String?
    /// True after the first `search()` task has run to completion (success
    /// or failure). Distinguishes "haven't searched yet" from "searched
    /// and got nothing" — consumers showing an empty-state should gate on
    /// this so the empty copy doesn't flash before the first search lands.
    @Published private(set) var hasSearched = false

    private var searchTask: Task<Void, Never>?
    private let ynhDetector: any YNHDetectorProtocol
    private let commandRunner: any YNHCommandRunner

    init(
        ynhDetector: any YNHDetectorProtocol = YNHDetector.shared,
        commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()
    ) {
        self.ynhDetector = ynhDetector
        self.commandRunner = commandRunner
    }

    /// Search registries and sources. An empty query browses all available harnesses.
    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let debounce: UInt64 = trimmed.isEmpty ? 0 : 350
        searchTask = Task {
            if debounce > 0 { try? await Task.sleep(for: .milliseconds(debounce)) }
            guard !Task.isCancelled else { return }
            guard case .ready(let ynhPath, _, _) = ynhDetector.status else {
                results = []
                return
            }
            isSearching = true
            error = nil
            defer {
                isSearching = false
                hasSearched = true
            }
            var env = ProcessInfo.processInfo.environment
            if let override = ynhDetector.ynhHomeOverride {
                env["YNH_HOME"] = override
            }
            let args: [String] =
                trimmed.isEmpty
                ? ["search", "--format", "json"]
                : ["search", trimmed, "--format", "json"]
            do {
                let result = try await commandRunner.run(
                    executable: ynhPath,
                    arguments: args,
                    environment: env
                )
                guard !Task.isCancelled else { return }
                guard result.didSucceed else {
                    throw YNHDetectionError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
                }
                results = try JSONDecoder().decode([SearchResult].self, from: Data(result.stdout.utf8))
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                results = []
            }
        }
    }

    func reset() {
        searchTask?.cancel()
        searchTask = nil
        results = []
        isSearching = false
        error = nil
        hasSearched = false
    }
}
