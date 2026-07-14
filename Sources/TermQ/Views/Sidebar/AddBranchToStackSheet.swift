import SwiftUI
import TermQCore
import TermQShared

/// Sheet for adding a branch to a worktree's stack.
///
/// New names run the provider's create (staged changes become the branch's first
/// commit — surfaced in the sheet copy); a name matching an existing local branch is
/// tracked onto the stack instead, with the note and button label switching to say so.
/// The decision itself lives in `WorktreeSidebarViewModel.addBranchToStack`.
struct AddBranchToStackSheet: View {
    let repo: ObservableRepository
    let worktree: GitWorktree
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var branchName: String = ""
    @State private var target: String = ""
    @State private var existingBranches: [String] = []
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?

    private var branchExists: Bool {
        existingBranches.contains(branchName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Stacks.addBranchTitle)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Stacks.addBranchNameLabel)
                    .foregroundColor(.primary)
                TextField(Strings.Stacks.addBranchNamePlaceholder, text: $branchName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Stacks.addBranchTargetLabel)
                    .foregroundColor(.primary)
                TextField("", text: $target)
                    .textFieldStyle(.roundedBorder)
            }

            Text(branchExists ? Strings.Stacks.addBranchTrackNote : Strings.Stacks.addBranchStagedNote)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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

                Button(branchExists ? Strings.Stacks.addBranchTrack : Strings.Stacks.addBranchCreate) {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.isEmpty || isWorking)
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(isWorking)
        .onAppear {
            target = worktree.branch ?? ""
            Task {
                existingBranches = (try? await viewModel.listBranches(for: repo)) ?? []
            }
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await viewModel.addBranchToStack(
                repo: repo,
                worktree: worktree,
                name: branchName,
                target: target.isEmpty ? nil : target
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
