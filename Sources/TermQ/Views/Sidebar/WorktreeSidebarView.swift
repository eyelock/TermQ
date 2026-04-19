import AppKit
import SwiftUI
import TermQCore
import TermQShared

/// Collapsible sidebar showing registered repositories and their worktrees.
struct WorktreeSidebarView: View {
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    var onLaunchHarness: ((String, String, String?) -> Void)?
    var onAutoLaunchHarness: ((String, String, String?) -> Void)?
    @ObservedObject private var boardVM: BoardViewModel = .shared
    @ObservedObject private var harnessRepository: HarnessRepository = .shared
    @ObservedObject private var ynhPersistence: YNHPersistence = .shared
    @ObservedObject private var ynhDetector: YNHDetector = .shared
    @State private var showAddRepo = false
    @State private var showNewWorktreeFor: ObservableRepository?
    @State private var showEditRepoFor: ObservableRepository?
    @State private var checkoutBranchContext: CheckoutBranchContext?
    @State private var pendingRemoval: (ObservableRepository, GitWorktree)?
    @State private var isShowingRemoveAlert = false
    @State private var pendingForceDelete: (ObservableRepository, GitWorktree)?
    @State private var isShowingDeleteAlert = false
    @State private var pruneSheetFor: ObservableRepository?
    @State private var pruneStaleEntries: [String] = []
    @State private var isShowingPruneNothingAlert = false
    @State private var isPruneAnalysing = false
    @State private var pruneBranchesSheetFor: ObservableRepository?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if viewModel.repositories.isEmpty {
                emptyState
            } else {
                repoList
            }
        }
        .sheet(isPresented: $showAddRepo) {
            AddRepositorySheet(viewModel: viewModel)
        }
        .sheet(item: $showNewWorktreeFor) { repo in
            NewWorktreeSheet(repo: repo, viewModel: viewModel)
        }
        .sheet(item: $checkoutBranchContext) { ctx in
            CheckoutBranchSheet(
                repo: ctx.repo,
                preselectedBranch: ctx.preselectedBranch,
                viewModel: viewModel
            )
        }
        .sheet(item: $showEditRepoFor) { repo in
            EditRepositorySheet(repo: repo, viewModel: viewModel)
        }
        .sheet(item: $pruneSheetFor) { repo in
            PruneWorktreesSheet(repo: repo, staleEntries: pruneStaleEntries, viewModel: viewModel)
        }
        .sheet(item: $pruneBranchesSheetFor) { repo in
            PruneBranchesSheet(repo: repo, viewModel: viewModel)
        }
        .alert(Strings.Sidebar.pruneWorktreesNothingTitle, isPresented: $isShowingPruneNothingAlert) {
            Button(Strings.Common.ok) {}
        } message: {
            Text(Strings.Sidebar.pruneWorktreesNothingMessage)
        }
        .alert(Strings.Sidebar.removeWorktreeTitle, isPresented: $isShowingRemoveAlert) {
            Button(Strings.Sidebar.removeWorktreeConfirm, role: .destructive) {
                if let (repo, worktree) = pendingRemoval {
                    Task {
                        do {
                            try await viewModel.removeWorktree(repo: repo, worktree: worktree)
                        } catch {
                            viewModel.operationError = error.localizedDescription
                        }
                    }
                    pendingRemoval = nil
                }
            }
            Button(Strings.Sidebar.cancelButton, role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            if let (_, worktree) = pendingRemoval {
                Text(Strings.Sidebar.removeWorktreeMessage(worktree.path))
            }
        }
        .alert(Strings.Sidebar.deleteWorktreeTitle, isPresented: $isShowingDeleteAlert) {
            Button(Strings.Sidebar.deleteWorktreeConfirm, role: .destructive) {
                if let (repo, worktree) = pendingForceDelete {
                    Task {
                        do {
                            try await viewModel.forceDeleteWorktree(repo: repo, worktree: worktree)
                        } catch {
                            viewModel.operationError = error.localizedDescription
                        }
                    }
                    pendingForceDelete = nil
                }
            }
            Button(Strings.Sidebar.cancelButton, role: .cancel) {
                pendingForceDelete = nil
            }
        } message: {
            if let (_, worktree) = pendingForceDelete {
                Text(Strings.Sidebar.deleteWorktreeMessage(worktree.path))
            }
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
            if let msg = viewModel.operationError {
                Text(msg)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(Strings.Sidebar.title)
                .font(.headline)
                .foregroundColor(.primary)

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
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help(Strings.Sidebar.refreshWorktrees)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(Strings.Sidebar.emptyMessage)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Repository List

    private var repoList: some View {
        List(viewModel.repositories) { repo in
            repoRow(repo)
        }
        .listStyle(.sidebar)
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
                        showNewWorktreeFor = repo
                    } label: {
                        Label(Strings.Sidebar.newWorktree, systemImage: "plus")
                    }

                    Button {
                        checkoutBranchContext = CheckoutBranchContext(repo: repo, preselectedBranch: nil)
                    } label: {
                        Label(Strings.Sidebar.newWorktreeFromBranch, systemImage: "arrow.triangle.branch")
                    }

                    Divider()

                    Button {
                        showEditRepoFor = repo
                    } label: {
                        Label(Strings.Sidebar.editRepository, systemImage: "pencil")
                    }

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

                    Divider()

                    Button(role: .destructive) {
                        viewModel.removeRepository(repo)
                    } label: {
                        Label(Strings.Sidebar.removeRepository, systemImage: "trash")
                    }
                }
        }
    }

    @ViewBuilder
    private func repoLabel(_ repo: ObservableRepository) -> some View {
        HStack {
            Label(repo.name, systemImage: "shippingbox")
                .lineLimit(1)

            Spacer()

            if let harnessName = ynhPersistence.repoDefaultHarness(for: repo.path) {
                Button {
                    harnessRepository.selectedHarnessName = harnessName
                } label: {
                    Image(systemName: "puzzlepiece.extension")
                        .imageScale(.small)
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help(Strings.Sidebar.linkedHarness(harnessName))
            }

            Button {
                Task { await viewModel.refreshRepo(for: repo) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(Strings.Sidebar.refreshWorktrees)
            .opacity(viewModel.expandedRepoIDs.contains(repo.id) ? 1 : 0)
        }
    }

    // MARK: - Worktree Content

    @ViewBuilder
    private func worktreeContent(for repo: ObservableRepository) -> some View {
        if viewModel.loadingRepos.contains(repo.id) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        } else if let trees = viewModel.worktrees[repo.id] {
            if trees.isEmpty {
                Text(Strings.Sidebar.worktreesEmpty)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            } else {
                ForEach(trees) { worktree in
                    worktreeRow(worktree, repo: repo, allWorktrees: trees)
                }
            }

            Button {
                showNewWorktreeFor = repo
            } label: {
                Label(Strings.Sidebar.newWorktree, systemImage: "plus")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .padding(.top, 2)

            // Local branches without worktrees
            if let branches = viewModel.availableBranches[repo.id], !branches.isEmpty {
                BranchSectionDisclosureView(
                    repo: repo,
                    viewModel: viewModel,
                    onPruneBranches: { analyseAndPruneBranches(repo: repo) }
                ) {
                    ForEach(branches, id: \.self) { branch in
                        branchRow(branch, repo: repo)
                    }
                }
                .padding(.top, 4)
            }
        } else {
            Text(Strings.Sidebar.worktreesPlaceholder)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
    }

    @ViewBuilder
    private func worktreeRow(
        _ worktree: GitWorktree, repo: ObservableRepository, allWorktrees: [GitWorktree]
    ) -> some View {
        HStack(spacing: 6) {
            WorktreeLeftIcon(worktree: worktree, allWorktrees: allWorktrees, boardVM: boardVM)

            VStack(alignment: .leading, spacing: 1) {
                Button {
                    primaryAction(worktree: worktree, repo: repo)
                } label: {
                    HStack(spacing: 4) {
                        Text(worktree.branch ?? Strings.Sidebar.detachedHead)
                            .font(.subheadline)
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
        .padding(.leading, 4)
        .contextMenu { worktreeContextMenu(worktree, repo: repo) }
    }

    @ViewBuilder
    private func branchRow(_ branch: String, repo: ObservableRepository) -> some View {
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
        }
        .padding(.leading, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                checkoutBranchContext = CheckoutBranchContext(repo: repo, preselectedBranch: branch)
            } label: {
                Label(Strings.Sidebar.newWorktree, systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func worktreeContextMenu(_ worktree: GitWorktree, repo: ObservableRepository) -> some View {
        let effectiveHarness =
            ynhPersistence.harness(for: worktree.path) ?? ynhPersistence.repoDefaultHarness(for: repo.path)

        // Launch harness is the primary action when one is configured — show it first.
        if let harnessName = effectiveHarness {
            Button {
                onLaunchHarness?(harnessName, worktree.path, worktree.branch)
            } label: {
                Label(Strings.Sidebar.launchHarness(harnessName), systemImage: "play.fill")
            }
            Divider()
        }

        // Group 1: Terminal actions
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

        // Group 2: Reveal / copy
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
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worktree.path, forType: .string)
        } label: {
            Label(Strings.Sidebar.copyPathname, systemImage: "doc.on.clipboard")
        }

        Divider()

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

        // Group 4: Worktree actions (main worktree only)
        if worktree.isMainWorktree {
            Divider()

            Button {
                checkoutBranchContext = CheckoutBranchContext(repo: repo, preselectedBranch: nil)
            } label: {
                Label(Strings.Sidebar.newWorktreeFromBranch, systemImage: "arrow.triangle.branch")
            }

            if !harnessRepository.harnesses.isEmpty {
                Divider()
                harnessContextItems(forPath: worktree.path)
            }
        }

        // Group 5: Lock (linked worktrees only)
        if !worktree.isMainWorktree {
            Divider()

            if worktree.isLocked {
                Button {
                    Task {
                        do {
                            try await viewModel.unlockWorktree(repo: repo, worktree: worktree)
                        } catch {
                            viewModel.operationError = error.localizedDescription
                        }
                    }
                } label: {
                    Label(Strings.Sidebar.unlockWorktree, systemImage: "lock.open")
                }
            } else {
                Button {
                    Task {
                        do {
                            try await viewModel.lockWorktree(repo: repo, worktree: worktree)
                        } catch {
                            viewModel.operationError = error.localizedDescription
                        }
                    }
                } label: {
                    Label(Strings.Sidebar.lockWorktree, systemImage: "lock")
                }
            }

            // Group 5.5: Harness linkage (only when harnesses are available)
            if !harnessRepository.harnesses.isEmpty {
                Divider()
                harnessContextItems(forPath: worktree.path)
            }

            Divider()

            // Group 6: Destructive (linked worktrees only)
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

    private func analyseAndPrune(repo: ObservableRepository) async {
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

    private func analyseAndPruneBranches(repo: ObservableRepository) {
        pruneBranchesSheetFor = repo
    }

}

// MARK: - Remote Navigation

extension WorktreeSidebarView {
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

    fileprivate func openRemoteCommit(worktree: GitWorktree, repo: ObservableRepository) {
        Task {
            guard let raw = try? await GitService.shared.remoteURL(repoPath: repo.path),
                let base = remoteWebURL(from: raw)
            else { return }
            let urlStr = base.absoluteString + "/commit/" + worktree.commitHash
            if let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
        }
    }

    fileprivate func remoteWebURL(from remoteURL: String) -> URL? {
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

    fileprivate func orgRepoName(repoPath: String) -> String {
        let url = URL(fileURLWithPath: repoPath)
        let repo = url.lastPathComponent
        let org = url.deletingLastPathComponent().lastPathComponent
        return "\(org)/\(repo)"
    }

    fileprivate func openInTerminal(path: String) {
        guard !path.contains("\n"), !path.contains("\r") else {
            TermQLogger.ui.error("openInTerminal: path contains newline, aborting")
            return
        }
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
            tell application "Terminal"
                activate
                do script "cd '\(escaped)'"
            end tell
            """
        // Task.detached: NSAppleScript.executeAndReturnError is synchronous and blocks the calling
        // thread. Detaching keeps it off the main actor without holding a cooperative thread.
        Task.detached {
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
                    if TermQLogger.fileLoggingEnabled {
                        TermQLogger.ui.error("openInTerminal AppleScript error=\(error)")
                    } else {
                        TermQLogger.ui.error("openInTerminal AppleScript failed code=\(code)")
                    }
                }
            }
        }
    }

    fileprivate func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

// MARK: - Checkout Branch Context

/// Carries both the target repository and an optional pre-selected branch into
/// `CheckoutBranchSheet`. Using a wrapper struct avoids secondary `@State` variables
/// and lets `sheet(item:)` bind to a single optional.
private struct CheckoutBranchContext: Identifiable {
    let id = UUID()
    let repo: ObservableRepository
    let preselectedBranch: String?
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
private struct RepoDisclosureView<Content: View, Label: View>: View {
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
private struct BranchSectionDisclosureView<Content: View>: View {
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
private struct WorktreeLeftIcon: View {
    let worktree: GitWorktree
    let allWorktrees: [GitWorktree]
    @ObservedObject var boardVM: BoardViewModel
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
            // Left slot — status badge (optional)
            Group {
                if worktree.isMainWorktree {
                    Image(systemName: "house.fill")
                        .foregroundColor(.secondary)
                } else if worktree.isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.orange)
                } else {
                    Color.clear
                }
            }
            .imageScale(.small)
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

// MARK: - Harness Helpers

extension WorktreeSidebarView {
    /// Jigsaw badge for worktree rows.
    ///
    /// Orange = explicit override on this worktree; dim = inherited from repo default.
    /// The repo header separately shows a green badge when a default is configured.
    @ViewBuilder
    fileprivate func harnessRowBadge(for worktree: GitWorktree, repo: ObservableRepository) -> some View {
        if let harnessName = ynhPersistence.harness(for: worktree.path) {
            Button {
                harnessRepository.selectedHarnessName = harnessName
            } label: {
                Image(systemName: "puzzlepiece.extension")
                    .imageScale(.small)
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .help(harnessName)
        } else if let inherited = ynhPersistence.repoDefaultHarness(for: repo.path) {
            Button {
                harnessRepository.selectedHarnessName = inherited
            } label: {
                Image(systemName: "puzzlepiece.extension")
                    .imageScale(.small)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(inherited)
        }
    }

    @ViewBuilder
    fileprivate func harnessContextItems(forPath path: String) -> some View {
        let linked = ynhPersistence.harness(for: path)
        Menu {
            if linked != nil {
                Button(Strings.Sidebar.clearHarness) {
                    ynhPersistence.setHarness(nil, for: path)
                }
                Divider()
            }
            ForEach(harnessRepository.harnesses) { harness in
                Button(harness.name) {
                    ynhPersistence.setHarness(harness.name, for: path)
                }
            }
        } label: {
            if let linked {
                Label(Strings.Sidebar.linkedHarness(linked), systemImage: "puzzlepiece.extension")
            } else {
                Label(Strings.Sidebar.setHarness, systemImage: "puzzlepiece.extension")
            }
        }
    }

    /// Context items for setting the repository-level default harness.
    /// Reads/writes `repoHarness` — independent from worktree overrides.
    @ViewBuilder
    fileprivate func repoDefaultHarnessContextItems(for repo: ObservableRepository) -> some View {
        let linked = ynhPersistence.repoDefaultHarness(for: repo.path)
        Menu {
            if linked != nil {
                Button(Strings.Sidebar.clearHarness) {
                    ynhPersistence.setRepoDefaultHarness(nil, for: repo.path)
                }
                Divider()
            }
            ForEach(harnessRepository.harnesses) { harness in
                Button(harness.name) {
                    ynhPersistence.setRepoDefaultHarness(harness.name, for: repo.path)
                }
            }
        } label: {
            if let linked {
                Label(Strings.Sidebar.linkedHarness(linked), systemImage: "puzzlepiece.extension")
            } else {
                Label(Strings.Sidebar.setHarness, systemImage: "puzzlepiece.extension")
            }
        }
    }

}
