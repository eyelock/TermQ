import Foundation
import TermQCore
import TermQShared

// MARK: - Default Branch / origin/HEAD

extension WorktreeSidebarViewModel {
    /// Return the default branch for a repo via `origin/HEAD` symref.
    func defaultBranch(for repo: ObservableRepository) async -> String {
        await gitService.defaultBranch(repoPath: repo.path)
    }

    /// Refresh `origin/HEAD` from the remote without a full worktree reload.
    ///
    /// Used before reading `defaultBranch` in user-facing flows (e.g. opening the
    /// New Worktree sheet) so the default reflects the remote's current default even
    /// for repos whose remote default changed after they were added. Failures are
    /// silent — we fall back to the existing (possibly stale) symref.
    func refreshRemoteHead(for repo: ObservableRepository) async {
        await gitService.updateRemoteHead(repoPath: repo.path)
    }
}
