import AppKit
import SwiftUI
import TermQCore
import TermQShared

/// Collapsible sidebar showing registered repositories and their worktrees.
struct WorktreeSidebarView: View {
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    var onLaunchHarness: ((String, String, String?) -> Void)?
    var onAutoLaunchHarness: ((String, String, String?) -> Void)?
    var onRunWithFocus: ((HarnessLaunchConfig) -> Void)?
    @ObservedObject var boardVM: BoardViewModel = .shared
    @ObservedObject var harnessRepository: HarnessRepository = .shared
    @ObservedObject var ynhPersistence: YNHPersistence = .shared
    @ObservedObject var ynhDetector: YNHDetector = .shared
    @ObservedObject private var editorRegistry: EditorRegistry = .shared
    @ObservedObject var prService: GitHubPRService = .shared
    @ObservedObject var ghProbe: GhCliProbe = .shared
    @ObservedObject var stackService: StackService = .shared
    @ObservedObject private var menuCoordinator: SidebarMenuCoordinator = .shared
    @ObservedObject var workspaceStore: WorkspaceStore = .shared
    @Environment(SettingsStore.self) var settings
    // Per-window mode (Local vs Remote). Transient — not persisted.
    @State var sidebarMode: SidebarMode = .local
    // Sheets and alerts for PR operations.
    @State private var checkoutPRContext: CheckoutPRContext?
    @State private var forceUpdatePRContext: ForceUpdatePRContext?
    @State var isShowingPruneClosedPRsFor: ObservableRepository?
    @State var pruneClosedPRsCandidates: [PRPruneCandidate] = []
    @State var focusPruneCandidates: [FocusWorktreeCandidate] = []
    @State var pendingToast: SidebarToast?
    @State var runWithFocusContext: RunWithFocusContext?
    @State private var showAddRepo = false
    // Internal (not private) so the empty-state views in WorktreeSidebarView+Workspace.swift can drive it.
    @State var showManageWorkspaces = false
    // Internal (not private) so the STACKS group-header menu in
    // WorktreeSidebarView+Stacks.swift can offer the generic "New Worktree…" action.
    @State var newWorktreeContext: NewWorktreeContext?
    // Internal (not private) so the Stacks section in WorktreeSidebarView+Stacks.swift
    // can anchor an unanchored stack by converting its bottom branch to a worktree.
    @State var convertWorktreeContext: ConvertWorktreeContext?
    @State private var showEditRepoFor: ObservableRepository?
    @State private var pendingRemoval: (ObservableRepository, GitWorktree)?
    @State private var isShowingRemoveAlert = false
    @State private var pendingForceDelete: (ObservableRepository, GitWorktree)?
    @State private var isShowingDeleteAlert = false
    @State private var pruneSheetFor: ObservableRepository?
    @State private var pruneStaleEntries: [String] = []
    @State private var isShowingPruneNothingAlert = false
    @State private var isPruneAnalysing = false
    @State private var pruneAllContext: PruneAllContext?
    @State private var pruneBranchesSheetFor: ObservableRepository?
    @State private var branchToDelete: (ObservableRepository, String)?
    @State private var isShowingDeleteBranchAlert = false
    @State private var branchToDestroy: (ObservableRepository, String)?
    @State private var isShowingDestroyBranchAlert = false
    @State var addBranchToStackContext: AddBranchToStackContext?
    @State var submitStackContext: SubmitStackContext?
    @State var stackConflictWorking = false
    /// A guarded switch/launch was blocked (dirty worktree, in-use, checked out
    /// elsewhere) — the error alert offers "Break Out into Worktree…" as an escape.
    @State var stackSwitchGuardFailure: StackSwitchGuardFailure?
    @State var newStackContext: NewStackContext?
    @State var pendingDestroyStack: (ObservableRepository, StackGroup)?
    @State var isShowingDestroyStackAlert = false
    /// Worktree row to scroll into view — set by the Stacks section's jump indicator,
    /// consumed by the ScrollViewReader wrapping the repo list.
    @State var stackJumpTargetWorktreeID: String?
    /// Worktree row briefly highlighted after a reveal, so the user sees where the
    /// jump landed.
    @State var stackHighlightWorktreeID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.displayedRepositories.isEmpty { emptyState } else { repoList }
        }
        .overlay(alignment: .bottom) {
            if let toast = pendingToast {
                SidebarToastBanner(toast: toast, onDismiss: { pendingToast = nil })
                    .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showAddRepo) { AddRepositorySheet(viewModel: viewModel) }
        .onAppear { consumeMenuRequest() }
        .onChange(of: menuCoordinator.pending) { _, _ in consumeMenuRequest() }
        .sheet(isPresented: $showManageWorkspaces) { ManageWorkspacesSheet(store: workspaceStore) }
        .sheet(item: $newWorktreeContext) { ctx in
            NewWorktreeSheet(repo: ctx.repo, initialBaseBranch: ctx.initialBaseBranch, viewModel: viewModel)
        }
        .sheet(item: $convertWorktreeContext) { ctx in
            ConvertToWorktreeSheet(repo: ctx.repo, originalBranch: ctx.branch, viewModel: viewModel)
        }
        .sheet(item: $addBranchToStackContext) { ctx in
            AddBranchToStackSheet(
                repo: ctx.repo, worktree: ctx.worktree, insertion: ctx.insertion, viewModel: viewModel)
        }
        .sheet(item: $newStackContext) { ctx in
            NewStackSheet(repo: ctx.repo, viewModel: viewModel)
        }
        .sheet(item: $submitStackContext) { ctx in
            SubmitStackSheet(
                repo: ctx.repo, worktree: ctx.worktree, branches: ctx.branches,
                scope: ctx.scope, viewModel: viewModel,
                onComplete: { created, updated in
                    showStackToast(Strings.Stacks.submitDone(created, updated))
                })
        }
        .sheet(item: $showEditRepoFor) { repo in EditRepositorySheet(repo: repo, viewModel: viewModel) }
        .sheet(item: $pruneSheetFor) { repo in
            PruneWorktreesSheet(repo: repo, staleEntries: pruneStaleEntries, viewModel: viewModel)
        }
        .sheet(item: $pruneAllContext) { ctx in
            PruneAllWorktreesSheet(candidates: ctx.candidates, viewModel: viewModel)
        }
        .sheet(item: $pruneBranchesSheetFor) { repo in PruneBranchesSheet(repo: repo, viewModel: viewModel) }
        .sheet(item: $forceUpdatePRContext) { ctx in ForceUpdatePRSheet(context: ctx, viewModel: viewModel) }
        .sheet(item: $runWithFocusContext) { ctx in
            RunWithFocusSheet(
                context: ctx,
                onLaunch: { cfg in
                    onRunWithFocus?(cfg)
                    runWithFocusContext = nil
                },
                onCancel: { runWithFocusContext = nil }
            )
        }
        .sheet(item: $isShowingPruneClosedPRsFor) { makePruneClosedPRsSheet(repo: $0) }
        .alert(Strings.Sidebar.pruneWorktreesNothingTitle, isPresented: $isShowingPruneNothingAlert) {
            Button(Strings.Common.ok) {}
        } message: {
            Text(Strings.Sidebar.pruneWorktreesNothingMessage)
        }
        .alert(Strings.Sidebar.removeWorktreeTitle, isPresented: $isShowingRemoveAlert) {
            Button(Strings.Sidebar.removeWorktreeConfirm, role: .destructive) {
                if let (repo, worktree) = pendingRemoval {
                    Task {
                        do { try await viewModel.removeWorktree(repo: repo, worktree: worktree) } catch {
                            viewModel.operationError = error.localizedDescription
                        }
                    }
                    pendingRemoval = nil
                }
            }
            Button(Strings.Sidebar.cancelButton, role: .cancel) { pendingRemoval = nil }
        } message: {
            if let (_, worktree) = pendingRemoval { Text(Strings.Sidebar.removeWorktreeMessage(worktree.path)) }
        }
        .alert(Strings.Sidebar.deleteWorktreeTitle, isPresented: $isShowingDeleteAlert) {
            Button(Strings.Sidebar.deleteWorktreeConfirm, role: .destructive) {
                if let (repo, worktree) = pendingForceDelete {
                    Task {
                        do { try await viewModel.forceDeleteWorktree(repo: repo, worktree: worktree) } catch {
                            viewModel.operationError = error.localizedDescription
                        }
                    }
                    pendingForceDelete = nil
                }
            }
            Button(Strings.Sidebar.cancelButton, role: .cancel) { pendingForceDelete = nil }
        } message: {
            if let (_, worktree) = pendingForceDelete { Text(Strings.Sidebar.deleteWorktreeMessage(worktree.path)) }
        }
        .alert(Strings.Stacks.destroyStackTitle, isPresented: $isShowingDestroyStackAlert) {
            Button(Strings.Stacks.destroyStackConfirm, role: .destructive) {
                if let (repo, group) = pendingDestroyStack {
                    Task { await destroyStack(group: group, repo: repo) }
                    pendingDestroyStack = nil
                }
            }
            Button(Strings.Sidebar.cancelButton, role: .cancel) { pendingDestroyStack = nil }
        } message: {
            if let (_, group) = pendingDestroyStack { Text(destroyStackAlertMessage(for: group)) }
        }
        .alert(Strings.Sidebar.deleteBranchTitle, isPresented: $isShowingDeleteBranchAlert) {
            Button(Strings.Sidebar.deleteBranchConfirm, role: .destructive) {
                if let (repo, branch) = branchToDelete {
                    Task {
                        do { try await viewModel.deleteBranch(repo: repo, branch: branch) } catch {
                            viewModel.operationError = error.localizedDescription
                        }
                    }
                    branchToDelete = nil
                }
            }
            Button(Strings.Sidebar.cancelButton, role: .cancel) { branchToDelete = nil }
        } message: {
            if let (_, branch) = branchToDelete { Text(Strings.Sidebar.deleteBranchMessage(branch)) }
        }
        .alert(Strings.Sidebar.destroyBranchTitle, isPresented: $isShowingDestroyBranchAlert) {
            Button(Strings.Sidebar.destroyBranchConfirm, role: .destructive) {
                if let (repo, branch) = branchToDestroy {
                    Task {
                        do { try await viewModel.forceDeleteBranch(repo: repo, branch: branch) } catch {
                            viewModel.operationError = error.localizedDescription
                        }
                    }
                    branchToDestroy = nil
                }
            }
            Button(Strings.Sidebar.cancelButton, role: .cancel) { branchToDestroy = nil }
        } message: {
            if let (_, branch) = branchToDestroy { Text(Strings.Sidebar.destroyBranchMessage(branch)) }
        }
        .alert(
            Strings.Alert.error,
            isPresented: Binding(
                get: { viewModel.operationError != nil },
                set: { if !$0 { viewModel.operationError = nil } }
            )
        ) {
            Button(Strings.Common.ok) { viewModel.operationError = nil }
        } message: {
            if let msg = viewModel.operationError { Text(msg) }
        }
        .alert(
            Strings.Alert.error,
            isPresented: Binding(
                get: { stackSwitchGuardFailure != nil },
                set: { if !$0 { stackSwitchGuardFailure = nil } }
            ),
            presenting: stackSwitchGuardFailure
        ) { failure in
            Button(Strings.Stacks.breakOut) {
                convertWorktreeContext = ConvertWorktreeContext(repo: failure.repo, branch: failure.branch)
                stackSwitchGuardFailure = nil
            }
            Button(Strings.Common.ok, role: .cancel) { stackSwitchGuardFailure = nil }
        } message: { failure in
            Text(failure.message)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                WorkspaceSwitcher(store: workspaceStore)

                Spacer()

                Button {
                    showAddRepo = true
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help(Strings.Sidebar.addButtonHelp)

                Button {
                    viewModel.refresh()
                    if sidebarMode == .remote {
                        Task { await prService.refreshAll(force: true) }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help(Strings.Sidebar.refreshWorktrees)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if ghProbe.status != .missing {
                Picker("", selection: $sidebarMode) {
                    Text(Strings.RemotePRs.modeLocal).tag(SidebarMode.local)
                    Text(Strings.RemotePRs.modeRemote).tag(SidebarMode.remote)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .onChange(of: sidebarMode) { _, newMode in
                    if newMode == .remote {
                        for repo in viewModel.repositories {
                            Task { await prService.refresh(repoPath: repo.path) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Repository List

    private var repoList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(viewModel.displayedRepositories) { repo in
                    repoRow(repo)
                }
                .onMove(perform: reorderHandler)
            }
            .listStyle(.sidebar)
            .onChange(of: stackJumpTargetWorktreeID) { _, target in
                guard let target else { return }
                withAnimation {
                    proxy.scrollTo(target, anchor: .center)
                }
                stackJumpTargetWorktreeID = nil
            }
        }
    }

    @ViewBuilder
    private func repoRow(_ repo: ObservableRepository) -> some View {
        RepoDisclosureView(repo: repo, viewModel: viewModel) {
            worktreeContent(for: repo)
        } label: {
            repoLabel(repo)
                .contextMenu {
                    if let harnessName = ynhPersistence.repoDefaultHarness(for: repo.path) {
                        Button {
                            onLaunchHarness?(harnessName, repo.path, nil)
                        } label: {
                            Label(Strings.Sidebar.launchHarness(harnessName), systemImage: "play.fill")
                        }
                        Divider()
                    }

                    Button {
                        newWorktreeContext = NewWorktreeContext(repo: repo, initialBaseBranch: nil)
                    } label: {
                        Label(Strings.Sidebar.newWorktree, systemImage: "plus")
                    }

                    Divider()

                    Button {
                        showEditRepoFor = repo
                    } label: {
                        Label(Strings.Sidebar.editRepository, systemImage: "pencil")
                    }

                    addToWorkspaceMenu(for: repo)

                    Button {
                        Task { await analyseAndPrune(repo: repo) }
                    } label: {
                        Label(Strings.Sidebar.pruneWorktrees, systemImage: "scissors")
                    }
                    .disabled(isPruneAnalysing)

                    if !harnessRepository.harnesses.isEmpty {
                        Divider()
                        repoDefaultHarnessContextItems(for: repo)
                    }

                    if stackService.isAvailable && !stackService.isStacked(repo: repo.path) {
                        Divider()
                        Button {
                            Task { await viewModel.enableStacking(for: repo) }
                        } label: {
                            Label(Strings.Stacks.enableStacking, systemImage: "square.stack.3d.up")
                        }
                        .help(Strings.Stacks.enableStackingHelp)
                    }

                    Divider()

                    Button(role: .destructive) {
                        viewModel.removeRepository(repo)
                    } label: {
                        Label(Strings.Sidebar.removeRepository, systemImage: "trash")
                    }
                }
        }
    }

    // MARK: - Worktree Content

    @ViewBuilder
    private func worktreeContent(for repo: ObservableRepository) -> some View {
        switch sidebarMode {
        case .local:
            localWorktreeContent(for: repo)
        case .remote:
            remoteWorktreeContent(for: repo)
        }
    }

    @ViewBuilder
    private func localWorktreeContent(for repo: ObservableRepository) -> some View {
        if viewModel.loadingRepos.contains(repo.id) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        } else if let trees = viewModel.worktrees[repo.id] {
            // Collapsible like the Stacks and Local Branches sections — users working
            // exclusively in stacks can hide the worktree list entirely. Wraps the
            // rows AND the "+ New Worktree" affordance; state persists per repo.
            //
            // When `hideStackedWorktrees` is on, worktrees whose branch belongs to a
            // tracked stack are dropped here — they're already listed under STACKS, so
            // this avoids showing the same worktree twice. `allWorktrees` on each row
            // stays the UNFILTERED `trees` so cross-worktree lookups (e.g. "checked out
            // elsewhere") keep seeing every worktree, not just the visible ones.
            let displayedTrees =
                settings.hideStackedWorktrees
                ? trees.filter { viewModel.stackRootName(for: $0, repo: repo) == nil }
                : trees
            let showChevronSlot = repoHasStackedWorktrees(displayedTrees, repo: repo)
            WorktreeSectionDisclosureView(repo: repo, viewModel: viewModel) {
                if trees.isEmpty {
                    Text(Strings.Sidebar.worktreesEmpty)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                } else {
                    ForEach(displayedTrees) { worktree in
                        worktreeRow(
                            worktree, repo: repo, allWorktrees: trees,
                            showChevronSlot: showChevronSlot)
                    }
                }

                Button {
                    newWorktreeContext = NewWorktreeContext(repo: repo, initialBaseBranch: nil)
                } label: {
                    // Manual icon + text, NOT `Label` — sidebar-styled Lists auto-align
                    // `Label` icons into a shared column that ignores surrounding
                    // padding, which silently defeated leading-padding attempts here.
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .imageScale(.small)
                        Text(Strings.Sidebar.newWorktree)
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            // Tracked stacks inventory — hidden when no provider, repo not initialized,
            // or the graph has no stacks. Branches shown here are excluded from the
            // Local Branches section below.
            stacksSection(for: repo)

            // Local branches without worktrees (excluding stack members)
            let branches = viewModel.displayedLocalBranches(for: repo)
            if !branches.isEmpty {
                BranchSectionDisclosureView(
                    repo: repo,
                    viewModel: viewModel,
                    onPruneBranches: { analyseAndPruneBranches(repo: repo) },
                    content: {
                        ForEach(branches, id: \.self) { branch in
                            branchRow(branch, repo: repo)
                        }
                    }
                )
                // No trailing modifiers: the section emits sibling List rows.
            }
        } else {
            Text(Strings.Sidebar.worktreesPlaceholder)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
    }

}

// MARK: - Worktree Row

extension WorktreeSidebarView {
    @ViewBuilder
    func worktreeRowContent(
        _ worktree: GitWorktree, repo: ObservableRepository, allWorktrees: [GitWorktree]
    ) -> some View {
        let isActive = isActiveTerminalInWorktree(worktree, allWorktrees: allWorktrees)
        HStack(spacing: 6) {
            WorktreeLeftIcon(
                worktree: worktree,
                allWorktrees: allWorktrees,
                boardVM: boardVM,
                isDeleting: viewModel.deletingWorktreeIDs.contains(worktree.id),
                isUpdating: viewModel.updatingWorktreeIDs.contains(worktree.id),
                stackRootName: viewModel.stackRootName(for: worktree, repo: repo)
            )

            VStack(alignment: .leading, spacing: 1) {
                Button {
                    primaryAction(worktree: worktree, repo: repo)
                } label: {
                    HStack(spacing: 4) {
                        Text(worktree.branch ?? Strings.Sidebar.detachedHead)
                            .font(.system(.subheadline, weight: isActive ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        if worktree.isDirty {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(worktree.branch ?? "")
                Button {
                    openRemoteCommit(worktree: worktree, repo: repo)
                } label: {
                    Text(worktree.commitHash)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fontDesign(.monospaced)
                }
                .buttonStyle(.plain)
                .help(Strings.Sidebar.openRemoteCommit)
            }

            Spacer()

            // PR link badge: shown when this worktree's head matches an open PR.
            // Tapping launches the Run with Focus sheet for that PR.
            if let prNumber = linkedPRNumber(for: worktree, repo: repo) {
                let pr = (prService.prsByRepo[repo.path] ?? []).first { $0.number == prNumber }
                Button {
                    runWithFocusContext = RunWithFocusContext(
                        worktree: worktree, repo: repo, prNumber: prNumber)
                } label: {
                    Text(Strings.RemotePRs.linkedPR(prNumber))
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .help(pr.map { "#\($0.number) \($0.title)" } ?? Strings.RemotePRs.linkedPR(prNumber))
            }

            harnessRowBadge(for: worktree, repo: repo)

            Button {
                // Resign sidebar first responder before creating the terminal so the
                // NSTableView does not win the focus race against focusTerminal()'s
                // 100 ms asyncAfter. Without this, the NSTableView re-renders its
                // badge count due to the new transientCard and reclaims focus.
                NSApp.keyWindow?.makeFirstResponder(nil)
                boardVM.newTerminal(
                    at: worktree.path, branch: worktree.branch, repoName: orgRepoName(repoPath: repo.path))
            } label: {
                Image(systemName: "terminal")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(Strings.Sidebar.newTerminal)
        }
    }

}

// MARK: - Context Menus

extension WorktreeSidebarView {
    @ViewBuilder
    fileprivate func branchRow(_ branch: String, repo: ObservableRepository) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .imageScale(.small)
                .foregroundColor(.secondary)
                .frame(width: 26)

            Text(branch)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundColor(.primary)

            Spacer()

            if viewModel.fetchingBranchNames.contains(branch) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
            }
        }
        .padding(.leading, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                newWorktreeContext = NewWorktreeContext(repo: repo, initialBaseBranch: branch)
            } label: {
                Label(Strings.Sidebar.newWorktreeFromBranch, systemImage: "arrow.triangle.branch")
            }

            Button {
                convertWorktreeContext = ConvertWorktreeContext(repo: repo, branch: branch)
            } label: {
                Label(Strings.Sidebar.convertToWorktree, systemImage: "arrow.right.square")
            }

            Divider()

            Button {
                openBranchOnRemote(branch: branch, repo: repo)
            } label: {
                Label(Strings.Sidebar.openRemoteBranch, systemImage: "network")
            }

            Button {
                Task {
                    do {
                        try await viewModel.fetchBranchFromOrigin(repo: repo, branch: branch)
                    } catch {
                        viewModel.operationError = error.localizedDescription
                    }
                }
            } label: {
                Label(Strings.Sidebar.updateFromOrigin, systemImage: "arrow.down.circle")
            }

            if !viewModel.isProtectedBranch(branch, for: repo) {
                Divider()

                Button(role: .destructive) {
                    branchToDelete = (repo, branch)
                    isShowingDeleteBranchAlert = true
                } label: {
                    Label(Strings.Sidebar.deleteBranch, systemImage: "minus.circle")
                }

                Button(role: .destructive) {
                    branchToDestroy = (repo, branch)
                    isShowingDestroyBranchAlert = true
                } label: {
                    Label(Strings.Sidebar.destroyBranch, systemImage: "trash")
                }
            }
        }
    }

    /// The worktree conveniences shared between the worktree-row menu and the STACKS
    /// group-header menu (which delegates to the anchoring worktree): Run with Focus,
    /// terminals, reveal/copy/open-in. No worktree-lifecycle items (lock/remove/
    /// destroy/harness assignment) — those stay exclusive to the worktree row.
    @ViewBuilder
    func worktreeConvenienceMenuItems(
        _ worktree: GitWorktree, repo: ObservableRepository
    ) -> some View {
        worktreeFocusMenuItems(worktree, repo: repo)
        Divider()

        Button {
            boardVM.newTerminal(at: worktree.path, branch: worktree.branch, repoName: orgRepoName(repoPath: repo.path))
        } label: {
            Label(Strings.Sidebar.newTerminal, systemImage: "terminal")
        }
        Button {
            boardVM.addTerminal(
                workingDirectory: worktree.path, branch: worktree.branch, repoName: orgRepoName(repoPath: repo.path))
        } label: {
            Label(Strings.Sidebar.createTerminal, systemImage: "plus.rectangle")
        }

        Divider()

        worktreeRevealMenuItems(worktree)

        Divider()
    }

    /// Reveal/copy/open-in block: path-only actions, independent of which branch is
    /// checked out. Shared by the worktree-row menu and the STACKS group-header menu
    /// (where the checked-out branch may not match the action being performed).
    @ViewBuilder
    func worktreeRevealMenuItems(_ worktree: GitWorktree) -> some View {
        Button {
            revealInFinder(path: worktree.path)
        } label: {
            Label(Strings.Sidebar.revealInFinder, systemImage: "folder")
        }
        Button {
            openInTerminal(path: worktree.path)
        } label: {
            Label(Strings.Sidebar.openInTerminal, systemImage: "apple.terminal")
        }
        Button {
            PathActions.copyPathname(worktree.path)
        } label: {
            Label(Strings.Sidebar.copyPathname, systemImage: "doc.on.clipboard")
        }
        if !editorRegistry.available.isEmpty {
            Menu(Strings.Sidebar.openIn) {
                ForEach(editorRegistry.available) { editor in
                    Button(editor.displayName) { openIn(editor: editor, worktree: worktree) }
                }
            }
        }
    }

    @ViewBuilder
    func worktreeContextMenu(_ worktree: GitWorktree, repo: ObservableRepository) -> some View {
        let effectiveHarness =
            ynhPersistence.harness(for: worktree.path) ?? ynhPersistence.repoDefaultHarness(for: repo.path)

        // Group 0: Harness actions
        if let harnessName = effectiveHarness {
            Button {
                onLaunchHarness?(harnessName, worktree.path, worktree.branch)
            } label: {
                Label(Strings.Sidebar.launchHarness(harnessName), systemImage: "play.fill")
            }
        }
        // Groups 0b–2 are shared with the stack group-header menu (delegated to the
        // anchoring worktree) — one implementation, two menus.
        worktreeConvenienceMenuItems(worktree, repo: repo)

        // Group 3: Remote links
        if worktree.branch != nil {
            Button {
                openRemoteBranch(worktree: worktree, repo: repo)
            } label: {
                Label(Strings.Sidebar.openRemoteBranch, systemImage: "network")
            }
        }
        Button {
            openRemoteCommit(worktree: worktree, repo: repo)
        } label: {
            Label(Strings.Sidebar.openRemoteCommit, systemImage: "chevron.left.forwardslash.chevron.right")
        }
        if worktree.branch != nil {
            let linkedPR = linkedPRNumber(for: worktree, repo: repo).flatMap { prNum in
                (prService.prsByRepo[repo.path] ?? []).first(where: { $0.number == prNum })
            }
            let isForcePushed =
                linkedPR.map {
                    prService.forcePushedPRs[repo.path]?.contains($0.number) ?? false
                } ?? false

            Button {
                if let pr = linkedPR, case .ready(let ghPath, _) = ghProbe.status {
                    if isForcePushed || worktree.isDirty {
                        forceUpdatePRContext = ForceUpdatePRContext(
                            worktree: worktree,
                            repo: repo,
                            prNumber: pr.number,
                            ghPath: ghPath
                        )
                    } else {
                        Task {
                            do {
                                try await viewModel.updateFromOriginForPR(
                                    worktree: worktree,
                                    repo: repo,
                                    prNumber: pr.number,
                                    ghPath: ghPath
                                )
                            } catch {
                                viewModel.operationError = error.localizedDescription
                            }
                        }
                    }
                } else {
                    Task {
                        do { try await viewModel.pullBranch(worktree: worktree, repo: repo) } catch {
                            viewModel.operationError = error.localizedDescription
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if isForcePushed {
                        Text(Strings.RemotePRs.forcePushIndicator)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    Label(Strings.Sidebar.updateFromOrigin, systemImage: "arrow.down.circle")
                }
            }
        }

        // Stack actions (only when a provider is available and the repo is stacked)
        stackContextMenuItems(worktree, repo: repo)

        // Group 4: Main-worktree actions
        if worktree.isMainWorktree {
            Divider()
            Button {
                newWorktreeContext = NewWorktreeContext(repo: repo, initialBaseBranch: worktree.branch)
            } label: {
                Label(Strings.Sidebar.newWorktree, systemImage: "plus")
            }
            if !harnessRepository.harnesses.isEmpty {
                Divider()
                harnessContextItems(forPath: worktree.path)
            }
        }

        // Groups 5–6: Linked-worktree-only actions
        if !worktree.isMainWorktree {
            linkedWorktreeContextItems(worktree, repo: repo)
        }
    }

    @ViewBuilder
    private func linkedWorktreeContextItems(_ worktree: GitWorktree, repo: ObservableRepository) -> some View {
        Divider()

        if worktree.isLocked {
            Button {
                Task {
                    do { try await viewModel.unlockWorktree(repo: repo, worktree: worktree) } catch {
                        viewModel.operationError = error.localizedDescription
                    }
                }
            } label: {
                Label(Strings.Sidebar.unlockWorktree, systemImage: "lock.open")
            }
        } else {
            Button {
                Task {
                    do { try await viewModel.lockWorktree(repo: repo, worktree: worktree) } catch {
                        viewModel.operationError = error.localizedDescription
                    }
                }
            } label: {
                Label(Strings.Sidebar.lockWorktree, systemImage: "lock")
            }
        }

        if !harnessRepository.harnesses.isEmpty {
            Divider()
            harnessContextItems(forPath: worktree.path)
        }

        // PR-linked actions (appended only when this worktree is linked to a PR).
        // "Run with Focus…" itself lives in the top-level menu group for all worktrees.
        if let prNumber = linkedPRNumber(for: worktree, repo: repo) {
            Divider()

            Button {
                openPROnRemote(prNumber: prNumber, repo: repo)
            } label: {
                Label(Strings.RemotePRs.openPROnRemote, systemImage: "network")
            }

            Button {
                sidebarMode = .remote
            } label: {
                Label(Strings.RemotePRs.showInRemote, systemImage: "arrow.turn.up.right")
            }
        }

        Divider()

        Button(role: .destructive) {
            pendingRemoval = (repo, worktree)
            isShowingRemoveAlert = true
        } label: {
            Label(Strings.Sidebar.removeWorktree, systemImage: "minus.circle")
        }
        Button(role: .destructive) {
            pendingForceDelete = (repo, worktree)
            isShowingDeleteAlert = true
        } label: {
            Label(Strings.Sidebar.deleteWorktree, systemImage: "trash")
        }
    }
}

// MARK: - Repository Actions

extension WorktreeSidebarView {
    fileprivate func analyseAndPrune(repo: ObservableRepository) async {
        isPruneAnalysing = true
        defer { isPruneAnalysing = false }
        do {
            let stale = try await viewModel.pruneWorktreesDryRun(repo: repo)
            if stale.isEmpty {
                isShowingPruneNothingAlert = true
            } else {
                pruneStaleEntries = stale
                pruneSheetFor = repo
            }
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    fileprivate func analyseAndPruneBranches(repo: ObservableRepository) {
        pruneBranchesSheetFor = repo
    }

    /// Consume a menu-triggered request routed to the Repositories tab. Called
    /// from `onAppear` (after a menu switches to this tab) and from `onChange`
    /// (when the tab is already frontmost).
    fileprivate func consumeMenuRequest() {
        if menuCoordinator.consume(.addRepository) { showAddRepo = true }
        if menuCoordinator.consume(.pruneAllWorktrees) {
            guard !isPruneAnalysing else { return }
            Task { await analyseAndPruneAll() }
        }
    }

    /// Dry-run a worktree prune across every repository — both git's orphaned-record
    /// prune and (when GitHub is available) closed-PR and "Run with Focus" review
    /// worktrees — then present one aggregated confirmation sheet. The all-repos
    /// counterpart to `analyseAndPrune(repo:)`.
    fileprivate func analyseAndPruneAll() async {
        isPruneAnalysing = true
        defer { isPruneAnalysing = false }
        var candidates: [RepoPruneCandidate] = []
        var hadError = false
        for repo in viewModel.repositories {
            var candidate: RepoPruneCandidate
            do {
                let stale = try await viewModel.pruneWorktreesDryRun(repo: repo)
                candidate = RepoPruneCandidate(repo: repo, staleEntries: stale)
            } catch {
                viewModel.operationError = error.localizedDescription
                hadError = true
                continue
            }
            if case .ready = ghProbe.status {
                let (closed, focus) = await viewModel.collectPRPruneCandidates(
                    repo: repo, prService: prService)
                candidate.closedPRCandidates = closed
                candidate.focusCandidates = focus
            }
            if !candidate.isEmpty {
                candidates.append(candidate)
            }
        }
        // Only claim "nothing to prune" when the empty result wasn't caused by
        // every dry-run failing — otherwise operationError surfaces the cause.
        if !candidates.isEmpty {
            pruneAllContext = PruneAllContext(candidates: candidates)
        } else if !hadError {
            isShowingPruneNothingAlert = true
        }
    }
}

// MARK: - Remote Navigation

extension WorktreeSidebarView {
    func openBranchOnRemote(branch: String, repo: ObservableRepository) {
        Task {
            guard let raw = try? await GitService.shared.remoteURL(repoPath: repo.path),
                let base = remoteWebURL(from: raw)
            else { return }
            let urlStr = base.absoluteString + "/tree/" + branch
            if let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
        }
    }

    fileprivate func openRemoteBranch(worktree: GitWorktree, repo: ObservableRepository) {
        guard let branch = worktree.branch else { return }
        Task {
            guard let raw = try? await GitService.shared.remoteURL(repoPath: repo.path),
                let base = remoteWebURL(from: raw)
            else { return }
            // Branch names with slashes are valid URL path segments on GitHub/GitLab
            let urlStr = base.absoluteString + "/tree/" + branch
            if let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
        }
    }

    func openRemoteCommit(worktree: GitWorktree, repo: ObservableRepository) {
        Task {
            guard let raw = try? await GitService.shared.remoteURL(repoPath: repo.path),
                let base = remoteWebURL(from: raw)
            else { return }
            let urlStr = base.absoluteString + "/commit/" + worktree.commitHash
            if let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
        }
    }

    func remoteWebURL(from remoteURL: String) -> URL? {
        var urlString = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // SSH: git@github.com:user/repo.git → https://github.com/user/repo
        if urlString.hasPrefix("git@") {
            urlString = String(urlString.dropFirst(4))  // strip "git@"
            if let colon = urlString.firstIndex(of: ":") {
                let host = String(urlString[urlString.startIndex..<colon])
                let path = String(urlString[urlString.index(after: colon)...])
                urlString = "https://\(host)/\(path)"
            }
        }
        if urlString.hasSuffix(".git") { urlString = String(urlString.dropLast(4)) }
        if urlString.hasSuffix("/") { urlString = String(urlString.dropLast()) }
        return URL(string: urlString)
    }

    fileprivate func primaryAction(worktree: GitWorktree, repo: ObservableRepository) {
        let harnessName =
            ynhPersistence.harness(for: worktree.path)
            ?? ynhPersistence.repoDefaultHarness(for: repo.path)
        if case .ready = ynhDetector.status, let name = harnessName {
            onAutoLaunchHarness?(name, worktree.path, worktree.branch)
        } else {
            NSApp.keyWindow?.makeFirstResponder(nil)
            boardVM.newTerminal(at: worktree.path, branch: worktree.branch, repoName: orgRepoName(repoPath: repo.path))
        }
    }

    func orgRepoName(repoPath: String) -> String {
        let url = URL(fileURLWithPath: repoPath)
        let repo = url.lastPathComponent
        let org = url.deletingLastPathComponent().lastPathComponent
        return "\(org)/\(repo)"
    }

    func openInTerminal(path: String) {
        PathActions.openInTerminal(path: path)
    }

    func revealInFinder(path: String) {
        PathActions.revealInFinder(path: path)
    }

    fileprivate func openIn(editor: ExternalEditor, worktree: GitWorktree) {
        PathActions.openIn(editor: editor, path: worktree.path)
    }
}
