import SwiftUI
import TermQCore
import TermQShared

// MARK: - Repo Row Label

extension WorktreeSidebarView {
    @ViewBuilder
    func repoLabel(_ repo: ObservableRepository) -> some View {
        HStack {
            Label(repo.name, systemImage: "shippingbox")
                .lineLimit(1)

            Spacer()

            if let harnessId = ynhPersistence.repoDefaultHarness(for: repo.path) {
                Button {
                    harnessRepository.selectedHarnessId = harnessId
                } label: {
                    Image(systemName: "puzzlepiece.extension")
                        .imageScale(.small)
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help(Strings.Sidebar.linkedHarness(harnessId))
            }

            // In-progress indication for stack mutations (sync can take seconds of
            // network time): the refresh affordance becomes a spinner for the
            // duration, and can't re-trigger while one is in flight.
            if stackService.isMutating(repo: repo.path) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .opacity(viewModel.expandedRepoIDs.contains(repo.id) ? 1 : 0)
            } else {
                Button {
                    Task {
                        let report = await viewModel.refreshRepo(for: repo)
                        if let report, stackService.conflicts[repo.path] == nil {
                            // The sync path ran — always confirm the outcome
                            // (a conflict pause is reported by the banner instead).
                            showStackToast(syncToastMessage(for: report))
                        }
                        if sidebarMode == .remote {
                            await prService.refresh(repoPath: repo.path, force: true)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .help(Strings.Sidebar.refreshWorktrees)
                .opacity(viewModel.expandedRepoIDs.contains(repo.id) ? 1 : 0)
            }
        }
    }
}
