import SwiftUI
import TermQCore
import TermQShared

/// Confirmation sheet before submitting a stack (or a single branch) as change requests.
///
/// Lists what the submit will do per branch — create a new CR or update the existing
/// one — with a Draft toggle for new CRs and an update-only mode that skips creating
/// new ones. The provider's submit is idempotent, so re-running is safe.
struct SubmitStackSheet: View {
    let repo: ObservableRepository
    let worktree: GitWorktree
    /// Branches the submit covers, bottom of stack first. A single-element array for
    /// per-branch submit.
    let branches: [StackBranch]
    let scope: StackScope
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    /// Called after a successful submit with (created, updated) counts, derived from
    /// the pre-submit change-request state of the listed branches. Drives the
    /// completion toast in the presenting view.
    var onComplete: ((Int, Int) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var asDraft = false
    @State private var updateOnly = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Stacks.submitTitle)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(branches) { branch in
                    HStack(spacing: 8) {
                        Image(systemName: branch.changeRequest == nil ? "plus.circle" : "arrow.up.circle")
                            .imageScale(.small)
                            .foregroundColor(branch.changeRequest == nil ? .green : .accentColor)
                        Text(branch.name)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Text(
                            branch.changeRequest == nil
                                ? Strings.Stacks.submitWillCreate
                                : Strings.Stacks.submitWillUpdate
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))

            Toggle(Strings.Stacks.submitDraftToggle, isOn: $asDraft)
            Toggle(Strings.Stacks.submitUpdateOnlyToggle, isOn: $updateOnly)

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

                Button(Strings.Stacks.submitButton) {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting)
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(isSubmitting)
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        do {
            try await viewModel.submitStack(
                repo: repo,
                worktree: worktree,
                scope: scope,
                options: StackSubmitOptions(draft: asDraft, updateOnly: updateOnly)
            )
            let creatable = branches.filter { $0.changeRequest == nil }.count
            let created = updateOnly ? 0 : creatable
            let updated = branches.count - creatable
            onComplete?(created, updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
