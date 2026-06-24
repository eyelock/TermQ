import SwiftUI
import TermQCore

/// One repository's stale worktree records, for the aggregated prune sheet.
struct RepoPruneCandidate: Identifiable {
    let repo: ObservableRepository
    let staleEntries: [String]
    var id: ObservableRepository.ID { repo.id }
}

/// Identifiable wrapper so `sheet(item:)` can present the aggregated prune sheet.
struct PruneAllContext: Identifiable {
    let id = UUID()
    let candidates: [RepoPruneCandidate]
}

/// Sheet shown before pruning stale worktree records across every repository.
/// Lists each repository's stale records and asks for a single confirmation —
/// the all-repos counterpart to `PruneWorktreesSheet`.
struct PruneAllWorktreesSheet: View {
    let candidates: [RepoPruneCandidate]
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isPruning = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Sidebar.pruneWorktreesTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(Strings.Sidebar.pruneWorktreesExplanation)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(candidates) { candidate in
                        repoSection(candidate)
                    }
                }
            }
            .frame(maxHeight: 280)

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
        .frame(width: 480)
        .disabled(isPruning)
    }

    private func repoSection(_ candidate: RepoPruneCandidate) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(candidate.repo.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            Divider()

            ForEach(candidate.staleEntries, id: \.self) { entry in
                Text(entry)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if entry != candidate.staleEntries.last {
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
    }

    private func prune() async {
        isPruning = true
        defer { isPruning = false }
        errorMessage = nil
        do {
            for candidate in candidates {
                try await viewModel.pruneWorktrees(repo: candidate.repo)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
