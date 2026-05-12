import Foundation
import TermQCore
import TermQShared

// MARK: - Focus Worktree Lifecycle

extension WorktreeSidebarViewModel {
    /// Derive the stable focus-worktree path for a PR without a local checkout.
    ///
    /// Format: `~/.termq/focus-worktrees/termq-focus--<host>--<org>--<repo>--<branch>--<pr>`
    /// The `termq-focus-` prefix is the sentinel used in `refreshWorktrees` to exclude these
    /// from the Local tab and route them into `focusWorktrees[repo.id]`.
    func inferFocusWorktreePath(for repo: ObservableRepository, pr: GitHubPR) async -> String {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".termq/focus-worktrees")
        var repoKey: String
        if let raw = try? await gitService.remoteURL(repoPath: repo.path),
            let key = Self.remoteRepoKey(from: raw)
        {
            repoKey = key
        } else {
            repoKey = URL(fileURLWithPath: repo.path).lastPathComponent
        }
        let branchSlug = String(
            pr.headRefName.lowercased().map {
                $0.isLetter || $0.isNumber || $0 == "-" ? $0 : Character("-")
            })
        let name = "termq-focus--\(repoKey)--\(branchSlug)--\(pr.number)"
        return base.appendingPathComponent(name).path
    }

    /// Create (or reuse) a focus worktree for a remote PR, then return it.
    ///
    /// The path is derived from the PR's remote coordinates and is stable across multiple
    /// "Run with Focus" invocations on the same PR, so the worktree is reused if it exists.
    func checkoutPRForFocus(
        _ pr: GitHubPR,
        repo: ObservableRepository,
        ghPath: String
    ) async throws -> GitWorktree {
        let worktreePath = await inferFocusWorktreePath(for: repo, pr: pr)
        if let existing = focusWorktrees[repo.id]?.first(where: { $0.path == worktreePath }) {
            return existing
        }
        let parentPath = URL(fileURLWithPath: worktreePath).deletingLastPathComponent().path
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(
                atPath: parentPath, withIntermediateDirectories: true, attributes: nil)
        }.value
        try await gitService.addDetachedWorktree(repoPath: repo.path, path: worktreePath)
        let result = try await CommandRunner.run(
            executable: ghPath,
            arguments: ["pr", "checkout", "\(pr.number)"],
            currentDirectory: worktreePath
        )
        guard result.didSucceed else {
            try? await gitService.removeWorktree(repo: repo.toGitRepository(), path: worktreePath)
            throw GitHubPRError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
        guard let wt = focusWorktrees[repo.id]?.first(where: { $0.path == worktreePath }) else {
            throw GitHubPRError.commandFailed("Focus worktree not found after checkout")
        }
        return wt
    }

    /// Remove focus worktrees by path and refresh the worktree list.
    func pruneFocusWorktrees(repo: ObservableRepository, paths: [String]) async {
        for path in paths {
            try? await gitService.removeWorktree(repo: repo.toGitRepository(), path: path)
        }
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    /// Parse a git remote URL into a `--`-separated host/org/repo key.
    ///
    /// Handles both SSH (`git@host:org/repo.git`) and HTTPS (`https://host/org/repo`) forms.
    private static func remoteRepoKey(from remoteURL: String) -> String? {
        var urlString = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlString.hasPrefix("git@") {
            urlString = String(urlString.dropFirst(4))
            if let colon = urlString.firstIndex(of: ":") {
                let host = String(urlString[urlString.startIndex..<colon])
                let path = String(urlString[urlString.index(after: colon)...])
                urlString = "https://\(host)/\(path)"
            }
        }
        if urlString.hasSuffix(".git") { urlString = String(urlString.dropLast(4)) }
        if urlString.hasSuffix("/") { urlString = String(urlString.dropLast()) }
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        let parts = url.pathComponents.filter { !$0.isEmpty && $0 != "/" }
        return ([host] + parts).joined(separator: "--")
    }
}
