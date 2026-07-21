import SwiftUI
import TermQCore
import TermQShared

/// One repository's prunable worktrees, for the aggregated prune sheet: stale
/// administrative records, closed-PR checkouts, and "Run with Focus" review worktrees.
struct RepoPruneCandidate: Identifiable {
    let repo: ObservableRepository
    let staleEntries: [String]
    var closedPRCandidates: [PRPruneCandidate] = []
    var focusCandidates: [FocusWorktreeCandidate] = []
    var id: ObservableRepository.ID { repo.id }

    var isEmpty: Bool {
        staleEntries.isEmpty && closedPRCandidates.isEmpty && focusCandidates.isEmpty
    }
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

            // Each loop omits the divider after its own last row only when it's also
            // the last populated group in the section, so the bottom border doesn't
            // get a trailing divider butted up against it.
            let staleIsLastGroup = candidate.closedPRCandidates.isEmpty && candidate.focusCandidates.isEmpty
            let closedIsLastGroup = candidate.focusCandidates.isEmpty

            ForEach(candidate.staleEntries, id: \.self) { entry in
                Text(entry)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !(staleIsLastGroup && entry == candidate.staleEntries.last) {
                    Divider()
                }
            }

            ForEach(candidate.closedPRCandidates) { pr in
                closedPRRow(pr)
                if !(closedIsLastGroup && pr.id == candidate.closedPRCandidates.last?.id) {
                    Divider()
                }
            }

            ForEach(candidate.focusCandidates) { focus in
                focusRow(focus)
                if focus.id != candidate.focusCandidates.last?.id {
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

    private func closedPRRow(_ candidate: PRPruneCandidate) -> some View {
        HStack(spacing: 8) {
            Image(systemName: candidate.canPrune ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(candidate.canPrune ? .green : .orange)
                .imageScale(.small)
            Text("#\(candidate.prNumber)")
                .font(.caption)
            Spacer()
            if !candidate.canPrune {
                Text(candidate.isDirty ? Strings.RemotePRs.pruneReasonDirty : Strings.RemotePRs.pruneReasonAhead)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func focusRow(_ candidate: FocusWorktreeCandidate) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .imageScale(.small)
            Text(candidate.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func prune() async {
        isPruning = true
        defer { isPruning = false }
        errorMessage = nil
        do {
            for candidate in candidates {
                if !candidate.staleEntries.isEmpty {
                    try await viewModel.pruneWorktrees(repo: candidate.repo)
                }
                let toPrune = candidate.closedPRCandidates.filter(\.canPrune)
                if !toPrune.isEmpty {
                    await viewModel.pruneClosedPRs(repo: candidate.repo, candidates: toPrune)
                }
                if !candidate.focusCandidates.isEmpty {
                    await viewModel.pruneFocusWorktrees(
                        repo: candidate.repo, paths: candidate.focusCandidates.map(\.path))
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
