import AppKit
import SwiftUI
import TermQCore
import TermQShared

// MARK: - Stack Entry Actions

/// Bundled context-menu actions for one stack branch entry — used by both the
/// worktree-row chain (`StackDisclosureRow`) and the STACKS inventory
/// (`StackGroupRow`), so `StackBranchEntryRow`'s initializers take one struct instead
/// of a dozen individual closures. `nil` fields hide their menu item.
struct StackEntryActions {
    var launchHarness: (name: String, action: () -> Void)?
    var runWithFocus: (() -> Void)?
    /// Row-icon/menu parity with `worktreeFocusMenuItems`'s cached-focus submenu
    /// (Revision 12a): one entry per cached focus name for the resolved harness. Empty
    /// when no run harness resolves or it has no cached focuses.
    var quickLaunchFocuses: [(name: String, action: () -> Void)] = []
    var quickTerminal: (() -> Void)?
    var createTerminal: (() -> Void)?
    var newBranchBefore: (() -> Void)?
    var newBranchAfter: (() -> Void)?
    var openRemoteBranch: (() -> Void)?
}

// MARK: - Add Branch to Stack Context

/// Carries the target repository and worktree into `AddBranchToStackSheet`, plus WHERE
/// the new branch attaches — an explicit target (the original "Add Branch to Stack" /
/// group-header "New Stacked Branch…" flow) or a position relative to a branch that
/// must be checked out first ("New Stacked Branch Before…/After…" on a chain entry).
struct AddBranchToStackContext: Identifiable {
    enum Insertion: Equatable {
        /// Create stacked on `target` (editable by the user in the sheet).
        case target(String)
        /// "Before": check `referenceBranch` out first, then `gs branch create --below`.
        case below(referenceBranch: String)
        /// "After": check `referenceBranch` out first, then `gs branch create --insert`.
        case above(referenceBranch: String)
    }

    let id = UUID()
    let repo: ObservableRepository
    let worktree: GitWorktree
    let insertion: Insertion

    /// Default insertion targets the worktree's own checked-out branch — the
    /// original "Add Branch to Stack" entry point's behavior.
    init(repo: ObservableRepository, worktree: GitWorktree, insertion: Insertion? = nil) {
        self.repo = repo
        self.worktree = worktree
        self.insertion = insertion ?? .target(worktree.branch ?? "")
    }
}

// MARK: - Switch Guard Failure

/// A guarded switch/launch was refused (dirty worktree, in-use, or checked out
/// elsewhere). Carries enough to offer "Break Out into Worktree…" as an escape hatch
/// for the branch that couldn't be switched to.
struct StackSwitchGuardFailure: Identifiable {
    let id = UUID()
    let message: String
    let repo: ObservableRepository
    let branch: String
}

// MARK: - New Stack Context

/// Carries the target repository into `NewStackSheet` — the STACKS section's "New
/// Stack…" footer (seeds a worktree-less stack).
struct NewStackContext: Identifiable {
    let id = UUID()
    let repo: ObservableRepository
}

// MARK: - Submit Stack Context

/// Carries the submit scope and affected branches into `SubmitStackSheet`.
struct SubmitStackContext: Identifiable {
    let id = UUID()
    let repo: ObservableRepository
    let worktree: GitWorktree
    let branches: [StackBranch]
    let scope: StackScope
}

// MARK: - Worktree Row (stack-aware)

extension WorktreeSidebarView {
    /// Renders a worktree row, wrapping it in the sidebar grid: a fixed leading
    /// chevron slot (shared by every row when the repo has any stacked worktree) and
    /// the stack chain below when expanded. Lives here (not in the main view file) so
    /// all stack-awareness stays in one place.
    ///
    /// Emits exactly ONE view per worktree (chain and conflict banner folded into the
    /// same VStack) — multiple loose siblings per ForEach element inside nested
    /// disclosure content is a recipe for List row-height misaccounting.
    @ViewBuilder
    func worktreeRow(
        _ worktree: GitWorktree, repo: ObservableRepository, allWorktrees: [GitWorktree],
        showChevronSlot: Bool
    ) -> some View {
        let chain = stackChain(for: worktree, repo: repo)
        // Header row, chain entries, and conflict banner are SIBLING List rows —
        // StackDisclosureRow's ViewBuilder body emits them individually so per-row
        // selection and context menus keep working.
        Group {
            StackDisclosureRow(
                chain: chain.count > 1 ? chain : [],
                showChevronSlot: showChevronSlot,
                currentBranch: worktree.branch,
                rowID: Self.worktreeRowID(worktree),
                isHighlighted: stackHighlightWorktreeID == Self.worktreeRowID(worktree),
                onSwitch: { branch in
                    Task { await switchStackBranch(to: branch, worktree: worktree, repo: repo) }
                },
                onRestackFromHere: { branch in
                    Task { await restackStack(worktree: worktree, repo: repo, from: branch) }
                },
                onSubmitBranch: { branch in
                    submitStackContext = SubmitStackContext(
                        repo: repo, worktree: worktree, branches: [branch],
                        scope: .branch(branch.name))
                },
                baseMismatch: { branch in
                    stackBaseMismatch(for: branch, repo: repo)
                },
                checkedOutElsewherePath: { branch in
                    guard let owner = viewModel.worktree(forBranch: branch.name, repo: repo),
                        owner.path != worktree.path
                    else { return nil }
                    return owner.path
                },
                onJumpToWorktree: { branch in
                    if let owner = viewModel.worktree(forBranch: branch.name, repo: repo) {
                        revealWorktree(owner, repo: repo)
                    }
                },
                onBreakOut: { branch in
                    convertWorktreeContext = ConvertWorktreeContext(repo: repo, branch: branch.name)
                },
                entryActions: { branch in
                    stackEntryActions(
                        for: branch, anchor: worktree, repo: repo, rootName: chain.first?.name ?? branch.name,
                        isFirstAboveTrunk: branch.name == chain.first?.name)
                },
                label: {
                    worktreeRowContent(worktree, repo: repo, allWorktrees: allWorktrees)
                },
                headerContextMenu: {
                    worktreeContextMenu(worktree, repo: repo)
                }
            )

            stackConflictBanner(for: worktree, repo: repo)
        }
        .padding(.leading, 4)
    }

    /// Whether any worktree in `trees` participates in a stack — drives the shared
    /// chevron slot so all rows of the repo align in one column. Repos with no stacks
    /// render without the slot, pixel-identical to the pre-stacks layout.
    func repoHasStackedWorktrees(_ trees: [GitWorktree], repo: ObservableRepository) -> Bool {
        trees.contains { stackChain(for: $0, repo: repo).count > 1 }
    }

    /// Stable scroll-target identity for a worktree row (Stacks-section jump).
    static func worktreeRowID(_ worktree: GitWorktree) -> String {
        "worktree-row-\(worktree.path)"
    }

    /// The chain of stack branches containing `worktree`'s checked-out branch, or `[]`
    /// when the repo isn't stacked, the branch isn't tracked, or it's a lone branch
    /// stacked directly on trunk with nothing above it.
    private func stackChain(for worktree: GitWorktree, repo: ObservableRepository) -> [StackBranch] {
        guard let branch = worktree.branch, let graph = viewModel.stacks[repo.id] else { return [] }
        return graph.chain(containing: branch)
    }

    /// Warning text when the entry's open PR targets a different base than its stack
    /// parent (happens after a downstack merge, until Sync Repo retargets). `nil` when
    /// consistent, unknown, or no PR data.
    private func stackBaseMismatch(for branch: StackBranch, repo: ObservableRepository) -> String? {
        guard let parent = branch.parent,
            let pr = (prService.prsByRepo[repo.path] ?? []).first(where: { $0.headRefName == branch.name }),
            let base = pr.baseRefName,
            base != parent
        else { return nil }
        return Strings.Stacks.baseMismatch(base, parent)
    }
}

// MARK: - Stacks Inventory Section

extension WorktreeSidebarView {
    /// The per-repo Stacks section, between the worktree list and Local Branches.
    /// Renders whenever the provider is available AND the repo is gs-initialized —
    /// even with zero tracked stacks, since the "New Stack…" footer is the bootstrap
    /// affordance for creating the first one. Hidden entirely when the provider is
    /// unavailable or the repo isn't initialized.
    @ViewBuilder
    func stacksSection(for repo: ObservableRepository) -> some View {
        let groups = viewModel.stackGroups(for: repo)
        if stackService.isAvailable, stackService.isStacked(repo: repo.path) {
            StacksSectionView(
                groups: groups,
                worktreeForBranch: { viewModel.worktree(forBranch: $0, repo: repo) },
                baseMismatch: { stackBaseMismatch(for: $0, repo: repo) },
                onJumpToWorktree: { worktree in
                    revealWorktree(worktree, repo: repo)
                },
                onNewWorktree: { group in
                    // Anchor the stack: check its bottom branch out as a worktree via
                    // the existing convert-branch flow (the branch already exists, so
                    // the new-branch sheet doesn't apply).
                    convertWorktreeContext = ConvertWorktreeContext(repo: repo, branch: group.rootName)
                },
                onNewStack: {
                    newStackContext = NewStackContext(repo: repo)
                },
                entryActions: { group, branch in
                    let anchoring = group.branches
                        .compactMap { viewModel.worktree(forBranch: $0.name, repo: repo) }.first
                    return stackEntryActions(
                        for: branch, anchor: anchoring, repo: repo, rootName: group.rootName,
                        isFirstAboveTrunk: branch.name == group.branches.first?.name)
                },
                onBreakOutBranch: { branch in
                    convertWorktreeContext = ConvertWorktreeContext(repo: repo, branch: branch.name)
                },
                onRestackFromHereBranch: { branch in
                    if let main = viewModel.mainWorktree(for: repo) {
                        Task { await restackStack(worktree: main, repo: repo, from: branch) }
                    }
                },
                onSubmitBranch: { branch in
                    if let main = viewModel.mainWorktree(for: repo) {
                        submitStackContext = SubmitStackContext(
                            repo: repo, worktree: main, branches: [branch],
                            scope: .branch(branch.name))
                    }
                },
                harnessBadge: { group in
                    let anchoring = group.branches
                        .compactMap { viewModel.worktree(forBranch: $0.name, repo: repo) }.first
                    stackGroupHarnessBadge(rootName: group.rootName, anchoringPath: anchoring?.path, repo: repo)
                },
                terminalBadge: { group in
                    let anchoring = group.branches
                        .compactMap { viewModel.worktree(forBranch: $0.name, repo: repo) }.first
                    if let anchoring {
                        TerminalCountBadge(
                            worktree: anchoring, allWorktrees: viewModel.worktrees[repo.id] ?? [],
                            boardVM: boardVM)
                    } else {
                        // Unanchored: no worktree path to attach terminals to. Empty
                        // circle keeps the column aligned with anchored rows.
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                            .imageScale(.small)
                            .frame(width: 14)
                    }
                },
                onQuickTerminal: { group in
                    let anchoring = group.branches
                        .compactMap { viewModel.worktree(forBranch: $0.name, repo: repo) }.first
                    guard let tip = group.branches.last else { return }
                    stackLaunch(
                        branch: tip.name, repo: repo, anchor: anchoring,
                        launch: stackLaunchQuickTerminalClosure(repo: repo))
                },
                onPrimaryAction: { group in
                    stackPrimaryAction(group: group, repo: repo)
                },
                groupContextMenu: { group in
                    stackGroupContextMenu(group, repo: repo)
                }
            )
            // No trailing modifiers: StacksSectionView emits sibling List rows, and a
            // modifier here would re-apply to every one of them.
        }
    }
}

// MARK: - Stack Launch Model

extension WorktreeSidebarView {
    /// Implements the "stack's single worktree" launch model (Round-3 spec, principle
    /// a): resolves the worktree to launch `branch` in, then calls `launch` with it.
    /// - Already checked out in its own worktree (e.g. broken out earlier) → launch
    ///   there directly, no switch.
    /// - `anchor` (some OTHER branch of the same stack checked out somewhere) →
    ///   guarded-switch it to `branch`, then launch. A guard failure (dirty, in-use,
    ///   checked out elsewhere) populates `stackSwitchGuardFailure`, whose alert offers
    ///   "Break Out into Worktree…" as an escape hatch.
    /// - No worktree anywhere → implicitly create one at `branch` (the exact code path
    ///   "Break Out into Worktree…" uses), then launch.
    func stackLaunch(
        branch: String, repo: ObservableRepository, anchor: GitWorktree?,
        launch: @escaping (GitWorktree) -> Void
    ) {
        if let owner = viewModel.worktree(forBranch: branch, repo: repo) {
            launch(owner)
            return
        }
        guard let anchor else {
            Task { await implicitlyCreateWorktreeAndLaunch(branch: branch, repo: repo, launch: launch) }
            return
        }
        Task {
            do {
                try await viewModel.switchStackBranch(repo: repo, worktree: anchor, to: branch)
                if let updated = viewModel.worktree(forBranch: branch, repo: repo) {
                    launch(updated)
                }
            } catch {
                stackSwitchGuardFailure = StackSwitchGuardFailure(
                    message: error.localizedDescription, repo: repo, branch: branch)
            }
        }
    }

    /// Stack group primary click (Revision 11d) — mirrors `primaryAction(worktree:repo:)`
    /// but stack-shaped: resolves the effective harness per the stack resolution order,
    /// then guard-switches (or implicitly creates a worktree for) the stack's TIP branch
    /// before launching. A guard failure surfaces the same "Break Out into Worktree…"
    /// alert as any other stack launch item.
    func stackPrimaryAction(group: StackGroup, repo: ObservableRepository) {
        guard let tip = group.branches.last else { return }
        let anchoring = group.branches
            .compactMap { viewModel.worktree(forBranch: $0.name, repo: repo) }.first
        let harnessName = ynhPersistence.effectiveStackHarness(
            repoPath: repo.path, rootName: group.rootName, worktreePath: anchoring?.path)
        if case .ready = ynhDetector.status, let name = harnessName {
            stackLaunch(
                branch: tip.name, repo: repo, anchor: anchoring,
                launch: stackLaunchAutoHarnessClosure(name, repo: repo))
        } else {
            stackLaunch(
                branch: tip.name, repo: repo, anchor: anchoring,
                launch: stackLaunchQuickTerminalClosure(repo: repo))
        }
    }

    /// Implicitly create a worktree at `branch` — the same mechanism "Break Out into
    /// Worktree…" uses (no rename; the branch already exists) — then run `launch`.
    /// Used when a stack (or one entry of it) has no worktree anywhere yet.
    func implicitlyCreateWorktreeAndLaunch(
        branch: String, repo: ObservableRepository, launch: @escaping (GitWorktree) -> Void
    ) async {
        let path = viewModel.inferWorktreePath(for: repo, branchName: branch)
        do {
            try await viewModel.checkoutBranchAsWorktree(repo: repo, branch: branch, path: path)
            if let created = viewModel.worktree(forBranch: branch, repo: repo) {
                launch(created)
            }
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    // MARK: Launch closures

    func stackLaunchHarnessClosure(_ harnessName: String, repo: ObservableRepository) -> (GitWorktree) -> Void {
        { worktree in self.onLaunchHarness?(harnessName, worktree.path, worktree.branch) }
    }

    /// Silent direct launch with resolved defaults — mirrors `primaryAction(worktree:repo:)`'s
    /// use of `onAutoLaunchHarness`, as opposed to `stackLaunchHarnessClosure`'s
    /// `onLaunchHarness`, which opens the manual Launch Harness sheet. Used by
    /// `stackPrimaryAction` so clicking a stack row behaves exactly like clicking a
    /// worktree row; the context-menu "Launch <Harness>" item keeps the sheet.
    func stackLaunchAutoHarnessClosure(_ harnessName: String, repo: ObservableRepository) -> (GitWorktree) -> Void {
        { worktree in self.onAutoLaunchHarness?(harnessName, worktree.path, worktree.branch) }
    }

    func stackLaunchRunWithFocusClosure(repo: ObservableRepository) -> (GitWorktree) -> Void {
        { worktree in
            let prNumber = self.linkedPRNumber(for: worktree, repo: repo)
            self.runWithFocusContext = RunWithFocusContext(worktree: worktree, repo: repo, prNumber: prNumber)
        }
    }

    /// Cached-focus one-click launch — mirrors `worktreeFocusMenuItems`'s "Quick Launch
    /// Focus" submenu (Revision 12a), routed through the guarded stack-launch path.
    func stackLaunchFocusClosure(
        _ focusName: String, harnessId: String, repo: ObservableRepository
    ) -> (GitWorktree) -> Void {
        { worktree in
            let prNumber = self.linkedPRNumber(for: worktree, repo: repo)
            self.quickLaunchFocus(
                focusName, worktree: worktree, repo: repo, prNumber: prNumber, harnessId: harnessId)
        }
    }

    func stackLaunchQuickTerminalClosure(repo: ObservableRepository) -> (GitWorktree) -> Void {
        { worktree in
            NSApp.keyWindow?.makeFirstResponder(nil)
            self.boardVM.newTerminal(
                at: worktree.path, branch: worktree.branch, repoName: self.orgRepoName(repoPath: repo.path))
        }
    }

    func stackLaunchCreateTerminalClosure(repo: ObservableRepository) -> (GitWorktree) -> Void {
        { worktree in
            self.boardVM.addTerminal(
                workingDirectory: worktree.path, branch: worktree.branch,
                repoName: self.orgRepoName(repoPath: repo.path))
        }
    }

    /// Open the remote commit page for `branch`'s current tip commit — read-only:
    /// the hash resolves via rev-parse, no checkout or switch involved.
    func openRemoteCommit(branch: String, repo: ObservableRepository) {
        Task {
            guard let hash = try? await GitService.shared.commitHash(repoPath: repo.path, ref: branch),
                let raw = try? await GitService.shared.remoteURL(repoPath: repo.path),
                let base = remoteWebURL(from: raw)
            else { return }
            let urlStr = base.absoluteString + "/commit/" + hash
            if let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: New Stacked Branch Before/After

    /// Opens `AddBranchToStackSheet` for a Before/After insertion. Resolves the target
    /// worktree the same way `stackLaunch` does — the entry's own worktree, else the
    /// group/chain's anchor, else implicitly create one at `branch.name` first (the
    /// sheet's own submit then checks out `branch.name` there, a no-op since it's
    /// already current).
    func openNewStackedBranchSheet(
        insertion: AddBranchToStackContext.Insertion, branch: StackBranch, anchor: GitWorktree?,
        repo: ObservableRepository
    ) {
        if let target = viewModel.worktree(forBranch: branch.name, repo: repo) ?? anchor {
            addBranchToStackContext = AddBranchToStackContext(repo: repo, worktree: target, insertion: insertion)
            return
        }
        Task {
            await implicitlyCreateWorktreeAndLaunch(branch: branch.name, repo: repo) { created in
                self.addBranchToStackContext = AddBranchToStackContext(
                    repo: repo, worktree: created, insertion: insertion)
            }
        }
    }

    /// Builds the bundled entry actions for `branch`, shared by the worktree-row chain
    /// and the STACKS inventory. `anchor` is the worktree to guard-switch when `branch`
    /// isn't already checked out somewhere of its own; `nil` when nothing anchors the
    /// stack yet (implicit creation kicks in). `rootName` is the stack's root branch
    /// name — the key for the stack-level harness override (Revision 11c). `isFirstAboveTrunk`
    /// hides "New Stacked Branch Before…" on the stack's root entry.
    func stackEntryActions(
        for branch: StackBranch, anchor: GitWorktree?, repo: ObservableRepository, rootName: String,
        isFirstAboveTrunk: Bool
    ) -> StackEntryActions {
        let owner = viewModel.worktree(forBranch: branch.name, repo: repo) ?? anchor
        let effectiveHarness = ynhPersistence.effectiveStackHarness(
            repoPath: repo.path, rootName: rootName, worktreePath: owner?.path)

        var actions = StackEntryActions()
        if let harnessName = effectiveHarness {
            actions.launchHarness = (
                harnessName,
                {
                    self.stackLaunch(
                        branch: branch.name, repo: repo, anchor: anchor,
                        launch: self.stackLaunchHarnessClosure(harnessName, repo: repo))
                }
            )
        }
        actions.runWithFocus = {
            self.stackLaunch(
                branch: branch.name, repo: repo, anchor: anchor,
                launch: self.stackLaunchRunWithFocusClosure(repo: repo))
        }
        let runHarnessId =
            ynhPersistence.runHarness(for: repo.path) ?? ynhPersistence.repoDefaultHarness(for: repo.path)
        let cachedFocuses: [String] =
            runHarnessId.flatMap { id in
                harnessRepository.cachedDetail(for: id)?.composition.focuses
            }.map { $0.keys.sorted() } ?? []
        if let runHarnessId, !cachedFocuses.isEmpty {
            actions.quickLaunchFocuses = cachedFocuses.map { focusName in
                (
                    focusName,
                    {
                        self.stackLaunch(
                            branch: branch.name, repo: repo, anchor: anchor,
                            launch: self.stackLaunchFocusClosure(
                                focusName, harnessId: runHarnessId, repo: repo))
                    }
                )
            }
        }
        actions.quickTerminal = {
            self.stackLaunch(
                branch: branch.name, repo: repo, anchor: anchor,
                launch: self.stackLaunchQuickTerminalClosure(repo: repo))
        }
        actions.createTerminal = {
            self.stackLaunch(
                branch: branch.name, repo: repo, anchor: anchor,
                launch: self.stackLaunchCreateTerminalClosure(repo: repo))
        }
        if !isFirstAboveTrunk {
            actions.newBranchBefore = {
                self.openNewStackedBranchSheet(
                    insertion: .below(referenceBranch: branch.name), branch: branch, anchor: anchor, repo: repo)
            }
        }
        actions.newBranchAfter = {
            self.openNewStackedBranchSheet(
                insertion: .above(referenceBranch: branch.name), branch: branch, anchor: anchor, repo: repo)
        }
        actions.openRemoteBranch = {
            self.openBranchOnRemote(branch: branch.name, repo: repo)
        }
        return actions
    }
}

// MARK: - Stack Group Context Menu

extension WorktreeSidebarView {
    /// The STACKS group-header context menu (Round-3 order). The group operates on the
    /// stack as a whole — launch items target the TIP (latest) branch via
    /// `stackLaunch`. Anchored groups follow the full order below; unanchored groups
    /// get the same launch items (implicitly creating a worktree at the tip on first
    /// use) plus the existing "anchor the stack" action and stack operations —
    /// worktree-scoped conveniences (reveal/remote-links/harness) have no target
    /// without a worktree. Worktree-lifecycle items (lock, remove, destroy) stay
    /// exclusive to the worktree row — the group is not the worktree.
    ///
    /// Stack mutations (restack/submit/sync) execute with the repo's MAIN worktree as
    /// CWD (gs targets branches via --branch; no checkout needed) through the same
    /// per-repo mutation queue, spinners, and toasts.
    @ViewBuilder
    func stackGroupContextMenu(_ group: StackGroup, repo: ObservableRepository) -> some View {
        let anchoring = group.branches
            .compactMap { viewModel.worktree(forBranch: $0.name, repo: repo) }.first
        let tip = group.branches.last
        let isMutating = stackService.isMutating(repo: repo.path)

        if let tip {
            stackGroupLaunchMenuItems(tip: tip, anchoring: anchoring, repo: repo, rootName: group.rootName)
        }

        Divider()
        if let anchoring, let tip {
            Button {
                addBranchToStackContext = AddBranchToStackContext(
                    repo: repo, worktree: anchoring, insertion: .target(tip.name))
            } label: {
                // Same sheet as the worktree row's "Add Branch to Stack…" item
                // (Revision 12b) — was "New Stacked Branch…" here, a different label
                // for an identical action depending on which row you right-clicked.
                Label(Strings.Stacks.addBranch, systemImage: "square.stack.3d.up.badge.a")
            }
            .disabled(isMutating)
            Button {
                newWorktreeContext = NewWorktreeContext(repo: repo, initialBaseBranch: nil)
            } label: {
                Label(Strings.Sidebar.newWorktree, systemImage: "plus")
            }

            Divider()
            worktreeRevealMenuItems(anchoring)

            Divider()
            Button {
                openBranchOnRemote(branch: tip.name, repo: repo)
            } label: {
                Label(Strings.Sidebar.openRemoteBranch, systemImage: "network")
            }
            Button {
                // Read-only: the tip's commit hash resolves via rev-parse — never
                // switch a worktree as a side-effect of opening a URL.
                openRemoteCommit(branch: tip.name, repo: repo)
            } label: {
                Label(Strings.Sidebar.openRemoteCommit, systemImage: "chevron.left.forwardslash.chevron.right")
            }
        } else {
            Button {
                convertWorktreeContext = ConvertWorktreeContext(repo: repo, branch: group.rootName)
            } label: {
                Label(Strings.Stacks.groupNewWorktree, systemImage: "plus")
            }
        }

        Divider()
        Button {
            if let main = viewModel.mainWorktree(for: repo), let root = group.branches.first {
                Task { await restackStack(worktree: main, repo: repo, from: root) }
            }
        } label: {
            Label(Strings.Stacks.restackStack, systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(isMutating)

        Button {
            if let main = viewModel.mainWorktree(for: repo), let root = group.branches.first {
                submitStackContext = SubmitStackContext(
                    repo: repo, worktree: main, branches: group.branches,
                    scope: .upstack(from: root.name))
            }
        } label: {
            Label(Strings.Stacks.submitStack, systemImage: "paperplane")
        }
        .disabled(isMutating)

        Button {
            if let main = viewModel.mainWorktree(for: repo) {
                Task { await syncStackRepo(worktree: main, repo: repo) }
            }
        } label: {
            Label(Strings.Stacks.syncRepo, systemImage: "arrow.triangle.2.circlepath.circle")
        }
        .disabled(isMutating)

        Button(role: .destructive) {
            pendingDestroyStack = (repo, group)
            isShowingDestroyStackAlert = true
        } label: {
            Label(Strings.Stacks.destroyStack, systemImage: "trash")
        }
        .disabled(isMutating)

        if !harnessRepository.harnesses.isEmpty {
            Divider()
            stackHarnessContextItems(repoPath: repo.path, rootName: group.rootName)
        }

        if let anchoring {
            Divider()
            Button {
                revealWorktree(anchoring, repo: repo)
            } label: {
                Label(Strings.Stacks.revealWorktree, systemImage: "arrow.turn.down.left")
            }
        }
    }

    /// The group header's launch items — Launch <Harness> / Run with Focus…, then
    /// Quick Terminal / Create Terminal…, all targeting `tip` via `stackLaunch`. The
    /// harness resolves per Revision 11c: stack override → anchoring worktree override
    /// → repo default.
    @ViewBuilder
    private func stackGroupLaunchMenuItems(
        tip: StackBranch, anchoring: GitWorktree?, repo: ObservableRepository, rootName: String
    ) -> some View {
        let effectiveHarness = ynhPersistence.effectiveStackHarness(
            repoPath: repo.path, rootName: rootName, worktreePath: anchoring?.path)

        if let harnessName = effectiveHarness {
            Button {
                stackLaunch(
                    branch: tip.name, repo: repo, anchor: anchoring,
                    launch: stackLaunchHarnessClosure(harnessName, repo: repo))
            } label: {
                Label(Strings.Sidebar.launchHarness(harnessName), systemImage: "play.fill")
            }
        }
        Button {
            stackLaunch(
                branch: tip.name, repo: repo, anchor: anchoring,
                launch: stackLaunchRunWithFocusClosure(repo: repo))
        } label: {
            Label(Strings.RemotePRs.runWithFocus, systemImage: "eye")
        }

        // Quick Launch Focus submenu — row-icon/menu parity with
        // `worktreeFocusMenuItems` (Revision 12a): one entry per cached focus name for
        // the resolved run harness, launched directly at the stack's TIP.
        let runHarnessId =
            ynhPersistence.runHarness(for: repo.path) ?? ynhPersistence.repoDefaultHarness(for: repo.path)
        let cachedFocuses: [String] =
            runHarnessId.flatMap { id in
                harnessRepository.cachedDetail(for: id)?.composition.focuses
            }.map { $0.keys.sorted() } ?? []
        if let runHarnessId, !cachedFocuses.isEmpty {
            Menu(Strings.RemotePRs.quickLaunchFocus) {
                ForEach(cachedFocuses, id: \.self) { focusName in
                    Button(Strings.RemotePRs.runFocusItem(focusName)) {
                        stackLaunch(
                            branch: tip.name, repo: repo, anchor: anchoring,
                            launch: stackLaunchFocusClosure(focusName, harnessId: runHarnessId, repo: repo))
                    }
                }
            }
        }

        Divider()
        Button {
            stackLaunch(
                branch: tip.name, repo: repo, anchor: anchoring,
                launch: stackLaunchQuickTerminalClosure(repo: repo))
        } label: {
            Label(Strings.Sidebar.newTerminal, systemImage: "terminal")
        }
        Button {
            stackLaunch(
                branch: tip.name, repo: repo, anchor: anchoring,
                launch: stackLaunchCreateTerminalClosure(repo: repo))
        } label: {
            Label(Strings.Sidebar.createTerminal, systemImage: "plus.rectangle")
        }
    }
}

// MARK: - Stack Actions

extension WorktreeSidebarView {
    /// Reveal a worktree row from anywhere (badge, menu items, chain indicators):
    /// expand its ancestors first — collapsed rows are not emitted, so scrollTo has
    /// nothing to find until they exist — then, after a runloop beat, scroll to the
    /// row and pulse a brief highlight so the user sees where the jump landed.
    func revealWorktree(_ worktree: GitWorktree, repo: ObservableRepository) {
        viewModel.prepareRevealWorktree(for: repo)
        let rowID = Self.worktreeRowID(worktree)
        Task { @MainActor in
            // One beat for SwiftUI to emit the newly expanded rows.
            try? await Task.sleep(nanoseconds: 80_000_000)
            stackJumpTargetWorktreeID = rowID
            stackHighlightWorktreeID = rowID
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if stackHighlightWorktreeID == rowID {
                stackHighlightWorktreeID = nil
            }
        }
    }

    /// Guarded switch — blocked errors surface through the standard error alert.
    func switchStackBranch(
        to branch: StackBranch, worktree: GitWorktree, repo: ObservableRepository
    ) async {
        do {
            try await viewModel.switchStackBranch(repo: repo, worktree: worktree, to: branch.name)
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    /// "Restack from Here" on a stack entry (`from` set) or "Restack Stack" from the
    /// worktree context menu (`from` nil). A conflict pause is not an error — the
    /// banner appears from `stackService.conflicts`. Success and no-op outcomes are
    /// surfaced via toast so the mutation never finishes silently.
    func restackStack(
        worktree: GitWorktree, repo: ObservableRepository, from branch: StackBranch? = nil
    ) async {
        do {
            let scope: StackScope = branch.map { .upstack(from: $0.name) } ?? .stack
            let report = try await viewModel.restack(repo: repo, worktree: worktree, scope: scope)
            var lines: [String] = []
            switch report.outcome {
            case .upToDate:
                lines.append(Strings.Stacks.restackUpToDate)
            case .restacked(let count):
                lines.append(Strings.Stacks.restackDone(count))
            case .paused:
                break  // the conflict banner reports it
            }
            if !report.skipped.isEmpty {
                lines.append(
                    Strings.Stacks.skippedNotice(
                        report.skipped.map(\.noticeLine).joined(separator: ", ")))
            }
            if !lines.isEmpty {
                showStackToast(lines.joined(separator: "\n"))
            }
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    func showStackToast(_ message: String) {
        pendingToast = SidebarToast(message: message, actionLabel: nil, action: nil)
    }

    /// Confirmation body for "Destroy Stack": lists the branches that will be deleted,
    /// plus a warning line when any of them still has an open PR — deleting the local
    /// branch there wouldn't touch the PR, but it's worth flagging before proceeding.
    func destroyStackAlertMessage(for group: StackGroup) -> String {
        let names = group.branches.map(\.name).joined(separator: ", ")
        var lines = [Strings.Stacks.destroyStackMessage(group.branches.count, names)]
        let openCount = group.branches.filter { $0.changeRequest?.status == .open }.count
        if openCount > 0 {
            lines.append(Strings.Stacks.destroyStackOpenPRWarning(openCount))
        }
        return lines.joined(separator: "\n\n")
    }

    /// Runs the confirmed "Destroy Stack" mutation and reports the outcome via toast —
    /// branches deleted, plus any worktree left untouched because it had uncommitted
    /// changes (so no local work is silently discarded).
    func destroyStack(group: StackGroup, repo: ObservableRepository) async {
        do {
            let report = try await viewModel.destroyStack(repo: repo, group: group)
            var lines = [Strings.Stacks.destroyStackDone(report.deletedBranches.count)]
            if !report.skippedDirtyWorktrees.isEmpty {
                lines.append(
                    Strings.Stacks.destroyStackWorktreeSkipped(
                        report.skippedDirtyWorktrees.joined(separator: ", ")))
            }
            showStackToast(lines.joined(separator: "\n"))
        } catch {
            if stackService.conflicts[repo.path] != nil {
                return  // the conflict banner reports it
            }
            viewModel.operationError = error.localizedDescription
        }
    }

    /// Context-menu items for stack operations on a worktree. Empty when no provider
    /// is available or the repo isn't stack-initialized. Mutating actions are disabled
    /// while a stack mutation is already in flight for the repo — the queue serializes
    /// anyway, but the UI should reflect it rather than silently stacking requests.
    @ViewBuilder
    func stackContextMenuItems(_ worktree: GitWorktree, repo: ObservableRepository) -> some View {
        if stackService.isAvailable && stackService.isStacked(repo: repo.path) {
            let isMutating = stackService.isMutating(repo: repo.path)
            Divider()

            Button {
                addBranchToStackContext = AddBranchToStackContext(repo: repo, worktree: worktree)
            } label: {
                Label(Strings.Stacks.addBranch, systemImage: "square.stack.3d.up.badge.a")
            }
            .disabled(isMutating)

            if let branch = worktree.branch, viewModel.stacks[repo.id]?.isStacked(branch) == true {
                Button {
                    Task { await restackStack(worktree: worktree, repo: repo) }
                } label: {
                    Label(Strings.Stacks.restackStack, systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isMutating)
                Button {
                    let chain = viewModel.stacks[repo.id].map { $0.chain(containing: branch) } ?? []
                    submitStackContext = SubmitStackContext(
                        repo: repo, worktree: worktree, branches: chain, scope: .stack)
                } label: {
                    Label(Strings.Stacks.submitStack, systemImage: "paperplane")
                }
                .disabled(isMutating)
            }

            Button {
                Task { await syncStackRepo(worktree: worktree, repo: repo) }
            } label: {
                Label(Strings.Stacks.syncRepo, systemImage: "arrow.triangle.2.circlepath.circle")
            }
            .disabled(isMutating)
        }
    }

    /// Sync Repo from the context menu — always confirms completion: either the list
    /// of removed merged branches or an explicit "everything in sync".
    func syncStackRepo(worktree: GitWorktree, repo: ObservableRepository) async {
        do {
            let report = try await viewModel.syncStackRepo(for: repo, worktree: worktree)
            if stackService.conflicts[repo.path] != nil {
                return  // the conflict banner reports it
            }
            showStackToast(syncToastMessage(for: report))
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    /// Sync outcome line(s): removed-branches summary or "everything in sync", plus a
    /// notice for branches the cross-worktree sweep couldn't restack.
    func syncToastMessage(for report: StackSyncReport) -> String {
        var lines: [String] = []
        if report.removedBranches.isEmpty {
            lines.append(Strings.Stacks.syncClean)
        } else {
            lines.append(
                Strings.Stacks.syncCleaned(
                    report.removedBranches.count,
                    report.removedBranches.joined(separator: ", ")))
        }
        if !report.skipped.isEmpty {
            lines.append(
                Strings.Stacks.skippedNotice(
                    report.skipped.map(\.noticeLine).joined(separator: ", ")))
        }
        return lines.joined(separator: "\n")
    }

    /// Conflict banner shown below the worktree row while a stack operation is paused
    /// on conflicts in this worktree.
    @ViewBuilder
    func stackConflictBanner(for worktree: GitWorktree, repo: ObservableRepository) -> some View {
        if let conflict = stackService.conflicts[repo.path], conflict.worktree == worktree.path {
            StackConflictBanner(
                conflict: conflict,
                isWorking: stackConflictWorking,
                onContinue: {
                    Task { await resumeStackConflict(repo: repo, worktree: conflict.worktree) }
                },
                onAbort: {
                    Task { await abortStackConflict(repo: repo, worktree: conflict.worktree) }
                }
            )
            .padding(.leading, 22)
            .padding(.trailing, 4)
        }
    }

    private func resumeStackConflict(repo: ObservableRepository, worktree: String) async {
        stackConflictWorking = true
        defer { stackConflictWorking = false }
        do {
            try await viewModel.continueStackOperation(repo: repo, worktree: worktree)
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    private func abortStackConflict(repo: ObservableRepository, worktree: String) async {
        stackConflictWorking = true
        defer { stackConflictWorking = false }
        do {
            try await viewModel.abortStackOperation(repo: repo, worktree: worktree)
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }
}
