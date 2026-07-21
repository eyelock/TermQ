import AppKit
import SwiftUI
import TermQShared

// MARK: - Layout Metrics

/// Shared horizontal grid for the sidebar's stack-aware rows.
///
/// Every worktree row in a repo that has at least one stacked worktree reserves the
/// chevron slot, so status circles, icons, and branch names align in one column
/// regardless of whether an individual row is stacked. Repos with no stacks render
/// without the slot — pixel-identical to the pre-stacks layout.
enum StackRowMetrics {
    /// Width of the leading chevron slot on worktree rows.
    static let chevronSlotWidth: CGFloat = 12
    /// Spacing between the chevron slot and the row content.
    static let chevronSpacing: CGFloat = 4
    /// x-offset of the row content column (after the chevron slot).
    static let contentColumn: CGFloat = chevronSlotWidth + chevronSpacing
    /// `WorktreeLeftIcon` block (12 + 2 + 14) plus the row's icon-to-label spacing (6).
    static let iconBlockWidth: CGFloat = 34
    /// x-offset of the worktree row's branch-name label.
    static let labelColumn: CGFloat = contentColumn + iconBlockWidth
    /// The single indent step nested content takes from its parent column.
    static let indentStep: CGFloat = 12
    /// x-offset of chain entries under a worktree row: one step right of the label.
    static let chainEntryIndent: CGFloat = labelColumn + indentStep
}

/// Plain rotated-chevron disclosure button, vertically centered with row content —
/// `DisclosureGroup`'s own chevron top-aligns against multi-line labels. No animation:
/// animated expansion inside List rows is a known source of stale row geometry.
struct StackChevronButton: View {
    @Binding var isExpanded: Bool
    var help: String = Strings.Stacks.disclosureHelp

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: StackRowMetrics.chevronSlotWidth)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Stack Disclosure Wrapper

/// A worktree row in the sidebar grid plus its stack chain.
///
/// Emits the header and each chain entry as SIBLING List rows (implicit ViewBuilder
/// body, no wrapping VStack): the List must see every row individually so selection
/// rings and context menus target exactly the row under the cursor. Collapsed entries
/// are simply not emitted — never hidden in place (phantom-space reservation) and
/// never nested inside the header's own view (whole-section hit-testing).
///
/// Expansion state is local `@State`, not persisted — the disclosure is a lightweight
/// "peek at the stack" affordance, not a navigation structure worth remembering across
/// launches yet.
struct StackDisclosureRow<Label: View, HeaderMenu: View>: View {
    /// The stack chain for this row; empty for unstacked worktrees.
    let chain: [StackBranch]
    /// Whether to reserve the leading chevron slot even without a chain — true when
    /// any sibling row in the repo is stacked, so all rows share one column.
    let showChevronSlot: Bool
    /// The branch checked out in THIS worktree — drives the ● current marker. The
    /// graph's `current` field reflects wherever `gs log` happened to run (the main
    /// checkout) and must not be used here.
    let currentBranch: String?
    /// Scroll-target identity for the header row (Stacks-section jump).
    let rowID: String
    /// Brief post-reveal highlight so the user sees where a jump landed.
    let isHighlighted: Bool
    /// Requested switch to a non-current entry (double-click or context menu). The
    /// guard logic (dirty worktree, attached session) lives in the view model, not here.
    let onSwitch: (StackBranch) -> Void
    /// Called for "Restack from Here" on an entry.
    let onRestackFromHere: (StackBranch) -> Void
    /// Called for "Submit This Branch…" on an entry.
    let onSubmitBranch: (StackBranch) -> Void
    /// Warning text when the entry's CR base doesn't match its stack parent; `nil` when
    /// consistent or unknown. Computed by the caller from PR data — this view stays dumb.
    let baseMismatch: (StackBranch) -> String?
    /// Path of the OTHER worktree the entry is checked out in, if any — drives the
    /// checked-out-elsewhere indicator on chain entries.
    let checkedOutElsewherePath: (StackBranch) -> String?
    /// Reveal the worktree that owns the entry (paired with `checkedOutElsewherePath`).
    let onJumpToWorktree: (StackBranch) -> Void
    /// "Break Out into Worktree…" for entries not checked out anywhere.
    let onBreakOut: (StackBranch) -> Void
    /// Bundled launch/insertion/remote actions for an entry (Round-3 launch menus).
    let entryActions: (StackBranch) -> StackEntryActions
    @ViewBuilder let label: () -> Label
    /// The worktree context menu — attached to the header row ONLY; chain entries
    /// carry their own menus.
    @ViewBuilder let headerContextMenu: () -> HeaderMenu
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .center, spacing: StackRowMetrics.chevronSpacing) {
            if !chain.isEmpty {
                StackChevronButton(isExpanded: $isExpanded)
            } else if showChevronSlot {
                Color.clear
                    .frame(width: StackRowMetrics.chevronSlotWidth, height: 1)
            }
            label()
        }
        .padding(.vertical, isHighlighted ? 2 : 0)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contextMenu { headerContextMenu() }
        .id(rowID)

        if isExpanded && !chain.isEmpty {
            ForEach(chain) { branch in
                let elsewhere = checkedOutElsewherePath(branch)
                StackBranchEntryRow(
                    branch: branch,
                    isCurrent: branch.name == currentBranch,
                    baseMismatch: baseMismatch(branch),
                    checkedOutElsewherePath: elsewhere,
                    onSwitch: { onSwitch(branch) },
                    onRestackFromHere: { onRestackFromHere(branch) },
                    onSubmitBranch: { onSubmitBranch(branch) },
                    onJumpToWorktree: elsewhere == nil ? nil : { onJumpToWorktree(branch) },
                    onBreakOut: elsewhere == nil && branch.name != currentBranch
                        ? { onBreakOut(branch) } : nil,
                    actions: entryActions(branch)
                )
                .padding(.leading, StackRowMetrics.chainEntryIndent)
            }
        }
    }
}

// MARK: - Stack Branch Entry Row

/// One line in an expanded stack: current-branch dot, name, and badges for change-request
/// status, restack need, and unpushed commits.
///
/// Two modes, chosen by which initializer is used:
/// - **Working surface** (worktree expansion): double-clicking a non-current entry (or
///   its context-menu "Switch to …" item) requests a guarded switch; the context menu
///   also offers restack/submit. Single-click never mutates.
/// - **Inventory** (Stacks section): no mutation actions — a worktree indicator jumps
///   to the anchoring worktree row instead, so actions live in exactly one place.
struct StackBranchEntryRow: View {
    let branch: StackBranch
    /// Whether this entry is the branch checked out in the containing worktree.
    /// Callers derive this from the worktree, NOT from the graph's `current` field —
    /// that reflects wherever `gs log` ran, not this worktree.
    let isCurrent: Bool
    /// Warning text when this branch's CR base doesn't match its stack parent.
    let baseMismatch: String?
    let onSwitch: (() -> Void)?
    let onRestackFromHere: (() -> Void)?
    let onSubmitBranch: (() -> Void)?
    /// Path of the worktree this branch is checked out in. In the working surface this
    /// is set only when it's a DIFFERENT worktree (the checked-out-elsewhere indicator);
    /// in the inventory it's any owning worktree.
    let worktreePath: String?
    let onJumpToWorktree: (() -> Void)?
    /// "Break Out into Worktree…" — offered when the branch has no worktree of its own.
    let onBreakOut: (() -> Void)?
    /// Bundled launch/insertion/remote actions (Round-3 launch menus) — shared by both
    /// modes, built uniformly by `WorktreeSidebarView+Stacks`'s `stackEntryActions`.
    let actions: StackEntryActions

    /// Working-surface mode (worktree expansion).
    init(
        branch: StackBranch,
        isCurrent: Bool,
        baseMismatch: String?,
        checkedOutElsewherePath: String?,
        onSwitch: @escaping () -> Void,
        onRestackFromHere: @escaping () -> Void,
        onSubmitBranch: @escaping () -> Void,
        onJumpToWorktree: (() -> Void)?,
        onBreakOut: (() -> Void)?,
        actions: StackEntryActions = StackEntryActions()
    ) {
        self.branch = branch
        self.isCurrent = isCurrent
        self.baseMismatch = baseMismatch
        self.onSwitch = onSwitch
        self.onRestackFromHere = onRestackFromHere
        self.onSubmitBranch = onSubmitBranch
        self.worktreePath = checkedOutElsewherePath
        self.onJumpToWorktree = onJumpToWorktree
        self.onBreakOut = onBreakOut
        self.actions = actions
    }

    /// Inventory mode (Stacks section) — read-only entry with a jump-to-worktree
    /// indicator when the branch is checked out somewhere. No current marker: the
    /// inventory lists stacks repo-wide, where "current" has no single meaning.
    init(
        branch: StackBranch,
        baseMismatch: String?,
        worktreePath: String?,
        onJumpToWorktree: (() -> Void)?,
        onBreakOut: (() -> Void)? = nil,
        onRestackFromHere: (() -> Void)? = nil,
        onSubmitBranch: (() -> Void)? = nil,
        actions: StackEntryActions = StackEntryActions()
    ) {
        self.branch = branch
        self.isCurrent = false
        self.baseMismatch = baseMismatch
        self.onSwitch = nil
        self.onRestackFromHere = onRestackFromHere
        self.onSubmitBranch = onSubmitBranch
        self.worktreePath = worktreePath
        self.onJumpToWorktree = onJumpToWorktree
        self.onBreakOut = onBreakOut
        self.actions = actions
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isCurrent ? Color.accentColor : Color.clear)
                .strokeBorder(Color.secondary, lineWidth: isCurrent ? 0 : 1)
                .frame(width: 6, height: 6)

            if let onSwitch, !isCurrent {
                // Single-click is inert (inspection only); double-click switches.
                // The context menu offers the same switch for discoverability.
                Text(branch.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                    .contentShape(Rectangle())
                    .gesture(TapGesture(count: 2).onEnded { onSwitch() })
                    .help(Strings.Stacks.switchHelp)
            } else {
                Text(branch.name)
                    .font(.caption)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }

            Spacer()

            if let worktreePath {
                Button {
                    onJumpToWorktree?()
                } label: {
                    Image(systemName: "arrow.turn.down.left")
                        .imageScale(.small)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help(Strings.Stacks.checkedOutAt(worktreePath))
            }

            if branch.needsRestack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .imageScale(.small)
                    .foregroundColor(.orange)
                    .help(Strings.Stacks.needsRestack)
            }

            if let baseMismatch {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .imageScale(.small)
                    .foregroundColor(.yellow)
                    .help(baseMismatch)
            }

            if let push = branch.push, push.ahead > 0 {
                Text(Strings.Stacks.unpushedCommits(push.ahead))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            changeRequestBadge
        }
        .font(.caption)
        .contextMenu {
            // Launch <Harness> / Run with Focus…
            if let launchHarness = actions.launchHarness {
                Button {
                    launchHarness.action()
                } label: {
                    Label(Strings.Sidebar.launchHarness(launchHarness.name), systemImage: "play.fill")
                }
            }
            if let onRunWithFocus = actions.runWithFocus {
                Button {
                    onRunWithFocus()
                } label: {
                    Label(Strings.RemotePRs.runWithFocus, systemImage: "eye")
                }
            }
            if !actions.quickLaunchFocuses.isEmpty {
                Menu(Strings.RemotePRs.quickLaunchFocus) {
                    ForEach(actions.quickLaunchFocuses, id: \.name) { focus in
                        Button(Strings.RemotePRs.runFocusItem(focus.name)) {
                            focus.action()
                        }
                    }
                }
            }

            // Quick Terminal / Create Terminal…
            if actions.quickTerminal != nil || actions.createTerminal != nil {
                Divider()
            }
            if let onQuickTerminal = actions.quickTerminal {
                Button {
                    onQuickTerminal()
                } label: {
                    Label(Strings.Sidebar.newTerminal, systemImage: "terminal")
                }
            }
            if let onCreateTerminal = actions.createTerminal {
                Button {
                    onCreateTerminal()
                } label: {
                    Label(Strings.Sidebar.createTerminal, systemImage: "plus.rectangle")
                }
            }

            // Switch to <branch>
            if let onSwitch, !isCurrent {
                Divider()
                Button {
                    onSwitch()
                } label: {
                    Label(Strings.Stacks.switchTo(branch.name), systemImage: "arrow.right.circle")
                }
            }

            // New Stacked Branch Before…/After…
            if actions.newBranchBefore != nil || actions.newBranchAfter != nil {
                Divider()
            }
            if let onBefore = actions.newBranchBefore {
                Button {
                    onBefore()
                } label: {
                    Label(Strings.Stacks.newBranchBefore, systemImage: "square.stack.3d.up.badge.a")
                }
            }
            if let onAfter = actions.newBranchAfter {
                Button {
                    onAfter()
                } label: {
                    Label(Strings.Stacks.newBranchAfter, systemImage: "square.stack.3d.up.badge.a")
                }
            }

            // Open Change Request / Open Branch on Remote
            if branch.changeRequest?.url != nil || actions.openRemoteBranch != nil {
                Divider()
            }
            if let urlString = branch.changeRequest?.url, let url = URL(string: urlString) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(Strings.Stacks.openChangeRequest, systemImage: "arrow.up.right.square")
                }
            }
            if let onOpenRemoteBranch = actions.openRemoteBranch {
                Button {
                    onOpenRemoteBranch()
                } label: {
                    Label(Strings.Sidebar.openRemoteBranch, systemImage: "network")
                }
            }

            // Restack from Here / Submit This Branch…
            if onRestackFromHere != nil || onSubmitBranch != nil {
                Divider()
            }
            if let onRestackFromHere {
                Button {
                    onRestackFromHere()
                } label: {
                    Label(Strings.Stacks.restackFromHere, systemImage: "arrow.triangle.2.circlepath")
                }
            }
            if let onSubmitBranch {
                Button {
                    onSubmitBranch()
                } label: {
                    Label(Strings.Stacks.submitBranch, systemImage: "paperplane")
                }
            }

            // Break Out into Worktree… / Reveal Worktree
            if onBreakOut != nil || onJumpToWorktree != nil {
                Divider()
            }
            if let onBreakOut {
                Button {
                    onBreakOut()
                } label: {
                    Label(Strings.Stacks.breakOut, systemImage: "rectangle.split.2x1")
                }
            }
            if let onJumpToWorktree {
                Button {
                    onJumpToWorktree()
                } label: {
                    Label(Strings.Stacks.revealWorktree, systemImage: "arrow.turn.down.left")
                }
            }

            // Copy Branch Name
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(branch.name, forType: .string)
            } label: {
                Label(Strings.Stacks.copyBranchName, systemImage: "doc.on.clipboard")
            }
        }
    }

    @ViewBuilder
    private var changeRequestBadge: some View {
        if let cr = branch.changeRequest {
            Button {
                if let urlString = cr.url, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("#\(cr.id)")
                    .font(.caption2)
                    .foregroundColor(changeRequestColor(cr.status))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(changeRequestColor(cr.status).opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .disabled(cr.url == nil)
            .help(Strings.Stacks.openChangeRequest)
        } else {
            Text(Strings.Stacks.noChangeRequest)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func changeRequestColor(_ status: StackChangeRequest.Status) -> Color {
        switch status {
        case .open: return .accentColor
        case .merged: return .purple
        case .closed: return .secondary
        case .unknown: return .secondary
        }
    }
}

// MARK: - Conflict Banner

/// Banner shown under a worktree row while a stack operation is paused on conflicts.
/// The worktree's own terminal is the natural place to resolve them — Continue resumes
/// the paused operation, Abort cancels it.
struct StackConflictBanner: View {
    let conflict: StackConflictState
    let isWorking: Bool
    let onContinue: () -> Void
    let onAbort: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                    .foregroundColor(.orange)
                Text(Strings.Stacks.conflictBanner(conflict.operation.conflictedFiles.count))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            Text(Strings.Stacks.conflictHint)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(Strings.Stacks.conflictContinue, action: onContinue)
                    .controlSize(.small)
                Button(Strings.Stacks.conflictAbort, role: .destructive, action: onAbort)
                    .controlSize(.small)
                if isWorking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.1))
        )
        .disabled(isWorking)
    }
}

// MARK: - Stacks Inventory Section

/// The per-repo "Stacks" section: an inventory of every tracked stack in the repo's
/// graph, anchored to a worktree or not. The worktree-row expansion remains the working
/// surface — entries here are read-only, with a jump indicator to the anchoring
/// worktree and a "New Worktree…" affordance for unanchored stacks. All grouping and
/// dedup decisions live in `WorktreeSidebarViewModel`; this view only renders.
///
/// Header and groups are emitted as SIBLING List rows (no wrapping container):
/// per-row selection and context menus require the List to see each row; collapsed
/// content is simply not emitted, so no phantom space either.
struct StacksSectionView<HarnessBadge: View, TerminalBadge: View, GroupMenu: View>: View {
    let groups: [StackGroup]
    /// The worktree a branch is checked out in, if any (view model lookup).
    let worktreeForBranch: (String) -> GitWorktree?
    let baseMismatch: (StackBranch) -> String?
    /// Reveal the given worktree's row in the sidebar list.
    let onJumpToWorktree: (GitWorktree) -> Void
    /// Anchor an unanchored stack: create a worktree for its bottom branch.
    let onNewWorktree: (StackGroup) -> Void
    /// "New Stack…" footer: opens the sheet that seeds a worktree-less stack.
    let onNewStack: () -> Void
    /// Bundled launch/insertion/remote actions for an entry within `group`.
    let entryActions: (StackGroup, StackBranch) -> StackEntryActions
    /// "Break Out into Worktree…" for an entry not checked out anywhere.
    let onBreakOutBranch: (StackBranch) -> Void
    /// "Restack from Here" on an entry.
    let onRestackFromHereBranch: (StackBranch) -> Void
    /// "Submit This Branch…" on an entry.
    let onSubmitBranch: (StackBranch) -> Void
    /// Row-icon parity (Revision 11b): the group header's trailing harness badge.
    @ViewBuilder let harnessBadge: (StackGroup) -> HarnessBadge
    /// Row-icon parity (Revision 11f): the group header's open-terminal-count badge,
    /// same visual language as `WorktreeLeftIcon`'s right slot.
    @ViewBuilder let terminalBadge: (StackGroup) -> TerminalBadge
    /// Row-icon parity (Revision 11b): quick-terminal launch at the group's tip.
    let onQuickTerminal: (StackGroup) -> Void
    /// Group primary click (Revision 11d): launch at the group's tip.
    let onPrimaryAction: (StackGroup) -> Void
    /// The group-header context menu, built by the presenting view so every item
    /// routes through the shared worktree/stack action handlers.
    @ViewBuilder let groupContextMenu: (StackGroup) -> GroupMenu
    @State private var isExpanded = true

    var body: some View {
        HStack(spacing: StackRowMetrics.chevronSpacing) {
            StackChevronButton(isExpanded: $isExpanded)
            Text(Strings.Stacks.sectionHeader)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }

        if isExpanded {
            ForEach(groups) { group in
                StackGroupRow(
                    group: group,
                    worktreeForBranch: worktreeForBranch,
                    baseMismatch: baseMismatch,
                    onJumpToWorktree: onJumpToWorktree,
                    onNewWorktree: { onNewWorktree(group) },
                    entryActions: { branch in entryActions(group, branch) },
                    onBreakOutBranch: onBreakOutBranch,
                    onRestackFromHereBranch: onRestackFromHereBranch,
                    onSubmitBranch: onSubmitBranch,
                    harnessBadge: { harnessBadge(group) },
                    terminalBadge: { terminalBadge(group) },
                    onQuickTerminal: { onQuickTerminal(group) },
                    onPrimaryAction: { onPrimaryAction(group) },
                    headerContextMenu: { groupContextMenu(group) }
                )
                // NOT indented by `contentColumn` — `StackGroupRow` already reserves
                // its own leading chevron column internally (same shape as a worktree
                // row's `StackDisclosureRow`). Adding this padding on top double-indented
                // stack rows relative to worktree rows, throwing off alignment with the
                // "+ New Worktree"/"+ New Stack…" footers and the section header itself.
            }

            Button {
                onNewStack()
            } label: {
                // Manual icon + text, NOT `Label` — sidebar-styled Lists auto-align
                // `Label` icons into a shared column that ignores surrounding padding,
                // which silently defeats leading-padding alignment here.
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .imageScale(.small)
                    Text(Strings.Stacks.newStack)
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            // Flush with the row start (0), matching "+ New Worktree" and the STACKS
            // group rows' own chevron column — NOT `contentColumn`, which is a stale
            // offset from when group rows were still double-indented.
            .padding(.top, 2)
        }
    }
}

/// One stack in the inventory: a collapsible group titled by its bottom branch,
/// rendering the chain upward with the standard entry badges. Same sibling-row rules
/// as the section: header and entries are separate List rows; collapsed entries are
/// not emitted.
struct StackGroupRow<HarnessBadge: View, TerminalBadge: View, HeaderMenu: View>: View {
    let group: StackGroup
    let worktreeForBranch: (String) -> GitWorktree?
    let baseMismatch: (StackBranch) -> String?
    let onJumpToWorktree: (GitWorktree) -> Void
    let onNewWorktree: () -> Void
    /// Bundled launch/insertion/remote actions for an entry.
    let entryActions: (StackBranch) -> StackEntryActions
    let onBreakOutBranch: (StackBranch) -> Void
    let onRestackFromHereBranch: (StackBranch) -> Void
    let onSubmitBranch: (StackBranch) -> Void
    /// Row-icon parity with worktree rows (Revision 11b): the trailing jigsaw badge
    /// reflecting the stack's effective harness. Injected so this view stays dumb about
    /// harness resolution — mirrors how `entryActions` is injected.
    @ViewBuilder let harnessBadge: () -> HarnessBadge
    /// Row-icon parity (Revision 11f): the leading open-terminal-count badge, same slot
    /// worktree rows use next to their left status icon. Injected so this view stays
    /// dumb about terminal-card lookup — mirrors how `harnessBadge` is injected.
    @ViewBuilder let terminalBadge: () -> TerminalBadge
    /// Row-icon parity (Revision 11b): quick-terminal launch at the stack TIP via the
    /// caller's guarded `stackLaunch` path (implicit worktree creation included).
    let onQuickTerminal: () -> Void
    /// Group primary click (Revision 11d): launch at the stack TIP, mirroring
    /// `primaryAction(worktree:repo:)`. The chevron and anchored badge keep their own
    /// click targets — only the title text routes through this closure.
    let onPrimaryAction: () -> Void
    /// Header context menu, injected by the presenting view — zero action logic here.
    @ViewBuilder let headerContextMenu: () -> HeaderMenu
    @State private var isExpanded = false

    /// The first worktree anchoring this stack, if any — the header's jump target.
    private var anchoringWorktree: GitWorktree? {
        group.branches.compactMap { worktreeForBranch($0.name) }.first
    }

    /// A stack is anchored when any of its branches is checked out in a worktree.
    private var isAnchored: Bool {
        anchoringWorktree != nil
    }

    var body: some View {
        HStack(spacing: StackRowMetrics.chevronSpacing) {
            StackChevronButton(isExpanded: $isExpanded)

            Image(systemName: "square.stack.3d.up")
                .imageScale(.small)
                .foregroundColor(.secondary)

            // Row-icon parity (Revision 11f): same terminal-count slot worktree rows
            // show next to their left status icon.
            terminalBadge()

            // Title stacked over the anchoring worktree name (Revision 11e) — mirrors
            // `worktreeRowContent`'s title-over-commit-hash layout, so a stack row
            // reads the same two-line shape as a worktree row instead of crowding the
            // worktree name inline next to the title.
            VStack(alignment: .leading, spacing: 1) {
                // Plain-style title button (Revision 11d) — mirrors `worktreeRowContent`'s
                // title button: clicking launches at the stack tip. The chevron and
                // anchored name below keep their own separate click targets.
                Button(action: onPrimaryAction) {
                    Text(group.rootName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .help(group.rootName)

                if let anchoringWorktree {
                    // Names the anchoring worktree; clicking reveals its row (same jump
                    // as the context-menu item).
                    Button {
                        onJumpToWorktree(anchoringWorktree)
                    } label: {
                        Text(worktreeDisplayName(anchoringWorktree))
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(Strings.Stacks.anchoredBadgeHelp(worktreeDisplayName(anchoringWorktree)))
                    .accessibilityLabel(
                        Strings.Stacks.anchoredBadgeHelp(worktreeDisplayName(anchoringWorktree)))
                }
            }

            Spacer()

            // Trailing icon cluster reads left-to-right as: (optional) New Worktree,
            // Harness, Terminal — New Worktree leads because it's the odd one out
            // (only present when unanchored); Harness/Terminal always appear in that
            // order, matching worktree rows.
            if anchoringWorktree == nil {
                Button(action: onNewWorktree) {
                    Image(systemName: "plus.square.on.square")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .help(Strings.Stacks.anchorHelp)
            }

            harnessBadge()

            Button {
                onQuickTerminal()
            } label: {
                Image(systemName: "terminal")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(Strings.Sidebar.newTerminal)
        }
        .contextMenu { headerContextMenu() }

        if isExpanded {
            ForEach(group.branches) { branch in
                let worktree = worktreeForBranch(branch.name)
                StackBranchEntryRow(
                    branch: branch,
                    baseMismatch: baseMismatch(branch),
                    worktreePath: worktree?.path,
                    onJumpToWorktree: worktree.map { wt in { onJumpToWorktree(wt) } },
                    onBreakOut: worktree == nil ? { onBreakOutBranch(branch) } : nil,
                    onRestackFromHere: { onRestackFromHereBranch(branch) },
                    onSubmitBranch: { onSubmitBranch(branch) },
                    actions: entryActions(branch)
                )
                .padding(.leading, StackRowMetrics.contentColumn + StackRowMetrics.indentStep)
            }
        }
    }

    /// Display name of a worktree for the badge: the branch (matching worktree row
    /// titles) or the directory name for detached checkouts.
    private func worktreeDisplayName(_ worktree: GitWorktree) -> String {
        worktree.branch ?? URL(fileURLWithPath: worktree.path).lastPathComponent
    }
}
