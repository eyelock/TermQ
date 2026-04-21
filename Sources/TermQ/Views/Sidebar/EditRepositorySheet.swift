import SwiftUI
import TermQCore

/// Sheet for editing the display name and worktree base path of a registered repository.
struct EditRepositorySheet: View {
    let repo: ObservableRepository
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var worktreeBasePath: String
    @State private var protectedBranchesText: String

    init(repo: ObservableRepository, viewModel: WorktreeSidebarViewModel) {
        self.repo = repo
        self.viewModel = viewModel
        _name = State(initialValue: repo.name)
        _worktreeBasePath = State(initialValue: repo.worktreeBasePath ?? "")
        _protectedBranchesText = State(initialValue: repo.protectedBranches?.joined(separator: ", ") ?? "")
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

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Sidebar.protectedBranchesOverrideLabel)
                    .foregroundColor(.primary)
                TextField(Strings.Sidebar.protectedBranchesOverridePlaceholder, text: $protectedBranchesText)
                    .textFieldStyle(.roundedBorder)
                Text(Strings.Sidebar.protectedBranchesOverrideHelp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button(Strings.Common.cancel) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(Strings.Common.save) {
                    let parsed =
                        protectedBranchesText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let parsedOverride: [String]? = parsed.isEmpty ? nil : parsed
                    viewModel.updateRepository(
                        repo,
                        name: name,
                        worktreeBasePath: worktreeBasePath.isEmpty ? nil : worktreeBasePath,
                        protectedBranches: parsedOverride
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
