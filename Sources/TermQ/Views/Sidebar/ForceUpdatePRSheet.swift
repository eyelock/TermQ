import SwiftUI
import TermQShared

/// Confirmation sheet before force-updating a PR-linked worktree.
///
/// Shown when `Update from Origin` is invoked on a worktree whose PR head
/// was force-pushed upstream, or whose tree is dirty / has ahead commits.
struct ForceUpdatePRSheet: View {
    let context: ForceUpdatePRContext
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var aheadCount: Int = 0
    @State private var isLoading = true
    @State private var isUpdating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text(Strings.RemotePRs.forceUpdateTitle)
                .font(.headline)

            // Body
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(
                    Strings.RemotePRs.forceUpdateMessage(
                        context.worktree.isDirty ? 1 : 0,
                        aheadCount
                    )
                )
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.secondary)
            }

            Spacer()

            Divider()

            // Buttons
            HStack {
                Button(Strings.RemotePRs.forceUpdateCancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(Strings.RemotePRs.forceUpdateConfirm) {
                    Task { await update() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isUpdating)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
        .task {
            aheadCount = await GitService.shared.aheadCount(worktreePath: context.worktree.path)
            isLoading = false
        }
    }

    private func update() async {
        isUpdating = true
        defer { isUpdating = false }
        do {
            try await viewModel.updateFromOriginForPR(
                worktree: context.worktree,
                repo: context.repo,
                prNumber: context.prNumber,
                ghPath: context.ghPath
            )
            dismiss()
        } catch {
            viewModel.operationError = error.localizedDescription
            dismiss()
        }
    }
}
