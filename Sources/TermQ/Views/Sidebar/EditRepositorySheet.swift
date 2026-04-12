import SwiftUI
import TermQCore

/// Sheet for editing the display name and worktree base path of a registered repository.
struct EditRepositorySheet: View {
    let repo: ObservableRepository
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var worktreeBasePath: String

    init(repo: ObservableRepository, viewModel: WorktreeSidebarViewModel) {
        self.repo = repo
        self.viewModel = viewModel
        _name = State(initialValue: repo.name)
        _worktreeBasePath = State(initialValue: repo.worktreeBasePath ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Sidebar.editRepositoryTitle)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Sidebar.nameLabel)
                    .foregroundColor(.primary)
                TextField(Strings.Sidebar.namePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            PathInputField(
                label: Strings.Sidebar.worktreeBasePathLabel,
                path: $worktreeBasePath,
                helpText: Strings.Sidebar.worktreeBasePathHelp,
                validatePath: false
            )

            HStack {
                Spacer()
                Button(Strings.Common.cancel) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(Strings.Common.save) {
                    viewModel.updateRepository(
                        repo,
                        name: name,
                        worktreeBasePath: worktreeBasePath.isEmpty ? nil : worktreeBasePath
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
