import AppKit
import SwiftUI
import TermQCore
import TermQShared

// MARK: - Harness Helpers

extension WorktreeSidebarView {
    /// Jigsaw badge for worktree rows.
    ///
    /// Orange = explicit override on this worktree; dim = inherited from repo default.
    /// The repo header separately shows a green badge when a default is configured.
    @ViewBuilder
    func harnessRowBadge(for worktree: GitWorktree, repo: ObservableRepository) -> some View {
        if let harnessId = ynhPersistence.harness(for: worktree.path) {
            Button {
                harnessRepository.selectedHarnessId = harnessId
            } label: {
                Image(systemName: "puzzlepiece.extension")
                    .imageScale(.small)
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .help(harnessId)
        } else if let inherited = ynhPersistence.repoDefaultHarness(for: repo.path) {
            Button {
                harnessRepository.selectedHarnessId = inherited
            } label: {
                Image(systemName: "puzzlepiece.extension")
                    .imageScale(.small)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(inherited)
        }
    }

    @ViewBuilder
    func harnessContextItems(forPath path: String) -> some View {
        let linked = ynhPersistence.harness(for: path)
        Menu {
            if linked != nil {
                Button(Strings.Sidebar.clearHarness) {
                    ynhPersistence.setHarness(nil, for: path)
                }
                Divider()
            }
            ForEach(harnessRepository.harnesses) { harness in
                Button(harness.name) {
                    ynhPersistence.setHarness(harness.id, for: path)
                }
            }
        } label: {
            if let linked {
                Label(Strings.Sidebar.linkedHarness(linked), systemImage: "puzzlepiece.extension")
            } else {
                Label(Strings.Sidebar.setHarness, systemImage: "puzzlepiece.extension")
            }
        }
    }

    /// Stack-scoped "Set Harness" menu — writes the stack-level override (keyed by the
    /// stack's root branch name), independent from worktree/repo overrides. Available
    /// for ALL stacks, anchored or not (Revision 11c) — unlike the worktree-scoped
    /// `harnessContextItems(forPath:)`, this never needs a worktree path.
    @ViewBuilder
    func stackHarnessContextItems(repoPath: String, rootName: String) -> some View {
        let linked = ynhPersistence.stackHarness(repoPath: repoPath, rootName: rootName)
        Menu {
            if linked != nil {
                Button(Strings.Sidebar.clearHarness) {
                    ynhPersistence.setStackHarness(nil, repoPath: repoPath, rootName: rootName)
                }
                Divider()
            }
            ForEach(harnessRepository.harnesses) { harness in
                Button(harness.name) {
                    ynhPersistence.setStackHarness(harness.id, repoPath: repoPath, rootName: rootName)
                }
            }
        } label: {
            if let linked {
                Label(Strings.Sidebar.linkedHarness(linked), systemImage: "puzzlepiece.extension")
            } else {
                Label(Strings.Sidebar.setHarness, systemImage: "puzzlepiece.extension")
            }
        }
    }

    /// Jigsaw badge for STACKS group rows (Revision 11b) — mirrors `harnessRowBadge`'s
    /// visual language (orange = explicit override, dim = inherited repo default,
    /// hidden = none), but resolves per the stack resolution order: stack override →
    /// owning/anchoring worktree override → repo default.
    @ViewBuilder
    func stackGroupHarnessBadge(rootName: String, anchoringPath: String?, repo: ObservableRepository) -> some View {
        let stackOverride = ynhPersistence.stackHarness(repoPath: repo.path, rootName: rootName)
        let worktreeOverride = anchoringPath.flatMap { ynhPersistence.harness(for: $0) }
        if let explicit = stackOverride ?? worktreeOverride {
            Button {
                harnessRepository.selectedHarnessId = explicit
            } label: {
                Image(systemName: "puzzlepiece.extension")
                    .imageScale(.small)
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .help(explicit)
        } else if let inherited = ynhPersistence.repoDefaultHarness(for: repo.path) {
            Button {
                harnessRepository.selectedHarnessId = inherited
            } label: {
                Image(systemName: "puzzlepiece.extension")
                    .imageScale(.small)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(inherited)
        }
    }

    /// Context items for setting the repository-level default harness.
    /// Reads/writes `repoHarness` — independent from worktree overrides.
    @ViewBuilder
    func repoDefaultHarnessContextItems(for repo: ObservableRepository) -> some View {
        let linked = ynhPersistence.repoDefaultHarness(for: repo.path)
        Menu {
            if linked != nil {
                Button(Strings.Sidebar.clearHarness) {
                    ynhPersistence.setRepoDefaultHarness(nil, for: repo.path)
                }
                Divider()
            }
            ForEach(harnessRepository.harnesses) { harness in
                Button(harness.name) {
                    ynhPersistence.setRepoDefaultHarness(harness.id, for: repo.path)
                }
            }
        } label: {
            if let linked {
                Label(Strings.Sidebar.linkedHarness(linked), systemImage: "puzzlepiece.extension")
            } else {
                Label(Strings.Sidebar.setHarness, systemImage: "puzzlepiece.extension")
            }
        }
    }

}
