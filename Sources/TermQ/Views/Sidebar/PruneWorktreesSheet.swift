import SwiftUI
import TermQCore

/// Sheet shown before a `git worktree prune` — lists stale records and asks for confirmation.
struct PruneWorktreesSheet: View {
    let repo: ObservableRepository
    let staleEntries: [String]
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isPruning: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Sidebar.pruneWorktreesTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(Strings.Sidebar.pruneWorktreesExplanation)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(staleEntries, id: \.self) { entry in
                    Text(entry)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if entry != staleEntries.last {
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
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

                Button(Strings.Sidebar.pruneWorktreesConfirm) {
                    Task { await prune() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isPruning)
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(isPruning)
    }

    private func prune() async {
        isPruning = true
        defer { isPruning = false }
        errorMessage = nil
        do {
            try await viewModel.pruneWorktrees(repo: repo)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
