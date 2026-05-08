import Foundation
import TermQShared

/// Wrapper around the `gh pr list --json ...` envelope.
private struct GhPRListEnvelope: Decodable {
    let items: [GitHubPR]

    init(from decoder: Decoder) throws {
        // `gh pr list --json` returns a top-level array, not a keyed container.
        var c = try decoder.unkeyedContainer()
        var prs: [GitHubPR] = []
        while !c.isAtEnd {
            if let pr = try? c.decode(GitHubPR.self) {
                prs.append(pr)
            } else {
                _ = try? c.decode(EmptyDecodable.self)
            }
        }
        items = prs
    }
}

private struct EmptyDecodable: Decodable {}

// MARK: - Service

/// Fetches and caches open GitHub PRs for registered repositories.
///
/// Architecture mirrors `GitService`/`HarnessRepository`:
/// - `@MainActor` singleton with `@Published` state
/// - 60-second TTL per repo with single-flight coalescing on automatic triggers
/// - Manual `↻` bypasses the TTL
/// - Force-push detection: emits `forcePushedPRs` when `headRefOid` changes between
///   refreshes for a PR with a paired local worktree
@MainActor
final class GitHubPRService: ObservableObject {
    static let shared = GitHubPRService()

    // MARK: - Published state

    /// Open PRs per repo path.
    @Published private(set) var prsByRepo: [String: [GitHubPR]] = [:]
    /// Which repos are currently fetching.
    @Published private(set) var loadingRepos: Set<String> = []
    /// Last fetch error per repo path.
    @Published private(set) var errorByRepo: [String: String] = [:]
    /// PR numbers whose head SHA changed between refreshes (force-push detected).
    @Published private(set) var forcePushedPRs: [String: Set<Int>] = [:]

    // MARK: - Private state

    private let ttl: TimeInterval = 60
    private var lastFetchTime: [String: Date] = [:]
    private var inflightTasks: [String: Task<[GitHubPR], Error>] = [:]
    /// Previous head SHAs — keyed by repoPath, then PR number.
    private var previousHeadOids: [String: [Int: String]] = [:]

    private let ghProbe: GhCliProbe
    private let commandRunner: any YNHCommandRunner

    init(ghProbe: GhCliProbe = .shared, commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.ghProbe = ghProbe
        self.commandRunner = commandRunner
    }

    // MARK: - Public API

    /// Refresh PRs for a single repo. Respects the 60s TTL unless `force: true`.
    func refresh(repoPath: String, force: Bool = false) async {
        guard case .ready(let ghPath, _) = ghProbe.status else { return }

        // TTL gate (bypassed by force).
        if !force,
            let last = lastFetchTime[repoPath],
            Date().timeIntervalSince(last) < ttl
        {
            return
        }

        // Single-flight coalescing: if a fetch is already inflight, await it.
        if let existing = inflightTasks[repoPath] {
            _ = try? await existing.value
            return
        }

        let task = Task<[GitHubPR], Error> { [weak self] in
            guard let self else { return [] }
            return try await self.fetchPRs(repoPath: repoPath, ghPath: ghPath)
        }
        inflightTasks[repoPath] = task

        loadingRepos.insert(repoPath)

        do {
            let prs = try await task.value
            detectForcePushes(repoPath: repoPath, newPRs: prs)
            prsByRepo[repoPath] = prs
            errorByRepo.removeValue(forKey: repoPath)
            lastFetchTime[repoPath] = Date()
        } catch {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.ui.warning("GitHubPRService: fetch failed for \(repoPath): \(error)")
            } else {
                TermQLogger.ui.warning("GitHubPRService: fetch failed")
            }
            errorByRepo[repoPath] = error.localizedDescription
        }

        inflightTasks.removeValue(forKey: repoPath)
        loadingRepos.remove(repoPath)
    }

    /// Refresh all repos for which PRs have been loaded before. Used on window focus / app launch.
    func refreshAll(force: Bool = false) async {
        let repos = Array(Set(prsByRepo.keys).union(loadingRepos))
        for repoPath in repos {
            await refresh(repoPath: repoPath, force: force)
        }
    }

    /// Remove all cached state for a repo (e.g. after it is removed from the sidebar).
    func evict(repoPath: String) {
        prsByRepo.removeValue(forKey: repoPath)
        errorByRepo.removeValue(forKey: repoPath)
        lastFetchTime.removeValue(forKey: repoPath)
        forcePushedPRs.removeValue(forKey: repoPath)
        previousHeadOids.removeValue(forKey: repoPath)
        inflightTasks[repoPath]?.cancel()
        inflightTasks.removeValue(forKey: repoPath)
        loadingRepos.remove(repoPath)
    }

    /// Clear the force-push flag for a PR (called after Update from Origin completes).
    func clearForcePush(repoPath: String, prNumber: Int) {
        forcePushedPRs[repoPath]?.remove(prNumber)
    }

    // MARK: - PR ↔ worktree matching

    /// Match open PRs against a set of local worktrees.
    ///
    /// Primary key: `headRefOid` (SHA). Falls back to `headRefName` / localBranchName()
    /// when the worktree's commit hasn't been fetched yet and the SHA doesn't match.
    static func matchPRsToWorktrees(
        prs: [GitHubPR],
        worktrees: [GitWorktree]
    ) -> [Int: String] {
        var result: [Int: String] = [:]
        for pr in prs {
            // SHA-first match
            if let wt = worktrees.first(where: {
                $0.commitHash.hasPrefix(pr.headRefOid.prefix(7))
                    || $0.commitHash == pr.headRefOid
            }) {
                result[pr.number] = wt.path
                continue
            }
            // Branch name fallback
            let localBranch = pr.localBranchName()
            if let wt = worktrees.first(where: { $0.branch == localBranch }) {
                result[pr.number] = wt.path
            }
        }
        return result
    }

    // MARK: - Private

    private func fetchPRs(repoPath: String, ghPath: String) async throws -> [GitHubPR] {
        let result = try await commandRunner.run(
            executable: ghPath,
            arguments: [
                "pr", "list",
                "--limit", "200",
                "--state", "open",
                "--json",
                "number,title,headRefName,headRefOid,author,isCrossRepository,isDraft,reviewRequests,assignees",
            ],
            environment: nil,
            currentDirectory: repoPath,
            onStdoutLine: nil,
            onStderrLine: nil
        )

        guard result.didSucceed else {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitHubPRError.commandFailed(msg.isEmpty ? "unknown error" : msg)
        }

        let data = Data(result.stdout.utf8)
        return try JSONDecoder().decode([GitHubPR].self, from: data)
    }

    private func detectForcePushes(repoPath: String, newPRs: [GitHubPR]) {
        let previous = previousHeadOids[repoPath] ?? [:]
        var detected: Set<Int> = forcePushedPRs[repoPath] ?? []

        for pr in newPRs {
            if let prevOid = previous[pr.number], prevOid != pr.headRefOid {
                detected.insert(pr.number)
            }
        }

        // Update previous OID map
        var newOids: [Int: String] = [:]
        for pr in newPRs { newOids[pr.number] = pr.headRefOid }
        previousHeadOids[repoPath] = newOids

        forcePushedPRs[repoPath] = detected
    }
}

// MARK: - Errors

enum GitHubPRError: Error, LocalizedError, Sendable {
    case commandFailed(String)
    case noGitHubRemote

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return "gh command failed: \(msg)"
        case .noGitHubRemote: return "No GitHub remote configured"
        }
    }
}
