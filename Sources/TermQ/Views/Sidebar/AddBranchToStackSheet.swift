import SwiftUI
import TermQCore
import TermQShared

/// Sheet for adding a stacked branch — reused for three entry points, distinguished by
/// `context.insertion`:
/// - `.target`: the original "Add Branch to Stack…" (worktree menu) and the STACKS
///   group header's "New Stacked Branch…" (target pre-filled with the stack's tip).
///   New names run the provider's create (staged changes become the branch's first
///   commit); a name matching an existing local branch is tracked onto the stack
///   instead, with the note and button label switching to say so.
/// - `.below`/`.above`: "New Stacked Branch Before…/After…" on a chain entry — the
///   target field is replaced by a static insertion note, and submission checks the
///   reference branch out first (guarded) before creating with the position flag.
/// The decision itself lives in `WorktreeSidebarViewModel`.
struct AddBranchToStackSheet: View {
    let repo: ObservableRepository
    let worktree: GitWorktree
    let insertion: AddBranchToStackContext.Insertion
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

    private var sheetTitle: String {
        switch insertion {
        case .target: return Strings.Stacks.addBranchTitle
        case .below: return Strings.Stacks.newBranchBefore
        case .above: return Strings.Stacks.newBranchAfter
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(sheetTitle)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Stacks.addBranchNameLabel)
                    .foregroundColor(.primary)
                TextField(Strings.Stacks.addBranchNamePlaceholder, text: $branchName)
                    .textFieldStyle(.roundedBorder)
            }

            switch insertion {
            case .target:
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
            case .below(let reference):
                Text(Strings.Stacks.newBranchInsertBelowNote(reference))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .above(let reference):
                Text(Strings.Stacks.newBranchInsertAboveNote(reference))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

                Button(submitButtonLabel) {
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
            if case .target(let initialTarget) = insertion {
                target = initialTarget
            }
            Task {
                existingBranches = (try? await viewModel.listBranches(for: repo)) ?? []
            }
        }
    }

    private var submitButtonLabel: String {
        switch insertion {
        case .target:
            return branchExists ? Strings.Stacks.addBranchTrack : Strings.Stacks.addBranchCreate
        case .below, .above:
            return Strings.Stacks.addBranchCreate
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            switch insertion {
            case .target:
                try await viewModel.addBranchToStack(
                    repo: repo,
                    worktree: worktree,
                    name: branchName,
                    target: target.isEmpty ? nil : target
                )
            case .below(let reference):
                try await viewModel.createStackedBranch(
                    repo: repo, worktree: worktree, referenceBranch: reference,
                    name: branchName, position: .below)
            case .above(let reference):
                try await viewModel.createStackedBranch(
                    repo: repo, worktree: worktree, referenceBranch: reference,
                    name: branchName, position: .above)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
