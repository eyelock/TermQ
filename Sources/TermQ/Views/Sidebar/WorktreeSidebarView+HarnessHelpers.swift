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
