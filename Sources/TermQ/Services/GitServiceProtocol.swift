import TermQShared

@MainActor
protocol GitServiceProtocol: AnyObject {
    func isGitRepo(path: String) async throws -> Bool
    func listWorktrees(repoPath: String) async throws -> [GitWorktree]
    func addWorktree(repo: GitRepository, branch: String, path: String, baseBranch: String?) async throws
    func removeWorktree(repo: GitRepository, path: String) async throws
    func forceDeleteWorktree(repoPath: String, worktreePath: String) async throws
    func lockWorktree(repoPath: String, worktreePath: String) async throws
    func unlockWorktree(repoPath: String, worktreePath: String) async throws
    func pruneWorktreesDryRun(repoPath: String) async throws -> [String]
    func pruneWorktrees(repoPath: String) async throws
    func listBranches(repoPath: String) async throws -> [String]
    func mergedLocalBranches(repoPath: String) async throws -> [String]
    func deleteLocalBranch(repoPath: String, branch: String) async throws
    func forceDeleteLocalBranch(repoPath: String, branch: String) async throws
    func fetchBranchFromOrigin(repoPath: String, branch: String) async throws
    func pullBranch(worktreePath: String) async throws
    func defaultBranch(repoPath: String) async -> String
    func updateRemoteHead(repoPath: String) async
    func inferRepoName(repoPath: String) async -> String
}
