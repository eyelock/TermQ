import SwiftUI
import TermQCore

/// Sheet for converting an existing local branch into a worktree.
///
/// Unlike `NewWorktreeSheet`, this does not create a new branch — it checks the
/// selected branch out at a worktree path. The branch name is editable so the
/// user can normalize a loose name (e.g. `my-stuff` → `feat/my-stuff`) as part
/// of the conversion; if changed, `git branch -m` runs before `git worktree add`.
struct ConvertToWorktreeSheet: View {
    let repo: ObservableRepository
    let originalBranch: String
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var branchName: String = ""
    @State private var path: String = ""
    @State private var isConverting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Sidebar.convertWorktreeTitle)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Sidebar.convertWorktreeBranchLabel)
                    .foregroundColor(.primary)
                TextField(Strings.Sidebar.branchNamePlaceholder, text: $branchName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: branchName) { _, newValue in
                        path = viewModel.inferWorktreePath(for: repo, branchName: newValue)
                    }
            }

            PathInputField(
                label: Strings.Sidebar.worktreePathLabel,
                path: $path,
                placeholder: viewModel.inferWorktreePath(for: repo, branchName: Strings.Sidebar.branchNamePlaceholder),
                validatePath: false
            )

            if let msg = errorMessage {
                Text(msg)
                    .foregroundColor(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(Strings.Sidebar.cancelButton) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(Strings.Sidebar.convertWorktreeButton) {
                    Task { await convert() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.isEmpty || path.isEmpty || isConverting)
                .help(
                    branchName.isEmpty
                        ? Strings.Sidebar.newWorktreeBranchRequired
                        : path.isEmpty ? Strings.Sidebar.newWorktreePathRequired : ""
                )
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(isConverting)
        .onAppear {
            branchName = originalBranch
            path = viewModel.inferWorktreePath(for: repo, branchName: originalBranch)
        }
    }

    private func convert() async {
        isConverting = true
        defer { isConverting = false }
        errorMessage = nil
        do {
            try await viewModel.convertBranchToWorktree(
                repo: repo,
                originalBranch: originalBranch,
                newBranch: branchName,
                path: path
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
