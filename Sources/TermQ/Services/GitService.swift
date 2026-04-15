import Foundation
import TermQShared

/// Main-actor git service for the TermQ GUI app
///
/// A pure command executor — has no `@Published` properties and does not conform to
/// `ObservableObject`. Observable state (worktree lists, loading indicators) lives in
/// `WorktreeSidebarViewModel`, not here.
///
/// All methods delegate to `GitServiceShared` which contains the shared process-execution
/// logic. Git commands are fast enough that main-actor isolation is not a concern.
@MainActor
public class GitService {
    public static let shared = GitService()

    private init() {}

    // MARK: - Repository Validation

    /// Check whether `path` is inside a git repository.
    public func isGitRepo(path: String) async throws -> Bool {
        try await GitServiceShared.isGitRepo(path: path)
    }

    // MARK: - Worktree Operations

    /// List all worktrees for the repository at `repoPath`, including dirty state.
    ///
    /// Dirty checks run concurrently — one `git status --porcelain` per worktree.
    public func listWorktrees(repoPath: String) async throws -> [GitWorktree] {
        let worktrees = try await GitServiceShared.listWorktrees(repoPath: repoPath)
        return await withTaskGroup(of: (Int, Bool).self) { group in
            for (i, worktree) in worktrees.enumerated() {
                group.addTask {
                    let dirty = await GitServiceShared.isWorktreeDirty(worktreePath: worktree.path)
                    return (i, dirty)
                }
            }
            var results = Array(repeating: false, count: worktrees.count)
            for await (i, dirty) in group { results[i] = dirty }
            return worktrees.enumerated().map { i, wt in
                GitWorktree(
                    path: wt.path,
                    branch: wt.branch,
                    commitHash: wt.commitHash,
                    isMainWorktree: wt.isMainWorktree,
                    isLocked: wt.isLocked,
                    isDirty: results[i]
                )
            }
        }
    }

    /// Check out an existing local branch as a new worktree at `path`.
    public func checkoutBranchAsWorktree(repo: GitRepository, branch: String, path: String) async throws {
        try await GitServiceShared.checkoutBranchAsWorktree(
            repoPath: repo.path,
            branch: branch,
            worktreePath: path
        )
    }

    /// Add a new worktree at `worktreePath` checked out to a new branch `branch`.
    /// Pass `baseBranch` to start from a specific branch instead of HEAD.
    public func addWorktree(
        repo: GitRepository,
        branch: String,
        path: String,
        baseBranch: String? = nil
    ) async throws {
        try await GitServiceShared.addWorktree(
            repoPath: repo.path,
            branch: branch,
            worktreePath: path,
            baseBranch: baseBranch
        )
    }

    /// Remove the worktree at `worktreePath`.
    public func removeWorktree(repo: GitRepository, path: String) async throws {
        try await GitServiceShared.removeWorktree(repoPath: repo.path, worktreePath: path)
    }

    /// Force-delete a worktree even if it has uncommitted changes.
    public func forceDeleteWorktree(repoPath: String, worktreePath: String) async throws {
        _ = try await GitServiceShared.runGitCommand(
            repoPath: repoPath,
            args: ["worktree", "remove", "--force", worktreePath]
        )
    }

    /// Return the URL of the `origin` remote (raw git format, SSH or HTTPS).
    public func remoteURL(repoPath: String) async throws -> String {
        let output = try await GitServiceShared.runGitCommand(
            repoPath: repoPath,
            args: ["remote", "get-url", "origin"]
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lock the worktree at `path` to protect it during agent work.
    public func lockWorktree(repoPath: String, worktreePath: String) async throws {
        _ = try await GitServiceShared.runGitCommand(repoPath: repoPath, args: ["worktree", "lock", worktreePath])
    }

    /// Unlock the worktree at `path`.
    public func unlockWorktree(repoPath: String, worktreePath: String) async throws {
        _ = try await GitServiceShared.runGitCommand(repoPath: repoPath, args: ["worktree", "unlock", worktreePath])
    }

    /// Dry-run `git worktree prune` and return the list of stale entries that would be removed.
    /// Returns an empty array when nothing needs pruning.
    public func pruneWorktreesDryRun(repoPath: String) async throws -> [String] {
        let output = try await GitServiceShared.runGitCommand(
            repoPath: repoPath,
            args: ["worktree", "prune", "--dry-run"]
        )
        return
            output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Prune stale worktree administrative records.
    public func pruneWorktrees(repoPath: String) async throws {
        _ = try await GitServiceShared.runGitCommand(repoPath: repoPath, args: ["worktree", "prune"])
    }

    // MARK: - Branch Operations

    /// List local branches for the repository at `repoPath`.
    public func listBranches(repoPath: String) async throws -> [String] {
        let output = try await GitServiceShared.runGitCommand(
            repoPath: repoPath,
            args: ["branch", "--format=%(refname:short)"]
        )
        return
            output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Get the default branch for the repository.
    ///
    /// Uses `origin/HEAD` symref — the authoritative default branch regardless of what
    /// is currently checked out. Falls back to checking for "main"/"master" in the local
    /// branch list, then `"main"`.
    public func defaultBranch(repoPath: String) async -> String {
        // origin/HEAD is set by the remote and doesn't change with local checkouts.
        // --short returns "origin/main" (or "origin/feature/main" for slash-names).
        // Strip only the first component (remote name) to preserve slashes in branch names.
        if let output = try? await GitServiceShared.runGitCommand(
            repoPath: repoPath,
            args: ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"]
        ) {
            let raw = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let slash = raw.firstIndex(of: "/") {
                let branch = String(raw[raw.index(after: slash)...])
                if !branch.isEmpty { return branch }
            }
        }
        // Fallback: check for conventional default branch names
        if let branches = try? await listBranches(repoPath: repoPath) {
            if branches.contains("main") { return "main" }
            if branches.contains("master") { return "master" }
        }
        return "main"
    }

    /// Get the currently checked-out branch name at `path`.
    ///
    /// Returns `nil` for detached HEAD.
    public func getCurrentBranch(path: String) async throws -> String? {
        try await GitServiceShared.getCurrentBranch(path: path)
    }

    /// Get the `origin` remote URL for the repository at `path`.
    public func getRemoteName(path: String) async throws -> String {
        try await GitServiceShared.getRemoteName(path: path)
    }

    /// Derive a display name from a remote URL or directory name.
    ///
    /// Strips `.git` suffix and takes the last path component.
    /// Falls back to the last component of `repoPath` if remote lookup fails.
    public func inferRepoName(repoPath: String) async -> String {
        if let remote = try? await getRemoteName(path: repoPath) {
            let stripped = remote.hasSuffix(".git") ? String(remote.dropLast(4)) : remote
            if let name = stripped.components(separatedBy: "/").last, !name.isEmpty {
                return name
            }
        }
        return URL(fileURLWithPath: repoPath).lastPathComponent
    }
}
