import SwiftUI
import TermQCore
import TermQShared

// MARK: - Focus Menu Items

extension WorktreeSidebarView {
    /// The launch group at the top of every local worktree menu (Quick Launch,
    /// Launch…, Launch with Focus), for the worktree's harness: its own, else
    /// the repository's default, the same one a click on the row launches. PR
    /// context is carried through when the worktree is a PR checkout.
    @ViewBuilder
    func worktreeFocusMenuItems(_ worktree: GitWorktree, repo: ObservableRepository) -> some View {
        let linkedPR = linkedPRNumber(for: worktree, repo: repo)
        let harness =
            ynhPersistence.harness(for: worktree.path) ?? ynhPersistence.repoDefaultHarness(for: repo.path)
        let focusHarness = harness ?? ynhPersistence.runHarness(for: repo.path)
        let cachedFocuses: [String] =
            focusHarness.flatMap { id in
                harnessRepository.cachedDetail(for: id)?.composition.focuses
            }.map { $0.keys.sorted() } ?? []

        LaunchMenuItems(
            name: harness.map(harnessDisplayName),
            quickLaunch: harness.map { name in { onAutoLaunchHarness?(name, worktree.path, worktree.branch) } },
            openSheet: {
                var context = RunWithFocusContext(worktree: worktree, repo: repo, prNumber: linkedPR)
                if let harness { context.preferredHarnessId = harness }
                runWithFocusContext = context
            },
            focuses: focusHarness.map { harnessId in
                cachedFocuses.map { focusName in
                    LaunchMenuItems.Focus(name: focusName) {
                        quickLaunchFocus(
                            focusName, worktree: worktree, repo: repo, prNumber: linkedPR, harnessId: harnessId)
                    }
                }
            } ?? [])
    }

    /// A harness's name for a menu label, from its id or name.
    func harnessDisplayName(_ id: String) -> String {
        harnessRepository.harnesses.first { $0.id == id || $0.name == id }?.name ?? id
    }
}
