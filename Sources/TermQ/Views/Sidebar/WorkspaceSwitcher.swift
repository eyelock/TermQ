import SwiftUI

/// Sidebar header control for choosing the active workspace (or "All").
///
/// A menu listing "All Repositories", each workspace, and "New Workspace…".
/// Selecting a row sets the active workspace on the store; the repository list
/// filters reactively. Full management (rename / delete / repo assignment) lives
/// in the manage sheet — this is selection plus quick-create only.
struct WorkspaceSwitcher: View {
    @ObservedObject var store: WorkspaceStore
    @State private var showNewWorkspace = false
    @State private var showManage = false

    private var activeName: String {
        store.activeWorkspaceId
            .flatMap { store.workspace(id: $0)?.name }
            ?? Strings.Sidebar.workspaceAll
    }

    var body: some View {
        Menu {
            menuRow(title: Strings.Sidebar.workspaceAll, isSelected: store.activeWorkspaceId == nil) {
                store.setActive(nil)
            }

            if !store.workspaces.isEmpty {
                Divider()
                ForEach(store.workspaces) { workspace in
                    menuRow(title: workspace.name, isSelected: store.activeWorkspaceId == workspace.id) {
                        store.setActive(workspace.id)
                    }
                }
            }

            Divider()
            Button {
                showNewWorkspace = true
            } label: {
                Label(Strings.Sidebar.workspaceNew, systemImage: "plus")
            }
            if !store.workspaces.isEmpty {
                Button {
                    showManage = true
                } label: {
                    Label(Strings.Sidebar.workspaceManage, systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(activeName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .foregroundColor(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(Strings.Sidebar.workspaceMenuHelp)
        .sheet(isPresented: $showNewWorkspace) {
            NewWorkspaceSheet(store: store)
        }
        .sheet(isPresented: $showManage) {
            ManageWorkspacesSheet(store: store)
        }
    }

    /// A selectable menu row that shows a checkmark when it is the active choice.
    @ViewBuilder
    private func menuRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// Quick-create sheet for a new workspace. Creates the workspace and makes it the
/// active selection so the user lands in the new (empty) context ready to add repos.
struct NewWorkspaceSheet: View {
    @ObservedObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Sidebar.workspaceNewTitle)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Sidebar.workspaceNameLabel)
                    .foregroundColor(.primary)
                TextField(Strings.Sidebar.workspaceNamePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button(Strings.Sidebar.cancelButton) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(Strings.Sidebar.workspaceCreate) {
                    let workspace = store.create(name: trimmedName)
                    store.setActive(workspace.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
