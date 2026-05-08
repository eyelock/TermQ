import AppKit
import SwiftUI
import TermQCore
import TermQShared

// MARK: - New Worktree Context

/// Carries the target repository and an optional base-branch seed into
/// `NewWorktreeSheet`. Lets `sheet(item:)` bind to a single optional while
/// preserving the branch-row entry point where the clicked branch becomes
/// the default base for the new worktree.
struct NewWorktreeContext: Identifiable {
    let id = UUID()
    let repo: ObservableRepository
    let initialBaseBranch: String?
}

// MARK: - Convert Worktree Context

/// Carries the target repository and the branch being converted into
/// `ConvertToWorktreeSheet`. Used by the "Convert to Worktree" branch action,
/// which checks the existing branch out as a worktree (optionally renaming it
/// first), without creating a new branch.
struct ConvertWorktreeContext: Identifiable {
    let id = UUID()
    let repo: ObservableRepository
    let branch: String
}

// MARK: - Sidebar Mode

/// Whether the Repositories panel is showing local worktrees or remote PRs.
enum SidebarMode {
    case local
    case remote
}

// MARK: - Checkout PR Context

struct CheckoutPRContext: Identifiable {
    let id = UUID()
    let pr: GitHubPR
    let repo: ObservableRepository
    let ghPath: String
}

// MARK: - Force Update PR Context

struct ForceUpdatePRContext: Identifiable {
    let id = UUID()
    let worktree: GitWorktree
    let repo: ObservableRepository
    let prNumber: Int
    let ghPath: String
}

// MARK: - Review With Focus Context

struct ReviewWithFocusContext: Identifiable {
    let id = UUID()
    let worktree: GitWorktree
    let repo: ObservableRepository
    let prNumber: Int
}

// MARK: - Sidebar Toast

struct SidebarToast: Identifiable {
    let id = UUID()
    let message: String
    let actionLabel: String?
    let action: (() -> Void)?
}

// MARK: - Repo Disclosure Wrapper

/// Owns the `@State` for a repo's expanded/collapsed state so the `DisclosureGroup`
/// never mutates the `@ObservableObject` ViewModel synchronously during a SwiftUI render
/// pass. Doing so caused reentrant NSTableView delegate calls and visible flicker.
///
/// - `isExpanded` drives the visual state directly.
/// - `.onChange(of: isExpanded)` persists to the ViewModel *after* the render completes.
/// - `.onChange(of: viewModel.expandedRepoIDs)` syncs back when the ViewModel changes
///   externally (reload, programmatic expand).
struct RepoDisclosureView<Content: View, Label: View>: View {
    let repo: ObservableRepository
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Label
    @State private var isExpanded: Bool

    init(
        repo: ObservableRepository,
        viewModel: WorktreeSidebarViewModel,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.repo = repo
        self.viewModel = viewModel
        self.content = content
        self.label = label
        self._isExpanded = State(initialValue: viewModel.expandedRepoIDs.contains(repo.id))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
        } label: {
            label()
        }
        .onChange(of: isExpanded) { _, newValue in
            viewModel.setExpanded(repo.id, expanded: newValue)
            if newValue && viewModel.worktrees[repo.id] == nil {
                Task { await viewModel.refreshWorktrees(for: repo) }
            }
        }
        .onChange(of: viewModel.expandedRepoIDs) { _, ids in
            let should = ids.contains(repo.id)
            if isExpanded != should { isExpanded = should }
        }
    }
}

// MARK: - Branch Section Disclosure Wrapper

/// Owns the `@State` for a repo's "Local Branches" section expanded/collapsed state,
/// using the same deferred-mutation pattern as `RepoDisclosureView` to avoid
/// reentrant NSTableView calls during SwiftUI render.
struct BranchSectionDisclosureView<Content: View>: View {
    let repo: ObservableRepository
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @ViewBuilder let content: () -> Content
    var onPruneBranches: (() -> Void)?
    @State private var isExpanded: Bool

    init(
        repo: ObservableRepository,
        viewModel: WorktreeSidebarViewModel,
        onPruneBranches: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.repo = repo
        self.viewModel = viewModel
        self.onPruneBranches = onPruneBranches
        self.content = content
        self._isExpanded = State(initialValue: viewModel.expandedBranchSectionIDs.contains(repo.id))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
        } label: {
            Text(Strings.Sidebar.localBranches)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .contextMenu {
                    Button {
                        onPruneBranches?()
                    } label: {
                        Label(Strings.Sidebar.pruneBranches, systemImage: "scissors")
                    }
                }
        }
        .onChange(of: isExpanded) { _, newValue in
            viewModel.setBranchSectionExpanded(repo.id, expanded: newValue)
        }
        .onChange(of: viewModel.expandedBranchSectionIDs) { _, ids in
            let should = ids.contains(repo.id)
            if isExpanded != should { isExpanded = should }
        }
    }
}

// MARK: - Left Icon

/// Two-slot icon for a worktree row.
///
/// Left slot (12 pt, optional):
/// - Main worktree → `house.fill` (secondary)
/// - Locked worktree → `lock.fill` (orange)
/// - Regular worktree → empty
///
/// Right slot (14 pt, always present):
/// - No open terminals → `circle` (secondary)
/// - N open terminals → `N.circle.fill` (accent, tappable → popover listing terminals)
struct WorktreeLeftIcon: View {
    let worktree: GitWorktree
    let allWorktrees: [GitWorktree]
    @ObservedObject var boardVM: BoardViewModel
    let isDeleting: Bool
    let isUpdating: Bool
    @State private var showPopover = false

    private var matchingCards: [TerminalCard] {
        (boardVM.board.cards + Array(boardVM.tabManager.transientCards.values))
            .filter { card in
                guard !card.isDeleted else { return false }
                let wd = card.workingDirectory
                let matchesThis = wd == worktree.path || wd.hasPrefix(worktree.path + "/")
                guard matchesThis else { return false }
                // Don't count this card if a more-specific sibling worktree owns it
                // (handles the common case where worktrees live inside the main repo dir)
                return !allWorktrees.contains { other in
                    other.id != worktree.id
                        && other.path.count > worktree.path.count
                        && (wd == other.path || wd.hasPrefix(other.path + "/"))
                }
            }
    }

    var body: some View {
        HStack(spacing: 2) {
            // Left slot — spinner during deletion/update, otherwise status badge
            Group {
                if isDeleting || isUpdating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                } else if worktree.isMainWorktree {
                    Image(systemName: "house.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.small)
                } else if worktree.isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.orange)
                        .imageScale(.small)
                } else {
                    Color.clear
                }
            }
            .frame(width: 12)

            // Right slot — terminal count (always shown)
            let cards = matchingCards
            if cards.isEmpty {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                    .imageScale(.small)
                    .frame(width: 14)
            } else {
                let iconName = cards.count <= 50 ? "\(cards.count).circle.fill" : "circle.fill"
                Button {
                    showPopover = true
                } label: {
                    Image(systemName: iconName)
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .help(Strings.Sidebar.terminalBadgeHelp)
                .popover(isPresented: $showPopover, arrowEdge: .leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(cards) { card in
                            Button {
                                boardVM.selectCard(card)
                                showPopover = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "terminal")
                                        .imageScale(.small)
                                        .foregroundColor(.secondary)
                                        .frame(width: 16)
                                    Text(card.title)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if card.id != cards.last?.id {
                                Divider()
                            }
                        }
                    }
                    .frame(minWidth: 200)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
