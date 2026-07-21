import SwiftUI
import TermQCore

// MARK: - Workspace view helpers

extension WorktreeSidebarView {
    /// Empty-state dispatcher. An active workspace with no visible members gets a
    /// dedicated message and a quick route into management; the unfiltered ("All")
    /// view keeps the original "add a repository" prompt. The store normalizes
    /// dangling active ids to `nil`, so a non-nil id here always names a real,
    /// empty workspace.
    @ViewBuilder
    var emptyState: some View {
        if workspaceStore.activeWorkspaceId != nil {
            workspaceEmptyState
        } else {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text(Strings.Sidebar.emptyMessage)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private var workspaceEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(Strings.Sidebar.workspaceEmptyMessage)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(Strings.Sidebar.workspaceManage) { showManageWorkspaces = true }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Drag-to-reorder maps positions into the full repository list, so it is only
    /// valid in the unfiltered "All" view; disabled while a workspace filter is
    /// active (per-workspace ordering is out of scope).
    var reorderHandler: ((IndexSet, Int) -> Void)? {
        guard workspaceStore.activeWorkspaceId == nil else { return nil }
        return { from, to in viewModel.moveRepository(from: from, to: to) }
    }

    /// Repo context-menu submenu to toggle this repo's membership in each
    /// workspace. A checkmark marks the workspaces it already belongs to;
    /// selecting a row adds or removes it. Disabled when no workspaces exist.
    @ViewBuilder
    func addToWorkspaceMenu(for repo: ObservableRepository) -> some View {
        Menu(Strings.Sidebar.workspaceAddTo) {
            ForEach(workspaceStore.workspaces) { workspace in
                let isMember = workspaceStore.contains(repoId: repo.id, in: workspace.id)
                Button {
                    if isMember {
                        workspaceStore.remove(repoId: repo.id, from: workspace.id)
                    } else {
                        workspaceStore.add(repoId: repo.id, to: workspace.id)
                    }
                } label: {
                    if isMember {
                        Label(workspace.name, systemImage: "checkmark")
                    } else {
                        Text(workspace.name)
                    }
                }
            }
        }
        .disabled(workspaceStore.workspaces.isEmpty)
    }
}
