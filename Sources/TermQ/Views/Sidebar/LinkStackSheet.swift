import SwiftUI
import TermQCore
import TermQShared

/// Confirmation before linking branches into a stack on the forge.
///
/// Named for what it does rather than folded into "Track Branch", because it is not the
/// local-metadata operation that name implies: a branch without a pull request gets one
/// CREATED. The sheet says so per branch, and the confirm button counts the pull requests
/// that will come into existence — the part a user is most likely to be surprised by.
struct LinkStackSheet: View {
    let repo: ObservableRepository
    let worktree: GitWorktree
    /// Branches to link, bottom of the stack first — that order defines the stack.
    let branches: [StackBranch]
    /// Trunk for the bottom of the stack. `nil` uses the repository default branch.
    let base: String?
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    var onComplete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var isLinking = false
    @State private var errorMessage: String?

    /// Branches with no change request yet — each becomes a new pull request.
    private var willCreate: [StackBranch] {
        branches.filter { $0.changeRequest == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Stacks.linkStackTitle)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(branches) { branch in
                    HStack(spacing: 8) {
                        Image(
                            systemName: branch.changeRequest == nil
                                ? "plus.circle" : "link.circle"
                        )
                        .imageScale(.small)
                        .foregroundColor(branch.changeRequest == nil ? .orange : .accentColor)
                        Text(branch.name)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let request = branch.changeRequest {
                            Text("#\(request.id) \(Strings.Stacks.linkStackExisting)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(Strings.Stacks.linkStackNew)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))

            if !willCreate.isEmpty {
                Text(Strings.Stacks.linkStackWillCreate(willCreate.count))
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(Strings.Sidebar.cancelButton) { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(Strings.Stacks.linkStackConfirm(branches.count)) {
                    Task { await link() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isLinking || branches.count < 2)
            }
        }
        .padding(24)
        .frame(width: 480)
        .disabled(isLinking)
    }

    private func link() async {
        isLinking = true
        defer { isLinking = false }
        errorMessage = nil
        do {
            try await viewModel.linkStack(
                repo: repo, worktree: worktree, branches: branches.map(\.name), base: base)
            onComplete?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
