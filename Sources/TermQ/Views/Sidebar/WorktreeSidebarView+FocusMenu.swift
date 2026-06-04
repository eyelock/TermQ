import SwiftUI
import TermQCore
import TermQShared

// MARK: - Focus Menu Items

extension WorktreeSidebarView {
    /// "Run with Focus…" + "Quick Launch Focus" items shown at the top of every
    /// local worktree context menu. PR context is carried through when the
    /// worktree is a PR checkout; plain local worktrees launch without one.
    @ViewBuilder
    func worktreeFocusMenuItems(_ worktree: GitWorktree, repo: ObservableRepository) -> some View {
        let linkedPR = linkedPRNumber(for: worktree, repo: repo)
        let runHarnessId =
            ynhPersistence.runHarness(for: repo.path) ?? ynhPersistence.repoDefaultHarness(for: repo.path)
        let cachedFocuses: [String] =
            runHarnessId.flatMap { id in
                harnessRepository.cachedDetail(for: id)?.composition.focuses
            }.map { $0.keys.sorted() } ?? []

        Button {
            runWithFocusContext = RunWithFocusContext(worktree: worktree, repo: repo, prNumber: linkedPR)
        } label: {
            Label(Strings.RemotePRs.runWithFocus, systemImage: "eye")
        }
        if let runHarnessId, !cachedFocuses.isEmpty {
            Menu(Strings.RemotePRs.quickLaunchFocus) {
                ForEach(cachedFocuses, id: \.self) { focusName in
                    Button(Strings.RemotePRs.runFocusItem(focusName)) {
                        quickLaunchFocus(
                            focusName, worktree: worktree, repo: repo,
                            prNumber: linkedPR, harnessId: runHarnessId)
                    }
                }
            }
        }
    }
}
