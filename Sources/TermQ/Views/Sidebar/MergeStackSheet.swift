import SwiftUI
import TermQCore
import TermQShared

/// Confirmation before merging every pull request in a stack.
///
/// This is the only action in the stack UI that lands code on a real branch, so it shows
/// the state each pull request is actually in — review decision and CI — fetched when the
/// sheet opens rather than reused from the PR feed. Stale readiness inside a merge
/// confirmation is the one place staleness is genuinely dangerous.
///
/// ## Why a blocked stack sends you to GitHub
///
/// gh-stack refuses a whole-stack merge when a draft or closed pull request sits partway
/// up, and suggests merging up to an explicit pull request instead. TermQ does not offer
/// that button, because `gh stack merge <n>` resolves a bare number as a STACK number
/// first and only then as a pull request number — and the two are independent sequences in
/// the same repository. Passing a pull request number that happens to collide with a stack
/// number would merge a different stack entirely, with `--yes`, containing pull requests
/// the user never saw here.
///
/// So the sheet does the valuable half — telling you before you commit to anything that
/// the merge cannot succeed, and why — and hands the partial merge to GitHub, where the
/// same operation is unambiguous.
struct MergeStackSheet: View {
    let repo: ObservableRepository
    let worktree: GitWorktree
    let group: StackGroup
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    let readinessService: StackMergeReadinessService
    /// Called after a successful merge with the number of pull requests merged.
    var onComplete: ((Int) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var readiness: StackMergeReadiness?
    @State private var isLoading = true
    @State private var isMerging = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Stacks.mergeStackTitle)
                .font(.title2)
                .fontWeight(.semibold)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(Strings.Stacks.mergeStackLoading)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let readiness {
                readinessList(readiness)
                summary(readiness)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
        .padding(24)
        .frame(width: 520)
        .disabled(isMerging)
        .task { await load() }
    }

    // MARK: - Rows

    @ViewBuilder
    private func readinessList(_ readiness: StackMergeReadiness) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(readiness.prs) { pr in
                HStack(spacing: 8) {
                    let icon = rowIcon(pr, in: readiness)
                    Image(systemName: icon.symbol)
                        .imageScale(.small)
                        .foregroundColor(icon.color)
                    Text("#\(String(pr.number))")
                        .font(.system(.body, design: .monospaced))
                    Text(pr.branch)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let reason = pr.blockReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        reviewBadge(pr.review)
                        checksBadge(pr.checks)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    /// Three states, not two. A pull request sitting ABOVE the blocker is ready in
    /// itself but still cannot merge, because nothing above a draft or closed pull
    /// request goes anywhere. Showing it with the same green tick as a genuinely
    /// mergeable one promises exactly what the sheet is about to refuse, so it gets
    /// a neutral mark instead; the summary line names the blocker and explains why.
    private func rowIcon(
        _ pr: StackPRReadiness, in readiness: StackMergeReadiness
    ) -> (symbol: String, color: Color) {
        if pr.blocksStackMerge { return ("exclamationmark.octagon.fill", .orange) }
        if readiness.mergeable.contains(where: { $0.number == pr.number }) {
            return ("checkmark.circle", .green)
        }
        return ("circle.dashed", .secondary)
    }

    /// Review and check state are advisory, not gates: branch protection varies per
    /// repository and TermQ cannot read it, so these inform the decision rather than
    /// prevent it. GitHub still refuses a merge that breaks its own rules.
    @ViewBuilder
    private func reviewBadge(_ review: StackReviewState) -> some View {
        switch review {
        case .approved:
            badge(Strings.Stacks.reviewApproved, systemImage: "checkmark.seal", color: .green)
        case .changesRequested:
            badge(Strings.Stacks.reviewChangesRequested, systemImage: "xmark.seal", color: .orange)
        case .reviewRequired:
            badge(Strings.Stacks.reviewRequired, systemImage: "seal", color: .secondary)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func checksBadge(_ checks: StackCheckState) -> some View {
        switch checks {
        case .passing:
            badge(Strings.Stacks.checksPassing, systemImage: "checkmark.circle", color: .green)
        case .failing:
            badge(Strings.Stacks.checksFailing, systemImage: "xmark.circle", color: .orange)
        case .pending:
            badge(Strings.Stacks.checksPending, systemImage: "clock", color: .secondary)
        case .none:
            EmptyView()
        }
    }

    private func badge(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).imageScale(.small)
            Text(text)
        }
        .font(.caption)
        .foregroundColor(color)
    }

    // MARK: - Summary

    @ViewBuilder
    private func summary(_ readiness: StackMergeReadiness) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let blocker = readiness.blocker {
                Text(Strings.Stacks.mergeBlockedBy("#\(String(blocker.number))"))
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Strings.Stacks.mergeStackMessage(readiness.prs.count))
                    .font(.caption)
                if let method = readiness.defaultMergeMethod {
                    Text(Strings.Stacks.mergeStackMethod(method.rawValue))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(Strings.Stacks.mergeStackIrreversible)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        HStack {
            Spacer()
            Button(Strings.Sidebar.cancelButton) { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])

            if let readiness, readiness.canMergeWholeStack {
                Button(Strings.Stacks.mergeStackConfirm(readiness.prs.count)) {
                    Task { await merge(readiness) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isMerging || isLoading)
            } else if readiness?.blocker != nil {
                // The partial merge lives on GitHub — see the type doc for why.
                Button(Strings.Stacks.mergeOpenOnGitHub) {
                    openStackOnGitHub()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Behaviour

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let numbers = group.branches.compactMap { Int($0.changeRequest?.id ?? "") }
        guard !numbers.isEmpty else {
            errorMessage = Strings.Stacks.mergeStackMessage(0)
            return
        }
        do {
            readiness = try await readinessService.readiness(
                repoPath: repo.path, prNumbers: numbers)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func merge(_ readiness: StackMergeReadiness) async {
        isMerging = true
        defer { isMerging = false }
        errorMessage = nil
        do {
            try await viewModel.mergeStack(repo: repo, worktree: worktree, group: group)
            onComplete?(readiness.prs.count)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Opens the bottom pull request, which is where GitHub renders the stack and offers
    /// the partial merge.
    private func openStackOnGitHub() {
        guard let url = group.branches.compactMap({ $0.changeRequest?.url }).first,
            let parsed = URL(string: url)
        else { return }
        NSWorkspace.shared.open(parsed)
    }
}
