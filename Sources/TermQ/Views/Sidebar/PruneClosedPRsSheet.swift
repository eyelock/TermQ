import SwiftUI
import TermQCore
import TermQShared

/// Confirmation sheet for pruning worktrees of closed/merged PRs.
///
/// Shows a list of closed PR worktrees split into "will prune" (clean) and
/// "will keep" (dirty or has unpushed commits). Mirrors the existing
/// `PruneWorktreesSheet` pattern.
struct PruneClosedPRsSheet: View {
    let repo: ObservableRepository
    let candidates: [PRPruneCandidate]
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @ObservedObject var prService: GitHubPRService
    let onDismiss: () -> Void

    @State private var isPruning = false

    private var toPrune: [PRPruneCandidate] { candidates.filter(\.canPrune) }
    private var toKeep: [PRPruneCandidate] { candidates.filter { !$0.canPrune } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(Strings.RemotePRs.pruneClosedPRsTitle(candidates.count))
                .font(.headline)

            // Candidates list
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(candidates) { candidate in
                        candidateRow(candidate)
                    }
                }
            }
            .frame(maxHeight: 300)

            Spacer()

            Divider()

            HStack {
                Button(Strings.Common.cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(pruneButtonLabel) {
                    Task { await prune() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(toPrune.isEmpty || isPruning)
            }
        }
        .padding()
        .frame(width: 460, height: 380)
    }

    @ViewBuilder
    private func candidateRow(_ candidate: PRPruneCandidate) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: candidate.canPrune ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(candidate.canPrune ? .green : .orange)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("#\(candidate.prNumber)")
                    .font(.subheadline)

                if let path = candidate.worktreePath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if !candidate.canPrune {
                    HStack(spacing: 8) {
                        if candidate.isDirty {
                            Text(Strings.RemotePRs.pruneReasonDirty)
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        if candidate.aheadCount > 0 {
                            Text(Strings.RemotePRs.pruneReasonAhead)
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            Spacer()

            Text(
                candidate.canPrune
                    ? Strings.RemotePRs.pruneRemove
                    : Strings.RemotePRs.pruneKeep
            )
            .font(.caption)
            .foregroundColor(candidate.canPrune ? .red : .secondary)
        }
        .padding(.vertical, 2)
    }

    private var pruneButtonLabel: String {
        Strings.RemotePRs.pruneClosedPRsConfirm
    }

    private func prune() async {
        isPruning = true
        defer { isPruning = false }
        await viewModel.pruneClosedPRs(repo: repo, candidates: toPrune)
        onDismiss()
    }
}
