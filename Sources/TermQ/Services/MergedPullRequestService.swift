import Foundation
import TermQShared

/// Which of a repository's pull requests have been merged.
///
/// ## Why this exists
///
/// gh-stack's tracking file records a branch's pull request number and nothing about its
/// state, and `graph()` is deliberately offline — tracking file plus `git worktree list`,
/// on every sidebar refresh. So a merged stack kept rendering as open indefinitely: the
/// merge confirmation would say "Already merged" against every pull request while the
/// sidebar behind it still showed them as live.
///
/// Merging through TermQ is not enough to know this. A stack merged on github.com, or by
/// a teammate, or in a previous run of the app, is the same situation — remembering only
/// what this process did leaves the sidebar wrong in every other case, and wrong again
/// after a restart.
///
/// ## Why it is one bounded call
///
/// `gh pr list --state merged --limit 100` is a single request whose cost does not grow
/// with the size of the stack, unlike the per-PR fan-out `StackMergeReadinessService`
/// uses. That service pays per PR because it needs review decisions and check rollups at
/// the moment of a merge decision; this one needs a single bit per pull request and is
/// paid on every repo refresh, so it must stay cheap.
///
/// The limit is a deliberate horizon rather than an attempt at completeness: a stack whose
/// merge is more than 100 merges old is long finished, and its branches will have been
/// cleaned up by then.
@MainActor
final class MergedPullRequestService: ObservableObject {
    static let shared = MergedPullRequestService()

    /// Merged pull request numbers per repo path.
    @Published private(set) var mergedByRepo: [String: Set<Int>] = [:]

    private let ttl: TimeInterval = 60
    private var lastFetch: [String: Date] = [:]
    private var inflight: [String: Task<Set<Int>, Never>] = [:]

    /// Resolved per call rather than captured: the probe fills `ghPath` in asynchronously
    /// at launch, so a value read at init time would be nil for the whole session.
    private let ghPathProvider: @MainActor () -> String?
    private let commandRunner: any YNHCommandRunner

    init(
        ghPathProvider: @escaping @MainActor () -> String? = { GhCliProbe.shared.status.ghPath },
        commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()
    ) {
        self.ghPathProvider = ghPathProvider
        self.commandRunner = commandRunner
    }

    /// Merged numbers already known for `repoPath`. Pure — never fetches.
    func mergedNumbers(repoPath: String) -> Set<Int> {
        mergedByRepo[repoPath] ?? []
    }

    /// Refresh the merged set. Respects a 60s TTL unless `force`, and coalesces
    /// concurrent callers onto one request — every stack refresh calls this.
    @discardableResult
    func refresh(repoPath: String, force: Bool = false) async -> Set<Int> {
        if let existing = inflight[repoPath] { return await existing.value }
        if !force, let last = lastFetch[repoPath], Date().timeIntervalSince(last) < ttl {
            return mergedNumbers(repoPath: repoPath)
        }
        let task = Task { [weak self] () -> Set<Int> in
            guard let self else { return [] }
            return await self.fetch(repoPath: repoPath)
        }
        inflight[repoPath] = task
        let result = await task.value
        inflight.removeValue(forKey: repoPath)
        // A failed fetch must not erase what is already known: reporting a merged pull
        // request as open again on a transient gh failure is the regression this exists
        // to fix.
        if !result.isEmpty || mergedByRepo[repoPath] == nil {
            mergedByRepo[repoPath] = result
        }
        lastFetch[repoPath] = Date()
        return mergedByRepo[repoPath] ?? []
    }

    private func fetch(repoPath: String) async -> Set<Int> {
        guard let ghPath = ghPathProvider() else { return [] }
        guard
            let result = try? await commandRunner.run(
                executable: ghPath,
                arguments: [
                    "pr", "list", "--state", "merged", "--limit", "100", "--json", "number",
                ],
                environment: nil,
                currentDirectory: repoPath,
                onStdoutLine: nil,
                onStderrLine: nil
            ), result.didSucceed,
            let data = result.stdout.data(using: .utf8)
        else { return [] }
        struct Row: Decodable { let number: Int }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return Set(rows.map(\.number))
    }

    /// Drop everything known about a repo — used when it leaves the sidebar.
    func evict(repoPath: String) {
        mergedByRepo.removeValue(forKey: repoPath)
        lastFetch.removeValue(forKey: repoPath)
    }
}
