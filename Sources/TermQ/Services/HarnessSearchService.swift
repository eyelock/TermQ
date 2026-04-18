import Foundation
import TermQShared

/// Searches installed registries and local sources via `ynh search <term> --format json`.
@MainActor
final class HarnessSearchService: ObservableObject {
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var error: String?

    private var searchTask: Task<Void, Never>?

    /// Search registries and sources. An empty query browses all available harnesses.
    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let debounce: UInt64 = trimmed.isEmpty ? 0 : 350
        searchTask = Task {
            if debounce > 0 { try? await Task.sleep(for: .milliseconds(debounce)) }
            guard !Task.isCancelled else { return }
            guard case .ready(let ynhPath, _, _) = YNHDetector.shared.status else {
                results = []
                return
            }
            isSearching = true
            error = nil
            defer { isSearching = false }
            var env = ProcessInfo.processInfo.environment
            if let override = YNHDetector.shared.ynhHomeOverride {
                env["YNH_HOME"] = override
            }
            let args: [String] = trimmed.isEmpty
                ? ["search", "--format", "json"]
                : ["search", trimmed, "--format", "json"]
            do {
                let output = try await YNHDetector.runCommand(
                    ynhPath,
                    args: args,
                    environment: env
                )
                guard !Task.isCancelled else { return }
                results = try JSONDecoder().decode([SearchResult].self, from: Data(output.utf8))
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
    }
}
