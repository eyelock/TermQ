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
    @Published var availableBranches: [UUID: [String]] = [:]
    @Published private(set) var loadingRepos: Set<UUID> = []
    @Published var isLoading: Bool = false
    @Published var operationError: String?
    @Published var expandedRepoIDs: Set<UUID> = []
    @Published var expandedBranchSectionIDs: Set<UUID> = []

    private let persistence = RepoPersistence()
    private static let expandedReposKey = "sidebar.expandedRepos"
    private static let expandedBranchSectionsKey = "sidebar.expandedBranchSections"
    private var monitors: [UUID: GitRepositoryMonitor] = [:]
    private var dirtyPollTimer: Timer?

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.expandedReposKey) ?? []
        expandedRepoIDs = Set(saved.compactMap { UUID(uuidString: $0) })
        let savedBranch = UserDefaults.standard.stringArray(forKey: Self.expandedBranchSectionsKey) ?? []
        expandedBranchSectionIDs = Set(savedBranch.compactMap { UUID(uuidString: $0) })
        loadRepositories()
        refreshExpandedWorktrees()
        startMonitorsForAllRepos()
        startDirtyPolling()
        persistence.startFileMonitoring { [weak self] in
            Task { @MainActor in
                self?.reloadRepositories()
            }
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
                for repo in expanded {
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
                await self.refreshWorktrees(for: repo)
            }
        }
    }

    private func stopMonitor(for repoID: UUID) {
        monitors.removeValue(forKey: repoID)
    }

    private func refreshExpandedWorktrees() {
        let toRefresh = repositories.filter { expandedRepoIDs.contains($0.id) }
        guard !toRefresh.isEmpty else { return }
        Task {
            for repo in toRefresh {
                await refreshWorktrees(for: repo)
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

    // MARK: - Repository CRUD

    /// Validate the path is a git repo, infer a name, append to the list, and persist.
    func addRepository(
        path: String,
        name: String? = nil,
        worktreeBasePath: String? = nil,
        addToGitignore: Bool = false
    ) async throws {
        guard try await GitService.shared.isGitRepo(path: path) else {
            throw WorktreeSidebarError.notAGitRepository(path: path)
        }

        let displayName: String
        if let provided = name, !provided.isEmpty {
            displayName = provided
        } else {
            displayName = await GitService.shared.inferRepoName(repoPath: path)
        }

        let repo = ObservableRepository(name: displayName, path: path, worktreeBasePath: worktreeBasePath)
        repositories.append(repo)
        setExpanded(repo.id, expanded: true)
        save()
        if addToGitignore, let base = worktreeBasePath, !base.isEmpty {
            ensureGitignored(repoPath: path, basePath: base)
        }
        startMonitor(for: repo)
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

    func removeRepository(_ repo: ObservableRepository) {
        stopMonitor(for: repo.id)
        repositories.removeAll { $0.id == repo.id }
        worktrees.removeValue(forKey: repo.id)
        save()
    }

    func updateRepository(_ repo: ObservableRepository, name: String, worktreeBasePath: String?) {
        repo.name = name
        repo.worktreeBasePath = worktreeBasePath
        save()
    }

    // MARK: - Worktree Queries

    /// Manual refresh triggered by the user — updates `origin/HEAD` before refreshing
    /// worktrees so that `defaultBranch` reflects the remote's current default.
    func refreshRepo(for repo: ObservableRepository) async {
        await GitService.shared.updateRemoteHead(repoPath: repo.path)
        await refreshWorktrees(for: repo)
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
            let trees = try await GitService.shared.listWorktrees(repoPath: repo.path)
            worktrees[repo.id] = trees
        } catch {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.ui.error("WorktreeSidebarViewModel: refreshWorktrees failed error=\(error)")
            } else {
                TermQLogger.ui.error("WorktreeSidebarViewModel: refreshWorktrees failed")
            }
            worktrees[repo.id] = worktrees[repo.id] ?? []
        }
        await refreshAvailableBranches(for: repo)
    }

    /// Refresh the list of local branches that do not already have a worktree checked out.
    ///
    /// Called automatically at the tail of every `refreshWorktrees` so the "Local Branches"
    /// section always reflects the current worktree state.
    func refreshAvailableBranches(for repo: ObservableRepository) async {
        do {
            let all = try await GitService.shared.listBranches(repoPath: repo.path)
            let occupied = Set(worktrees[repo.id]?.compactMap(\.branch) ?? [])
            availableBranches[repo.id] = all.filter { !occupied.contains($0) }
        } catch {
            availableBranches[repo.id] = availableBranches[repo.id] ?? []
        }
    }

    // MARK: - Worktree CRUD

    func createWorktree(
        repo: ObservableRepository,
        branchName: String,
        baseBranch: String?,
        path: String
    ) async throws {
        try await GitService.shared.addWorktree(
            repo: repo.toGitRepository(),
            branch: branchName,
            path: path,
            baseBranch: baseBranch
        )
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    func removeWorktree(repo: ObservableRepository, worktree: GitWorktree) async throws {
        guard !worktree.isMainWorktree else {
            throw WorktreeOperationError.removingMainWorktree
        }
        try await GitService.shared.removeWorktree(repo: repo.toGitRepository(), path: worktree.path)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    /// Check out an existing local branch as a new worktree.
    func checkoutBranchAsWorktree(repo: ObservableRepository, branch: String, path: String) async throws {
        try await GitService.shared.checkoutBranchAsWorktree(
            repo: repo.toGitRepository(),
            branch: branch,
            path: path
        )
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    func listBranches(for repo: ObservableRepository) async throws -> [String] {
        try await GitService.shared.listBranches(repoPath: repo.path)
    }

    /// Return the default branch for a repo via `origin/HEAD` symref.
    func defaultBranch(for repo: ObservableRepository) async -> String {
        await GitService.shared.defaultBranch(repoPath: repo.path)
    }

    func forceDeleteWorktree(repo: ObservableRepository, worktree: GitWorktree) async throws {
        guard !worktree.isMainWorktree else {
            throw WorktreeOperationError.removingMainWorktree
        }
        try await GitService.shared.forceDeleteWorktree(repoPath: repo.path, worktreePath: worktree.path)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    func lockWorktree(repo: ObservableRepository, worktree: GitWorktree) async throws {
        try await GitService.shared.lockWorktree(repoPath: repo.path, worktreePath: worktree.path)
        await refreshWorktrees(for: repo)
    }

    func unlockWorktree(repo: ObservableRepository, worktree: GitWorktree) async throws {
        try await GitService.shared.unlockWorktree(repoPath: repo.path, worktreePath: worktree.path)
        await refreshWorktrees(for: repo)
    }

    func pruneWorktreesDryRun(repo: ObservableRepository) async throws -> [String] {
        try await GitService.shared.pruneWorktreesDryRun(repoPath: repo.path)
    }

    func pruneWorktrees(repo: ObservableRepository) async throws {
        try await GitService.shared.pruneWorktrees(repoPath: repo.path)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    func mergedLocalBranches(repo: ObservableRepository) async throws -> [String] {
        try await GitService.shared.mergedLocalBranches(repoPath: repo.path)
    }

    func deleteBranches(repo: ObservableRepository, branches: [String]) async throws {
        for branch in branches {
            try await GitService.shared.deleteLocalBranch(repoPath: repo.path, branch: branch)
        }
        await refreshAvailableBranches(for: repo)
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

    // MARK: - Persistence

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
        refreshExpandedWorktrees()
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
            addedAt: addedAt
        )
    }
}
