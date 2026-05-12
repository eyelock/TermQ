import SwiftUI
import TermQCore
import TermQShared

/// Confirmation sheet for pruning remote-PR worktrees.
///
/// Shows two optional sections:
/// - Closed/merged PR worktrees (may be dirty or ahead — those are kept)
/// - Focus worktrees created by "Run with Focus" on non-checked-out PRs (always prunable)
struct PruneClosedPRsSheet: View {
    let repo: ObservableRepository
    let candidates: [PRPruneCandidate]
    let focusCandidates: [FocusWorktreeCandidate]
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @ObservedObject var prService: GitHubPRService
    let onDismiss: () -> Void

    @State private var isPruning = false

    private var toPrune: [PRPruneCandidate] { candidates.filter(\.canPrune) }
    private var toKeep: [PRPruneCandidate] { candidates.filter { !$0.canPrune } }
    private var showBothSections: Bool { !candidates.isEmpty && !focusCandidates.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sheetTitle)
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !candidates.isEmpty {
                        if showBothSections {
                            Text(Strings.RemotePRs.pruneClosedHeader)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                        ForEach(candidates) { candidate in
                            closedPRRow(candidate)
                        }
                    }

                    if !focusCandidates.isEmpty {
                        if showBothSections {
                            Text(Strings.RemotePRs.pruneFocusHeader)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                        ForEach(focusCandidates) { candidate in
                            focusRow(candidate)
                        }
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

                Button(Strings.RemotePRs.pruneClosedPRsConfirm) {
                    Task { await prune() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled((toPrune.isEmpty && focusCandidates.isEmpty) || isPruning)
            }
        }
        .padding()
        .frame(width: 460, height: 380)
    }

    @ViewBuilder
    private func closedPRRow(_ candidate: PRPruneCandidate) -> some View {
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

            Text(candidate.canPrune ? Strings.RemotePRs.pruneRemove : Strings.RemotePRs.pruneKeep)
                .font(.caption)
                .foregroundColor(candidate.canPrune ? .red : .secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func focusRow(_ candidate: FocusWorktreeCandidate) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .frame(width: 16)

            Text(candidate.displayName)
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            Text(Strings.RemotePRs.pruneRemove)
                .font(.caption)
                .foregroundColor(.red)
        }
        .padding(.vertical, 2)
    }

    private var sheetTitle: String {
        if candidates.isEmpty {
            return Strings.RemotePRs.pruneFocusTitle(focusCandidates.count)
        }
        return Strings.RemotePRs.pruneClosedPRsTitle(candidates.count)
    }

    private func prune() async {
        isPruning = true
        defer { isPruning = false }
        await viewModel.pruneClosedPRs(repo: repo, candidates: toPrune)
        if !focusCandidates.isEmpty {
            await viewModel.pruneFocusWorktrees(repo: repo, paths: focusCandidates.map(\.path))
        }
        onDismiss()
    }
}
