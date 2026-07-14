import Foundation
import TermQCore
import TermQShared

// MARK: - Worktree Error

enum WorktreeOperationError: Error, LocalizedError, Sendable {
    case removingMainWorktree

    var errorDescription: String? {
        switch self {
        case .removingMainWorktree:
            return Strings.Sidebar.removeMainWorktreeError
        }
    }
}

// MARK: - Error

enum WorktreeSidebarError: Error, LocalizedError, Sendable {
    case notAGitRepository(path: String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepository(let path):
            return Strings.Sidebar.errorNotGitRepo(path)
        }
    }
}

// MARK: - ViewModel

/// Manages the sidebar's repository list and persistence.
///
/// Observable state for the worktree list and loading indicators lives here, not in
/// `GitService`. Follows the `BoardViewModel` pattern: `@MainActor` `ObservableObject`
/// with a `shared` singleton, `@Published` properties, and a dedicated persistence helper.
@MainActor
final class WorktreeSidebarViewModel: ObservableObject {
    static let shared = WorktreeSidebarViewModel()

    @Published var repositories: [ObservableRepository] = []
    @Published var worktrees: [UUID: [GitWorktree]] = [:]
    @Published var focusWorktrees: [UUID: [GitWorktree]] = [:]
    @Published var availableBranches: [UUID: [String]] = [:]
    /// Stack graphs keyed by repo id, mirroring `worktrees`. Populated only for repos
    /// where a `StackProvider` is available and stacking has been enabled.
    @Published var stacks: [UUID: StackGraph] = [:]
    @Published private(set) var loadingRepos: Set<UUID> = []
    @Published var isLoading: Bool = false
    @Published var operationError: String?
    @Published var expandedRepoIDs: Set<UUID> = []
    @Published var expandedBranchSectionIDs: Set<UUID> = []
    /// Repos whose Worktrees section is COLLAPSED. Inverted relative to the other
    /// expansion sets because the section defaults to expanded — an id absent from
    /// the set (including every repo the first time) renders expanded.
    @Published var collapsedWorktreeSectionIDs: Set<UUID> = []
    @Published private(set) var deletingWorktreeIDs: Set<String> = []
    @Published private(set) var updatingWorktreeIDs: Set<String> = []
    @Published private(set) var fetchingBranchNames: Set<String> = []

    let gitService: any GitServiceProtocol
    private let persistence: any RepoPersistenceProtocol
    // Internal (not private) so the stack mutations in
    // WorktreeSidebarViewModel+Stacks.swift can force a PR refresh after submit/sync.
    let prService: GitHubPRService
    private let gitConfig: GitConfigStore
    private let workspaceStore: WorkspaceStore
    let stackService: StackService
    private static let expandedReposKey = "sidebar.expandedRepos"
    private static let expandedBranchSectionsKey = "sidebar.expandedBranchSections"
    private static let collapsedWorktreeSectionsKey = "sidebar.collapsedWorktreeSections"
    var monitors: [UUID: GitRepositoryMonitor] = [:]
    private var dirtyPollTimer: Timer?
    /// Test seams for the guarded-switch checks. `nil` uses the production checks
    /// (`git status --porcelain` / board-card working directories).
    var worktreeDirtyCheckOverride: ((String) async -> Bool)?
    var worktreeInUseCheckOverride: ((String) -> Bool)?

    init(
        gitService: any GitServiceProtocol = GitService.shared,
        persistence: any RepoPersistenceProtocol = RepoPersistence(),
        prService: GitHubPRService = .shared,
        gitConfig: GitConfigStore = .shared,
        workspaceStore: WorkspaceStore = .shared,
        stackService: StackService = .shared
    ) {
        self.persistence = persistence
        self.gitService = gitService
        self.prService = prService
        self.gitConfig = gitConfig
        self.workspaceStore = workspaceStore
        self.stackService = stackService
        let saved = UserDefaults.standard.stringArray(forKey: Self.expandedReposKey) ?? []
        expandedRepoIDs = Set(saved.compactMap { UUID(uuidString: $0) })
        let savedBranch = UserDefaults.standard.stringArray(forKey: Self.expandedBranchSectionsKey) ?? []
        expandedBranchSectionIDs = Set(savedBranch.compactMap { UUID(uuidString: $0) })
        let savedCollapsed =
            UserDefaults.standard.stringArray(forKey: Self.collapsedWorktreeSectionsKey) ?? []
        collapsedWorktreeSectionIDs = Set(savedCollapsed.compactMap { UUID(uuidString: $0) })
        loadRepositories()
        refreshExpandedWorktrees()
        startMonitorsForAllRepos()
        startDirtyPolling()
        persistence.startFileMonitoring { [weak self] in
            Task { @MainActor in
                self?.reloadRepositories()
            }
        }
        Task { [weak self] in
            await self?.stackService.probe()
            await self?.refreshAllStacks()
        }
    }

    // MARK: - Git State Monitoring

    private func startMonitorsForAllRepos() {
        for repo in repositories {
            startMonitor(for: repo)
        }
    }

    /// Polls dirty state every 15 s for expanded repos.
    ///
    /// The file-system monitor covers branch switches and staging events (`.git/HEAD` /
    /// `.git/index`), but plain file edits don't touch any git metadata — only `git status`
    /// can detect them. This timer closes that gap without watching every source file.
    private func startDirtyPolling() {
        dirtyPollTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let expanded = self.repositories.filter { self.expandedRepoIDs.contains($0.id) }
                // Skip repos with a stack mutation in flight — concurrent `git status`
                // runs can break provider operations (known git-spice issue).
                for repo in expanded where !self.stackService.isMutating(repo: repo.path) {
                    await self.refreshWorktrees(for: repo)
                }
            }
        }
    }

    private func startMonitor(for repo: ObservableRepository) {
        let id = repo.id
        let path = repo.path
        monitors[id] = GitRepositoryMonitor(repoPath: path) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let repo = self.repositories.first(where: { $0.id == id }) else { return }
                // Provider mutations rewrite refs and would spam this monitor mid-flight;
                // the mutation path refreshes explicitly when it completes.
                guard !self.stackService.isMutating(repo: repo.path) else { return }
                await self.refreshWorktrees(for: repo)
            }
        }
    }

    private func stopMonitor(for repoID: UUID) {
        monitors.removeValue(forKey: repoID)
    }

    /// Refresh worktrees for every expanded repo. `fetch: true` (user-triggered refresh)
    /// also fetches from `origin`; `fetch: false` (startup) only re-lists local state so
    /// launching the app doesn't fire a network fetch per expanded repo.
    private func refreshExpandedWorktrees(fetch: Bool = false) {
        let toRefresh = repositories.filter { expandedRepoIDs.contains($0.id) }
        guard !toRefresh.isEmpty else { return }
        Task {
            for repo in toRefresh {
                if fetch {
                    await refreshRepo(for: repo)
                } else {
                    await refreshWorktrees(for: repo)
                }
            }
        }
    }

    func setExpanded(_ id: UUID, expanded: Bool) {
        if expanded {
            expandedRepoIDs.insert(id)
        } else {
            expandedRepoIDs.remove(id)
        }
        UserDefaults.standard.set(expandedRepoIDs.map { $0.uuidString }, forKey: Self.expandedReposKey)
    }

    func setBranchSectionExpanded(_ id: UUID, expanded: Bool) {
        if expanded {
            expandedBranchSectionIDs.insert(id)
        } else {
            expandedBranchSectionIDs.remove(id)
        }
        UserDefaults.standard.set(
            expandedBranchSectionIDs.map { $0.uuidString },
            forKey: Self.expandedBranchSectionsKey
        )
    }

    func setWorktreeSectionExpanded(_ id: UUID, expanded: Bool) {
        if expanded {
            collapsedWorktreeSectionIDs.remove(id)
        } else {
            collapsedWorktreeSectionIDs.insert(id)
        }
        UserDefaults.standard.set(
            collapsedWorktreeSectionIDs.map { $0.uuidString },
            forKey: Self.collapsedWorktreeSectionsKey
        )
    }

    func isWorktreeSectionExpanded(_ id: UUID) -> Bool {
        !collapsedWorktreeSectionIDs.contains(id)
    }

    // MARK: - Workspace Filtering

    /// Repositories visible under the active workspace selection.
    ///
    /// "All" (`activeWorkspaceId == nil`) shows every repo; an active workspace
    /// shows only its members, preserving the sidebar's global order. The
    /// decision logic is the pure `WorkspaceFilter` — this only maps the ids
    /// back to the observable rows.
    var displayedRepositories: [ObservableRepository] {
        let visible = Set(workspaceStore.visibleRepoIds(allRepoIds: repositories.map(\.id)))
        return repositories.filter { visible.contains($0.id) }
    }

    // MARK: - Repository CRUD

    /// Validate the path is a git repo, infer a name, append to the list, and persist.
    func addRepository(
        path: String,
        name: String? = nil,
        worktreeBasePath: String? = nil,
        addToGitignore: Bool = false
    ) async throws {
        guard try await gitService.isGitRepo(path: path) else {
            throw WorktreeSidebarError.notAGitRepository(path: path)
        }

        let displayName: String
        if let provided = name, !provided.isEmpty {
            displayName = provided
        } else {
            displayName = await gitService.inferRepoName(repoPath: path)
        }

        let repo = ObservableRepository(name: displayName, path: path, worktreeBasePath: worktreeBasePath)
        repositories.append(repo)
        setExpanded(repo.id, expanded: true)
        save()
        // File the new repo into the active workspace, if any. In "All" (no
        // active workspace) it stays unassigned and shows only under "All".
        if let activeId = workspaceStore.activeWorkspaceId {
            workspaceStore.add(repoId: repo.id, to: activeId)
        }
        if addToGitignore, let base = worktreeBasePath, !base.isEmpty {
            ensureGitignored(repoPath: path, basePath: base)
        }
        startMonitor(for: repo)
        await initializeSubmodulesIfEnabled(at: path)
        // Sync origin/HEAD up front so the repo's default branch reflects the remote's
        // current default rather than whatever it was at clone time. git never refreshes
        // this symref on fetch/pull, so we do it explicitly when the repo is added.
        await gitService.updateRemoteHead(repoPath: path)
        await refreshWorktrees(for: repo)
    }

    /// Adds `basePath` to the repo's `.gitignore` if it lives inside the repo and isn't
    /// already listed. This prevents worktree directories from appearing as untracked files
    /// in the main checkout.
    private func ensureGitignored(repoPath: String, basePath: String) {
        let repoURL = URL(fileURLWithPath: repoPath)
        let baseURL = URL(fileURLWithPath: basePath)
        let repoPrefix = repoURL.path + "/"

        // Only act when basePath is nested inside the repo.
        guard baseURL.path.hasPrefix(repoPrefix) else { return }
        let relative = String(baseURL.path.dropFirst(repoPrefix.count))
        guard !relative.isEmpty else { return }

        let gitignoreURL = repoURL.appendingPathComponent(".gitignore")
        let existing = (try? String(contentsOf: gitignoreURL, encoding: .utf8)) ?? ""

        // Accept both "dir" and "dir/" spellings as already-present.
        let trimmed = relative.hasSuffix("/") ? relative : relative + "/"
        let bare = String(trimmed.dropLast())
        let alreadyPresent = existing.components(separatedBy: "\n").contains {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line == bare || line == trimmed
        }
        guard !alreadyPresent else { return }

        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let newContent = existing + separator + trimmed + "\n"
        do {
            try newContent.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        } catch {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.ui.error("ensureGitignored: write failed error=\(error)")
            } else {
                TermQLogger.ui.error("ensureGitignored: write failed")
            }
            operationError = error.localizedDescription
        }
    }

    func moveRepository(from source: IndexSet, to destination: Int) {
        repositories.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func removeRepository(_ repo: ObservableRepository) {
        stopMonitor(for: repo.id)
        repositories.removeAll { $0.id == repo.id }
        worktrees.removeValue(forKey: repo.id)
        stacks.removeValue(forKey: repo.id)
        stackService.evict(repo: repo.path)
        workspaceStore.removeRepoFromAll(repoId: repo.id)
        save()
    }

    func updateRepository(
        _ repo: ObservableRepository,
        name: String,
        worktreeBasePath: String?,
        protectedBranches: [String]? = nil
    ) {
        repo.name = name
        repo.worktreeBasePath = worktreeBasePath
        repo.protectedBranches = protectedBranches
        save()
    }

    // MARK: - Worktree Queries

    /// Manual refresh triggered by the user — fetches from `origin`, updates `origin/HEAD`
    /// so `defaultBranch` reflects the remote's current default, then refreshes worktrees.
    /// Returns the provider-sync report (removed merged branches + orchestration
    /// skips), or `nil` when the plain-fetch path ran instead. Callers that can show
    /// a toast use the result; everyone else ignores it.
    @discardableResult
    func refreshRepo(for repo: ObservableRepository) async -> StackSyncReport? {
        // No fetches while a stack mutation is in flight — a concurrent `git fetch`
        // can break provider ref rewrites (known git-spice issue). The mutation path
        // refreshes when it completes.
        guard !stackService.isMutating(repo: repo.path) else { return nil }
        // Stacked repos refresh via provider sync: it pulls trunk, deletes merged
        // locals, and retargets/restacks upstack CRs — a plain fetch would leave the
        // stack stale after a downstack merge.
        if stackService.isAvailable, stackService.isStacked(repo: repo.path),
            let mainWorktree = worktrees[repo.id]?.first(where: { $0.isMainWorktree })
        {
            do {
                return try await syncStackRepo(for: repo, worktree: mainWorktree)
            } catch {
                if TermQLogger.fileLoggingEnabled {
                    TermQLogger.ui.warning("refreshRepo: stack sync failed, falling back: \(error)")
                } else {
                    TermQLogger.ui.warning("refreshRepo: stack sync failed, falling back")
                }
                // Fall through to the plain fetch path below.
            }
        }
        await gitService.fetchRemote(repoPath: repo.path)
        await gitService.updateRemoteHead(repoPath: repo.path)
        await refreshWorktrees(for: repo)
        return nil
    }

    func refreshWorktrees(for repo: ObservableRepository) async {
        // Only show the loading spinner on the initial fetch (no data yet).
        // Background refreshes (monitor callbacks, dirty-poll timer) must not toggle
        // loadingRepos — swapping ProgressView ↔ ForEach mid-render causes a reentrant
        // NSTableView delegate call and visible flicker.
        let isInitialLoad = worktrees[repo.id] == nil
        if isInitialLoad { loadingRepos.insert(repo.id) }
        defer { if isInitialLoad { loadingRepos.remove(repo.id) } }
        do {
            let trees = try await gitService.listWorktrees(repoPath: repo.path)
            var regular: [GitWorktree] = []
            var focus: [GitWorktree] = []
            for tree in trees {
                if URL(fileURLWithPath: tree.path).lastPathComponent.hasPrefix("termq-focus-") {
                    focus.append(tree)
                } else {
                    regular.append(tree)
                }
            }
            worktrees[repo.id] = regular.sorted {
                if $0.isMainWorktree { return true }
                if $1.isMainWorktree { return false }
                let lhs = $0.branch ?? ""
                let rhs = $1.branch ?? ""
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            focusWorktrees[repo.id] = focus
        } catch {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.ui.error("WorktreeSidebarViewModel: refreshWorktrees failed error=\(error)")
            } else {
                TermQLogger.ui.error("WorktreeSidebarViewModel: refreshWorktrees failed")
            }
            worktrees[repo.id] = worktrees[repo.id] ?? []
        }
        await refreshAvailableBranches(for: repo)
        await refreshStack(for: repo)
    }

    /// Refresh the list of local branches that do not already have a worktree checked out.
    ///
    /// Called automatically at the tail of every `refreshWorktrees` so the "Local Branches"
    /// section always reflects the current worktree state.
    func refreshAvailableBranches(for repo: ObservableRepository) async {
        do {
            let all = try await gitService.listBranches(repoPath: repo.path)
            let occupied = Set(worktrees[repo.id]?.compactMap(\.branch) ?? [])
            availableBranches[repo.id] =
                all
                .filter { !occupied.contains($0) }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } catch {
            availableBranches[repo.id] = availableBranches[repo.id] ?? []
        }
    }

    // MARK: - Worktree CRUD

    /// Run `git submodule update --init --recursive` at `path` when the user has
    /// the "Initialize Git Submodules" toggle on. Failures surface via
    /// `operationError` rather than throwing — the worktree/repo is already
    /// created, so the user can re-run the init manually after fixing creds.
    private func initializeSubmodulesIfEnabled(at path: String) async {
        guard gitConfig.initializeSubmodules else { return }
        do {
            try await gitService.initializeSubmodules(repoPath: path)
        } catch {
            operationError = Strings.Sidebar.submoduleInitFailed(error.localizedDescription)
        }
    }

    func createWorktree(
        repo: ObservableRepository,
        branchName: String,
        baseBranch: String?,
        path: String
    ) async throws {
        try await gitService.addWorktree(
            repo: repo.toGitRepository(),
            branch: branchName,
            path: path,
            baseBranch: baseBranch
        )
        await initializeSubmodulesIfEnabled(at: path)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    func checkoutBranchAsWorktree(repo: ObservableRepository, branch: String, path: String) async throws {
        try await gitService.checkoutBranchAsWorktree(
            repo: repo.toGitRepository(),
            branch: branch,
            path: path
        )
        await initializeSubmodulesIfEnabled(at: path)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    /// Convert an existing local branch into a worktree, optionally renaming it first.
    ///
    /// If `newBranch` differs from `originalBranch`, the branch is renamed via `git branch -m`
    /// before being checked out at `path`. Used by the "Convert to Worktree" sidebar action.
    func convertBranchToWorktree(
        repo: ObservableRepository,
        originalBranch: String,
        newBranch: String,
        path: String
    ) async throws {
        if newBranch != originalBranch {
            try await gitService.renameBranch(
                repoPath: repo.path,
                oldName: originalBranch,
                newName: newBranch
            )
        }
        try await gitService.checkoutBranchAsWorktree(
            repo: repo.toGitRepository(),
            branch: newBranch,
            path: path
        )
        await initializeSubmodulesIfEnabled(at: path)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    func removeWorktree(repo: ObservableRepository, worktree: GitWorktree) async throws {
        guard !worktree.isMainWorktree else {
            throw WorktreeOperationError.removingMainWorktree
        }
        try await gitService.removeWorktree(repo: repo.toGitRepository(), path: worktree.path)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    func listBranches(for repo: ObservableRepository) async throws -> [String] {
        try await gitService.listBranches(repoPath: repo.path)
    }

    func forceDeleteWorktree(repo: ObservableRepository, worktree: GitWorktree) async throws {
        guard !worktree.isMainWorktree else {
            throw WorktreeOperationError.removingMainWorktree
        }
        deletingWorktreeIDs.insert(worktree.id)
        defer { deletingWorktreeIDs.remove(worktree.id) }
        try await gitService.forceDeleteWorktree(repoPath: repo.path, worktreePath: worktree.path)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    func lockWorktree(repo: ObservableRepository, worktree: GitWorktree) async throws {
        try await gitService.lockWorktree(repoPath: repo.path, worktreePath: worktree.path)
        await refreshWorktrees(for: repo)
    }

    func unlockWorktree(repo: ObservableRepository, worktree: GitWorktree) async throws {
        try await gitService.unlockWorktree(repoPath: repo.path, worktreePath: worktree.path)
        await refreshWorktrees(for: repo)
    }

    func pruneWorktreesDryRun(repo: ObservableRepository) async throws -> [String] {
        try await gitService.pruneWorktreesDryRun(repoPath: repo.path)
    }

    func pruneWorktrees(repo: ObservableRepository) async throws {
        try await gitService.pruneWorktrees(repoPath: repo.path)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    func mergedLocalBranches(repo: ObservableRepository) async throws -> [String] {
        let branches = try await gitService.mergedLocalBranches(repoPath: repo.path)
        let protected = Set(effectiveProtectedBranches(for: repo))
        return branches.filter { !protected.contains($0) }
    }

    func isProtectedBranch(_ branch: String, for repo: ObservableRepository) -> Bool {
        effectiveProtectedBranches(for: repo).contains(branch)
    }

    private func effectiveProtectedBranches(for repo: ObservableRepository) -> [String] {
        if let override = repo.protectedBranches {
            return override
        }
        return GitConfigStore.shared.globalProtectedBranches.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func deleteBranches(repo: ObservableRepository, branches: [String]) async throws {
        for branch in branches {
            try await gitService.deleteLocalBranch(repoPath: repo.path, branch: branch)
        }
        await refreshAvailableBranches(for: repo)
    }

    func deleteBranch(repo: ObservableRepository, branch: String) async throws {
        try await gitService.deleteLocalBranch(repoPath: repo.path, branch: branch)
        await refreshAvailableBranches(for: repo)
    }

    func forceDeleteBranch(repo: ObservableRepository, branch: String) async throws {
        try await gitService.forceDeleteLocalBranch(repoPath: repo.path, branch: branch)
        await refreshAvailableBranches(for: repo)
    }

    func fetchBranchFromOrigin(repo: ObservableRepository, branch: String) async throws {
        fetchingBranchNames.insert(branch)
        defer { fetchingBranchNames.remove(branch) }
        try await gitService.fetchBranchFromOrigin(repoPath: repo.path, branch: branch)
        await refreshAvailableBranches(for: repo)
    }

    func pullBranch(worktree: GitWorktree, repo: ObservableRepository) async throws {
        updatingWorktreeIDs.insert(worktree.id)
        defer { updatingWorktreeIDs.remove(worktree.id) }
        try await gitService.pullBranch(worktreePath: worktree.path)
        // Pull may have advanced submodule pointers — re-init when enabled so
        // the worktree isn't left pointing at stale submodule commits.
        await initializeSubmodulesIfEnabled(at: worktree.path)
        await refreshWorktrees(for: repo)
    }

    /// Infer a worktree directory path based on the repo's base path convention.
    ///
    /// Slashes in `branchName` are preserved so `fix/my-issue` creates
    /// a `fix/my-issue` subdirectory under the base, matching git convention.
    func inferWorktreePath(for repo: ObservableRepository, branchName: String) -> String {
        guard !branchName.isEmpty else { return "" }
        let base =
            repo.worktreeBasePath.flatMap { $0.isEmpty ? nil : $0 }
            ?? (repo.path + "/.worktrees")
        return URL(fileURLWithPath: base).appendingPathComponent(branchName).path
    }
}

// MARK: - PR Operations

extension WorktreeSidebarViewModel {
    /// Check whether a branch name (as `gh pr checkout` would create it) is already
    /// occupied by an existing worktree. Returns the worktree path if it exists.
    func existingWorktreePath(for branchName: String, repoID: UUID) -> String? {
        worktrees[repoID]?.first(where: { $0.branch == branchName })?.path
    }

    /// Three-step PR checkout:
    /// 1. `git worktree add --detach <path>`
    /// 2. `gh pr checkout <n>` from inside the worktree
    ///
    /// Returns the path of the created worktree.
    func checkoutPR(
        _ pr: GitHubPR,
        repo: ObservableRepository,
        ghPath: String
    ) async throws -> String {
        let worktreePath = inferPRWorktreePath(for: repo, prNumber: pr.number)
        try await gitService.addDetachedWorktree(repoPath: repo.path, path: worktreePath)
        let result = try await CommandRunner.run(
            executable: ghPath,
            arguments: ["pr", "checkout", "\(pr.number)"],
            currentDirectory: worktreePath
        )
        guard result.didSucceed else {
            // Clean up the detached worktree if gh checkout failed.
            try? await gitService.removeWorktree(
                repo: repo.toGitRepository(), path: worktreePath)
            throw GitHubPRError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
        return worktreePath
    }

    /// Update a PR-linked worktree from the PR head, using `gh pr checkout --force`.
    /// Callers must confirm before calling this when the worktree is dirty or ahead.
    func updateFromOriginForPR(
        worktree: GitWorktree,
        repo: ObservableRepository,
        prNumber: Int,
        ghPath: String
    ) async throws {
        updatingWorktreeIDs.insert(worktree.id)
        defer { updatingWorktreeIDs.remove(worktree.id) }
        let result = try await CommandRunner.run(
            executable: ghPath,
            arguments: ["pr", "checkout", "--force", "\(prNumber)"],
            currentDirectory: worktree.path
        )
        guard result.didSucceed else {
            throw GitHubPRError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        prService.clearForcePush(repoPath: repo.path, prNumber: prNumber)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    /// Analyse closed/merged PRs that are tracked locally for potential pruning.
    /// Returns a list of prunable candidates with their dirty/ahead state.
    func pruneClosedPRsDryRun(
        repo: ObservableRepository,
        closedPRNumbers: Set<Int>,
        prService: GitHubPRService
    ) async -> [PRPruneCandidate] {
        let wts = worktrees[repo.id] ?? []
        let openPRs = prService.prsByRepo[repo.path] ?? []
        let openNumbers = Set(openPRs.map(\.number))
        let matches = GitHubPRService.matchPRsToWorktrees(
            prs: openPRs, worktrees: wts, stackGraph: stacks[repo.id])

        // Find PR rows tracked locally but no longer open.
        // "Tracked locally" = they appear in the service's previousHeadOids (fetched before).
        var candidates: [PRPruneCandidate] = []

        for prNumber in closedPRNumbers {
            guard !openNumbers.contains(prNumber) else { continue }
            let worktreePath = matches[prNumber]
            var isDirty = false
            var aheadCount = 0
            if let path = worktreePath {
                isDirty = await GitServiceShared.isWorktreeDirty(worktreePath: path)
                aheadCount = await gitService.aheadCount(worktreePath: path)
            }
            candidates.append(
                PRPruneCandidate(
                    prNumber: prNumber,
                    worktreePath: worktreePath,
                    isDirty: isDirty,
                    aheadCount: aheadCount
                ))
        }
        return candidates
    }

    /// Execute pruning: remove clean PR rows and their worktrees.
    /// Dirty/ahead worktrees are silently skipped.
    func pruneClosedPRs(
        repo: ObservableRepository,
        candidates: [PRPruneCandidate]
    ) async {
        for candidate in candidates where !candidate.isDirty && candidate.aheadCount == 0 {
            if let path = candidate.worktreePath {
                try? await gitService.removeWorktree(repo: repo.toGitRepository(), path: path)
            }
        }
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    /// Force-refresh `repo`'s PRs, then collect everything in it that's prunable:
    /// worktrees checked out for PRs that are no longer open, and "Run with Focus"
    /// review worktrees (always prunable — they're ephemeral by design). Shared by
    /// the per-repo and all-repos prune flows so they agree on what counts as stale.
    func collectPRPruneCandidates(
        repo: ObservableRepository,
        prService: GitHubPRService
    ) async -> (closed: [PRPruneCandidate], focus: [FocusWorktreeCandidate]) {
        await prService.refresh(repoPath: repo.path, force: true)
        guard let openPRs = prService.prsByRepo[repo.path] else { return ([], []) }

        let openNumbers = Set(openPRs.map(\.number))
        let wts = worktrees[repo.id] ?? []
        var closedPRNumbers: Set<Int> = []
        for wt in wts {
            let last = URL(fileURLWithPath: wt.path).lastPathComponent
            if last.hasPrefix("pr-"), let prNum = Int(last.dropFirst(3)), !openNumbers.contains(prNum) {
                closedPRNumbers.insert(prNum)
            }
        }

        let closed =
            closedPRNumbers.isEmpty
            ? []
            : await pruneClosedPRsDryRun(repo: repo, closedPRNumbers: closedPRNumbers, prService: prService)
        let focus = (focusWorktrees[repo.id] ?? []).map { FocusWorktreeCandidate(path: $0.path) }
        return (closed, focus)
    }

    /// Derive a PR worktree path: `<worktreeBasePath>/pr-<n>`
    func inferPRWorktreePath(for repo: ObservableRepository, prNumber: Int) -> String {
        let base =
            repo.worktreeBasePath.flatMap { $0.isEmpty ? nil : $0 }
            ?? (repo.path + "/.worktrees")
        return URL(fileURLWithPath: base).appendingPathComponent("pr-\(prNumber)").path
    }

}

// MARK: - Persistence

extension WorktreeSidebarViewModel {
    func save() {
        let config = RepoConfig(repositories: repositories.map { $0.toGitRepository() })
        do {
            try persistence.save(config)
        } catch {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.ui.error("WorktreeSidebarViewModel: save failed error=\(error)")
            } else {
                TermQLogger.ui.error("WorktreeSidebarViewModel: save failed")
            }
        }
    }

    private func loadRepositories() {
        let config = persistence.loadConfig()
        repositories = config.repositories.map { ObservableRepository(from: $0) }
    }

    func refresh() {
        reloadRepositories()
        refreshExpandedWorktrees(fetch: true)
    }

    private func reloadRepositories() {
        let config = persistence.loadConfig()
        // Merge: update existing, append new, keep order
        var updated: [ObservableRepository] = []
        for gitRepo in config.repositories {
            if let existing = repositories.first(where: { $0.id == gitRepo.id }) {
                existing.name = gitRepo.name
                existing.path = gitRepo.path
                existing.worktreeBasePath = gitRepo.worktreeBasePath
                existing.protectedBranches = gitRepo.protectedBranches
                updated.append(existing)
            } else {
                updated.append(ObservableRepository(from: gitRepo))
            }
        }
        repositories = updated
    }
}

// MARK: - ObservableRepository ↔ GitRepository

extension ObservableRepository {
    /// Initialise from the Sendable `GitRepository` struct (TermQShared).
    convenience init(from gitRepo: GitRepository) {
        self.init(
            id: gitRepo.id,
            name: gitRepo.name,
            path: gitRepo.path,
            worktreeBasePath: gitRepo.worktreeBasePath,
            protectedBranches: gitRepo.protectedBranches,
            addedAt: gitRepo.addedAt
        )
    }

    /// Convert back to the Sendable `GitRepository` for persistence.
    func toGitRepository() -> GitRepository {
        GitRepository(
            id: id,
            name: name,
            path: path,
            worktreeBasePath: worktreeBasePath,
            protectedBranches: protectedBranches,
            addedAt: addedAt
        )
    }
}
