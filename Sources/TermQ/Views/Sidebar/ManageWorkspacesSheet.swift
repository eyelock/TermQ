import SwiftUI

/// Sheet for renaming and deleting workspaces.
///
/// Repo assignment lives in the per-repo right-click menu, not here — this sheet
/// is purely workspace lifecycle (rename / delete). Deleting a workspace never
/// removes the repositories in it; it only drops the grouping.
struct ManageWorkspacesSheet: View {
    @ObservedObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var workspaceToDelete: Workspace?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Strings.Sidebar.workspaceManageTitle)
                .font(.title2)
                .fontWeight(.semibold)

            if store.workspaces.isEmpty {
                Text(Strings.Sidebar.workspaceManageEmpty)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(store.workspaces) { workspace in
                        WorkspaceManageRow(workspace: workspace, store: store) {
                            workspaceToDelete = workspace
                        }
                    }
                }
                .frame(minHeight: 160)
            }

            HStack {
                Spacer()
                Button(Strings.Sidebar.workspaceManageDone) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .alert(Strings.Sidebar.workspaceDeleteTitle, isPresented: deleteAlertBinding) {
            Button(Strings.Sidebar.cancelButton, role: .cancel) { workspaceToDelete = nil }
            Button(Strings.Sidebar.workspaceDeleteConfirm, role: .destructive) {
                if let workspace = workspaceToDelete { store.delete(workspace.id) }
                workspaceToDelete = nil
            }
        } message: {
            if let workspace = workspaceToDelete {
                Text(Strings.Sidebar.workspaceDeleteMessage(workspace.name))
            }
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { workspaceToDelete != nil },
            set: { if !$0 { workspaceToDelete = nil } }
        )
    }
}

/// One editable row: rename via the text field (commits on Enter or focus loss),
/// delete via the trash button.
private struct WorkspaceManageRow: View {
    let workspace: Workspace
    @ObservedObject var store: WorkspaceStore
    let onDelete: () -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            TextField("", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help(Strings.Sidebar.workspaceDeleteConfirm)
        }
        .onAppear { name = workspace.name }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            name = workspace.name  // revert empty edits
        } else if trimmed != workspace.name {
            store.rename(workspace.id, to: trimmed)
        }
    }
}
