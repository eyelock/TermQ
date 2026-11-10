import Foundation
import TermQShared

/// The pull requests waiting on the human's review, across every GitHub
/// repository: one `gh search prs`, then one GraphQL query for when each
/// review was asked for. Backs the Repositories tab's Attention view.
@MainActor
final class ReviewRequestService: ObservableObject {
    static let shared = ReviewRequestService()

    @Published private(set) var requests: [ReviewRequest] = []
    @Published private(set) var isLoading = false
    /// Why the last load failed, from gh; nil when it worked.
    @Published private(set) var failure: String?
    @Published private(set) var lastLoaded: Date?
    /// The search hit its limit, so some requests may be missing.
    @Published private(set) var truncated = false

    /// `owner/name` of each repository added to TermQ, by path, for the
    /// "TermQ's repositories only" filter.
    @Published private(set) var termqRepositories: Set<String> = []
    /// The path of each TermQ repository, by lowercased `owner/name` (GitHub names
    /// are case-insensitive, and a remote URL may not use the API's casing).
    @Published private(set) var termqRepositoryPaths: [String: String] = [:]

    private var loadTask: Task<Void, Never>?
    private var namesTask: Task<Void, Never>?
    private var remoteCache: [String: String] = [:]

    /// Request times already fetched, by PR URL, so a timed refresh only
    /// asks about new requests. A forced refresh asks again, since a
    /// re-request after a review restarts the wait.
    private var requestedAt: [String: Date] = [:]

    /// Re-reads the review requests. Without `force` or `ignoringAge`, a load
    /// younger than a minute is kept; `force` also asks again for every
    /// request time.
    func refresh(ghPath: String, login: String, force: Bool = false, ignoringAge: Bool = false) {
        if !force, !ignoringAge, let lastLoaded, Date().timeIntervalSince(lastLoaded) < 60 { return }
        loadTask?.cancel()
        isLoading = true
        let known = force ? [:] : requestedAt
        loadTask = Task { [weak self] in
            let result = await Self.load(ghPath: ghPath, login: login, known: known)
            guard !Task.isCancelled, let self else { return }
            self.isLoading = false
            switch result {
            case .success(let loaded):
                // Only the current requests are kept, so the cache can't grow.
                self.requestedAt = Dictionary(
                    loaded.compactMap { request in request.requestedAt.map { (request.url, $0) } },
                    uniquingKeysWith: { first, _ in first })
                self.requests = loaded
                self.truncated = loaded.count >= ReviewRequests.searchLimit
                self.failure = nil
                self.lastLoaded = Date()
            case .failure(let error):
                TermQLogger.ui.error("ReviewRequestService: loading review requests failed")
                self.failure = error.message
            }
        }
    }

    /// Maps each TermQ repository path to `owner/name` from its origin
    /// remote (cached per path).
    func updateTermQRepositories(paths: [String]) {
        namesTask?.cancel()
        namesTask = Task { [weak self] in
            var names: Set<String> = []
            var pathsByName: [String: String] = [:]
            for path in paths {
                if let cached = self?.remoteCache[path] {
                    names.insert(cached)
                    pathsByName[cached.lowercased()] = pathsByName[cached.lowercased()] ?? path
                    continue
                }
                guard
                    let result = try? await StackProcessRunner.run(
                        "/usr/bin/git", ["-C", path, "remote", "get-url", "origin"], cwd: nil),
                    result.exitCode == 0, let name = ReviewRequests.nameWithOwner(fromRemote: result.stdout)
                else { continue }
                self?.remoteCache[path] = name
                names.insert(name)
                pathsByName[name.lowercased()] = pathsByName[name.lowercased()] ?? path
            }
            guard !Task.isCancelled else { return }
            self?.termqRepositories = names
            self?.termqRepositoryPaths = pathsByName
        }
    }

    /// The path of the TermQ repository named `repository` (`owner/name`, any case).
    func termqRepositoryPath(for repository: String) -> String? {
        termqRepositoryPaths[repository.lowercased()]
    }

    struct LoadError: Error {
        let message: String
    }

    nonisolated private static func load(
        ghPath: String, login: String, known: [String: Date]
    ) async -> Result<[ReviewRequest], LoadError> {
        let search: StackProcessResult
        do {
            search = try await StackProcessRunner.run(
                ghPath,
                [
                    "search", "prs", "--review-requested=@me", "--state=open", "--limit",
                    String(ReviewRequests.searchLimit), "--json",
                    ReviewRequests.searchFields,
                ],
                cwd: nil, env: ["GH_PROMPT_DISABLED": "1", "NO_COLOR": "1"])
        } catch {
            return .failure(LoadError(message: error.localizedDescription))
        }
        guard search.exitCode == 0, var found = ReviewRequests.decodeSearch(Data(search.stdout.utf8)) else {
            let reason = search.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(LoadError(message: reason.isEmpty ? "gh search prs failed" : reason))
        }
        let missing = ReviewRequests.applyKnown(&found, known: known)
        // In batches, to stay well inside GitHub's query limits. Without the
        // times the list still works, grouped by when PRs opened.
        var times: [Int: Date] = [:]
        for start in stride(from: 0, to: missing.count, by: timelineBatch) {
            let batch = Array(missing[start..<min(start + timelineBatch, missing.count)])
            guard
                let timeline = try? await StackProcessRunner.run(
                    ghPath,
                    ["api", "graphql", "-f", "query=\(ReviewRequests.timelineQuery(for: batch.map { found[$0] }))"],
                    cwd: nil, env: ["GH_PROMPT_DISABLED": "1"])
            else { continue }
            // Read partial data even when gh exits non-zero over one PR.
            for (offset, time) in ReviewRequests.requestTimes(fromGraphQL: Data(timeline.stdout.utf8), login: login) {
                times[start + offset] = time
            }
        }
        ReviewRequests.applyTimes(times, to: &found, asked: missing)
        return .success(found)
    }

    nonisolated private static let timelineBatch = 40
}
