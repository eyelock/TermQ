import TermQShared
import XCTest

@testable import TermQ
@testable import TermQCore

// MARK: - Mocks

@MainActor
final class MockGitService: GitServiceProtocol {
    var isGitRepoResult: Bool = true
    var isGitRepoError: Error?
    var listWorktreesResult: [GitWorktree] = []
    var listWorktreesError: Error?
    var listBranchesResult: [String] = []
    var listBranchesError: Error?
    var forceDeleteWorktreeError: Error?
    var pruneWorktreesError: Error?
    var pullBranchError: Error?
    var fetchBranchError: Error?
    var pruneWorktreesDryRunResult: [String] = []
    var mergedLocalBranchesResult: [String] = []
    var inferRepoNameResult: String = "mock-repo"
    var defaultBranchResult: String = "main"

    private(set) var forceDeleteWorktreeCalled = false
    private(set) var pruneWorktreesCalled = false
    private(set) var isGitRepoCalled = false
    private(set) var addWorktreeCalled = false
    private(set) var initializeSubmodulesCalls: [String] = []
    var initializeSubmodulesError: Error?
    private(set) var removeWorktreeCalled = false
    private(set) var lockWorktreeCalled = false
    private(set) var unlockWorktreeCalled = false
    private(set) var deleteLocalBranchCalls: [String] = []
    private(set) var renameBranchCalls: [(String, String)] = []
    private(set) var updateRemoteHeadCalled = false
    private(set) var fetchRemoteCalled = false

    func isGitRepo(path: String) async throws -> Bool {
        isGitRepoCalled = true
        if let error = isGitRepoError { throw error }
        return isGitRepoResult
    }

    func listWorktrees(repoPath: String) async throws -> [GitWorktree] {
        if let error = listWorktreesError { throw error }
        return listWorktreesResult
    }

    func checkoutBranchAsWorktree(repo: GitRepository, branch: String, path: String) async throws {}

    func addWorktree(repo: GitRepository, branch: String, path: String, baseBranch: String?) async throws {
        addWorktreeCalled = true
    }

    func removeWorktree(repo: GitRepository, path: String) async throws {
        removeWorktreeCalled = true
    }

    func forceDeleteWorktree(repoPath: String, worktreePath: String) async throws {
        forceDeleteWorktreeCalled = true
        if let error = forceDeleteWorktreeError { throw error }
    }

    func lockWorktree(repoPath: String, worktreePath: String) async throws {
        lockWorktreeCalled = true
    }

    func unlockWorktree(repoPath: String, worktreePath: String) async throws {
        unlockWorktreeCalled = true
    }

    func pruneWorktreesDryRun(repoPath: String) async throws -> [String] {
        pruneWorktreesDryRunResult
    }

    func pruneWorktrees(repoPath: String) async throws {
        pruneWorktreesCalled = true
        if let error = pruneWorktreesError { throw error }
    }

    func listBranches(repoPath: String) async throws -> [String] {
        if let error = listBranchesError { throw error }
        return listBranchesResult
    }

    func mergedLocalBranches(repoPath: String) async throws -> [String] {
        mergedLocalBranchesResult
    }

    func renameBranch(repoPath: String, oldName: String, newName: String) async throws {
        renameBranchCalls.append((oldName, newName))
    }

    private(set) var createBranchCalls: [(String, String)] = []
    func createBranch(repoPath: String, name: String, base: String) async throws {
        createBranchCalls.append((name, base))
    }

    func deleteLocalBranch(repoPath: String, branch: String) async throws {
        deleteLocalBranchCalls.append(branch)
    }

    func forceDeleteLocalBranch(repoPath: String, branch: String) async throws {}

    func fetchBranchFromOrigin(repoPath: String, branch: String) async throws {
        if let error = fetchBranchError { throw error }
    }

    func pullBranch(worktreePath: String) async throws {
        if let error = pullBranchError { throw error }
    }

    func addDetachedWorktree(repoPath: String, path: String) async throws {}

    func aheadCount(worktreePath: String) async -> Int { 0 }

    func defaultBranch(repoPath: String) async -> String { defaultBranchResult }

    func updateRemoteHead(repoPath: String) async {
        updateRemoteHeadCalled = true
    }

    func fetchRemote(repoPath: String) async {
        fetchRemoteCalled = true
    }

    func inferRepoName(repoPath: String) async -> String { inferRepoNameResult }
    func remoteURL(repoPath: String) async throws -> String { "" }

    func initializeSubmodules(repoPath: String) async throws {
        initializeSubmodulesCalls.append(repoPath)
        if let error = initializeSubmodulesError { throw error }
    }
}

@MainActor
final class MockRepoPersistence: RepoPersistenceProtocol {
    var config = RepoConfig(repositories: [])
    var saveError: Error?
    var saveCalled = false

    func loadConfig() -> RepoConfig { config }
    func save(_ config: RepoConfig) throws {
        saveCalled = true
        if let error = saveError { throw error }
        self.config = config
    }
    func startFileMonitoring(onExternalChange: @escaping @Sendable () -> Void) {}
}

// MARK: - Tests

@MainActor
final class WorktreeSidebarViewModelTests: XCTestCase {

    private func makeVM(
        gitService: MockGitService = MockGitService(),
        persistence: MockRepoPersistence = MockRepoPersistence(),
        prService: GitHubPRService = .shared,
        gitConfig: GitConfigStore = GitConfigStore(defaults: makeIsolatedDefaults()),
        workspaceStore: WorkspaceStore = makeIsolatedWorkspaceStore(),
        stackService: StackService = StackService()
    ) -> WorktreeSidebarViewModel {
        WorktreeSidebarViewModel(
            gitService: gitService, persistence: persistence, prService: prService, gitConfig: gitConfig,
            workspaceStore: workspaceStore, stackService: stackService)
    }

    private static func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "WorktreeSidebarViewModelTests.\(UUID().uuidString)")!
    }

    private func makeIsolatedDefaults() -> UserDefaults { Self.makeIsolatedDefaults() }

    /// A workspace store backed by a throwaway temp file so tests never touch the
    /// real `workspaces.json`.
    private static func makeIsolatedWorkspaceStore() -> WorkspaceStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WSVM-WorkspaceStore-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return WorkspaceStore(fileURL: dir.appendingPathComponent("workspaces.json"))
    }

    private func makeRepo(path: String = "/tmp/test-repo") -> ObservableRepository {
        ObservableRepository(name: "test", path: path)
    }

    private func makeWorktree(path: String = "/tmp/test-repo/.worktrees/feat", isMain: Bool = false) -> GitWorktree {
        GitWorktree(path: path, branch: "feat/test", commitHash: "abc12345", isMainWorktree: isMain, isLocked: false)
    }

    // MARK: - forceDeleteWorktree

    func testForceDeleteWorktree_nonMainWorktree_callsGitService() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()
        let worktree = makeWorktree()

        try await vm.forceDeleteWorktree(repo: repo, worktree: worktree)

        XCTAssertTrue(mock.forceDeleteWorktreeCalled)
    }

    func testForceDeleteWorktree_deletingIDsClearedAfterSuccess() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()
        let worktree = makeWorktree()

        try await vm.forceDeleteWorktree(repo: repo, worktree: worktree)

        XCTAssertTrue(vm.deletingWorktreeIDs.isEmpty)
    }

    func testForceDeleteWorktree_mainWorktree_throws() async {
        let vm = makeVM()
        let repo = makeRepo()
        let mainWorktree = makeWorktree(isMain: true)

        do {
            try await vm.forceDeleteWorktree(repo: repo, worktree: mainWorktree)
            XCTFail("Expected throw for main worktree")
        } catch WorktreeOperationError.removingMainWorktree {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testForceDeleteWorktree_deletingIDsClearedAfterError() async {
        let mock = MockGitService()
        mock.forceDeleteWorktreeError = NSError(domain: "test", code: 1)
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()
        let worktree = makeWorktree()

        _ = try? await vm.forceDeleteWorktree(repo: repo, worktree: worktree)

        XCTAssertTrue(vm.deletingWorktreeIDs.isEmpty)
    }

    func testForceDeleteWorktree_gitServiceError_rethrows() async {
        let mock = MockGitService()
        let expectedError = NSError(domain: "git", code: 128)
        mock.forceDeleteWorktreeError = expectedError
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()
        let worktree = makeWorktree()

        do {
            try await vm.forceDeleteWorktree(repo: repo, worktree: worktree)
            XCTFail("Expected error to be rethrown")
        } catch let error as NSError {
            XCTAssertEqual(error.code, 128)
        }
    }

    // MARK: - pruneWorktrees

    func testPruneWorktrees_callsGitService() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()
        vm.repositories = [repo]

        try await vm.pruneWorktrees(repo: repo)

        XCTAssertTrue(mock.pruneWorktreesCalled)
    }

    func testPruneWorktrees_gitServiceError_rethrows() async {
        let mock = MockGitService()
        mock.pruneWorktreesError = NSError(domain: "git", code: 1)
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()

        do {
            try await vm.pruneWorktrees(repo: repo)
            XCTFail("Expected error to be rethrown")
        } catch {
            // expected
        }
    }

    // MARK: - addRepository

    func testAddRepository_invalidPath_throwsNotAGitRepository() async {
        let mock = MockGitService()
        mock.isGitRepoResult = false
        let vm = makeVM(gitService: mock)

        do {
            try await vm.addRepository(path: "/not/a/repo")
            XCTFail("Expected notAGitRepository error")
        } catch WorktreeSidebarError.notAGitRepository(let path) {
            XCTAssertEqual(path, "/not/a/repo")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAddRepository_validPath_appendsRepository() async throws {
        let mock = MockGitService()
        mock.isGitRepoResult = true
        mock.inferRepoNameResult = "my-project"
        let vm = makeVM(gitService: mock)

        try await vm.addRepository(path: "/tmp/my-repo")

        XCTAssertTrue(vm.repositories.contains { $0.path == "/tmp/my-repo" })
    }

    func testAddRepository_providedName_usesProvidedName() async throws {
        let mock = MockGitService()
        mock.isGitRepoResult = true
        let vm = makeVM(gitService: mock)

        try await vm.addRepository(path: "/tmp/my-repo", name: "custom-name")

        XCTAssertTrue(vm.repositories.contains { $0.name == "custom-name" })
    }

    func testAddRepository_noProvidedName_infersFromGitService() async throws {
        let mock = MockGitService()
        mock.isGitRepoResult = true
        mock.inferRepoNameResult = "inferred-name"
        let vm = makeVM(gitService: mock)

        try await vm.addRepository(path: "/tmp/my-repo")

        XCTAssertTrue(vm.repositories.contains { $0.name == "inferred-name" })
    }

    // MARK: - persistence

    func testAddRepository_persistsToStorage() async throws {
        let mock = MockGitService()
        mock.isGitRepoResult = true
        let mockPersistence = MockRepoPersistence()
        let vm = makeVM(gitService: mock, persistence: mockPersistence)

        try await vm.addRepository(path: "/tmp/my-repo")

        XCTAssertTrue(mockPersistence.saveCalled)
    }

    func testLoadRepositories_populatesFromPersistence() {
        let mockPersistence = MockRepoPersistence()
        let existingRepo = GitRepository(name: "pre-loaded", path: "/tmp/pre-loaded-repo")
        mockPersistence.config = RepoConfig(repositories: [existingRepo])

        let vm = makeVM(persistence: mockPersistence)

        XCTAssertTrue(vm.repositories.contains { $0.path == "/tmp/pre-loaded-repo" })
    }

    // MARK: - moveRepository

    func testMoveRepository_updatesOrder() {
        let mockPersistence = MockRepoPersistence()
        let repoA = GitRepository(name: "alpha", path: "/tmp/alpha")
        let repoB = GitRepository(name: "beta", path: "/tmp/beta")
        let repoC = GitRepository(name: "gamma", path: "/tmp/gamma")
        mockPersistence.config = RepoConfig(repositories: [repoA, repoB, repoC])
        let vm = makeVM(persistence: mockPersistence)

        vm.moveRepository(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(vm.repositories.map(\.name), ["beta", "gamma", "alpha"])
    }

    func testMoveRepository_persists() {
        let mockPersistence = MockRepoPersistence()
        let repoA = GitRepository(name: "alpha", path: "/tmp/alpha")
        let repoB = GitRepository(name: "beta", path: "/tmp/beta")
        mockPersistence.config = RepoConfig(repositories: [repoA, repoB])
        let vm = makeVM(persistence: mockPersistence)
        mockPersistence.saveCalled = false

        vm.moveRepository(from: IndexSet(integer: 0), to: 2)

        XCTAssertTrue(mockPersistence.saveCalled)
    }

    // MARK: - worktree sorting

    func testRefreshWorktrees_mainWorktreeAlwaysFirst() async {
        let mock = MockGitService()
        let linked = GitWorktree(
            path: "/tmp/repo/.worktrees/feat", branch: "feat/a", commitHash: "aaa",
            isMainWorktree: false, isLocked: false)
        let main = GitWorktree(
            path: "/tmp/repo", branch: "develop", commitHash: "bbb",
            isMainWorktree: true, isLocked: false)
        mock.listWorktreesResult = [linked, main]
        let vm = makeVM(gitService: mock)
        let repo = makeRepo(path: "/tmp/repo")
        vm.repositories = [repo]

        await vm.refreshWorktrees(for: repo)

        XCTAssertTrue(vm.worktrees[repo.id]?.first?.isMainWorktree == true)
    }

    func testRefreshWorktrees_linkedWorktreesAlphabetical() async {
        let mock = MockGitService()
        let z = GitWorktree(
            path: "/tmp/repo/.worktrees/z", branch: "z-branch", commitHash: "zzz",
            isMainWorktree: false, isLocked: false)
        let a = GitWorktree(
            path: "/tmp/repo/.worktrees/a", branch: "a-branch", commitHash: "aaa",
            isMainWorktree: false, isLocked: false)
        let main = GitWorktree(
            path: "/tmp/repo", branch: "main", commitHash: "mmm",
            isMainWorktree: true, isLocked: false)
        mock.listWorktreesResult = [z, main, a]
        let vm = makeVM(gitService: mock)
        let repo = makeRepo(path: "/tmp/repo")
        vm.repositories = [repo]

        await vm.refreshWorktrees(for: repo)

        let branches = vm.worktrees[repo.id]?.map(\.branch) ?? []
        XCTAssertEqual(branches, ["main", "a-branch", "z-branch"])
    }

    // MARK: - branch sorting

    func testRefreshAvailableBranches_sortedAlphabetically() async {
        let mock = MockGitService()
        mock.listBranchesResult = ["z-feat", "a-fix", "m-chore"]
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()
        vm.repositories = [repo]
        vm.worktrees[repo.id] = []

        await vm.refreshAvailableBranches(for: repo)

        XCTAssertEqual(vm.availableBranches[repo.id], ["a-fix", "m-chore", "z-feat"])
    }

    func testRefreshAvailableBranches_excludesOccupiedBranches() async {
        let mock = MockGitService()
        mock.listBranchesResult = ["main", "feat/a", "feat/b"]
        let vm = makeVM(gitService: mock)
        let repo = makeRepo(path: "/tmp/repo")
        vm.repositories = [repo]
        let occupied = GitWorktree(
            path: "/tmp/repo/.worktrees/a", branch: "feat/a", commitHash: "aaa",
            isMainWorktree: false, isLocked: false)
        vm.worktrees[repo.id] = [occupied]

        await vm.refreshAvailableBranches(for: repo)

        XCTAssertFalse(vm.availableBranches[repo.id]?.contains("feat/a") == true)
        XCTAssertTrue(vm.availableBranches[repo.id]?.contains("main") == true)
    }

    // MARK: - isProtectedBranch

    func testIsProtectedBranch_repoOverride_matchesOverride() {
        let vm = makeVM()
        let repo = makeRepo()
        repo.protectedBranches = ["main", "develop"]

        XCTAssertTrue(vm.isProtectedBranch("main", for: repo))
        XCTAssertTrue(vm.isProtectedBranch("develop", for: repo))
        XCTAssertFalse(vm.isProtectedBranch("feat/x", for: repo))
    }

    func testIsProtectedBranch_noOverride_usesGlobalDefault() {
        let vm = makeVM()
        let repo = makeRepo()
        repo.protectedBranches = nil
        UserDefaults.standard.set("main,develop", forKey: "protectedBranches")
        defer { UserDefaults.standard.removeObject(forKey: "protectedBranches") }

        XCTAssertTrue(vm.isProtectedBranch("main", for: repo))
        XCTAssertTrue(vm.isProtectedBranch("develop", for: repo))
        XCTAssertFalse(vm.isProtectedBranch("feat/x", for: repo))
    }

    // MARK: - pullBranch spinners

    func testPullBranch_updatingIDClearedAfterSuccess() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)
        let repo = makeRepo(path: "/tmp/repo")
        let worktree = makeWorktree()
        vm.repositories = [repo]
        vm.worktrees[repo.id] = [worktree]

        try await vm.pullBranch(worktree: worktree, repo: repo)

        XCTAssertTrue(vm.updatingWorktreeIDs.isEmpty)
    }

    func testPullBranch_updatingIDClearedAfterError() async {
        let mock = MockGitService()
        mock.pullBranchError = NSError(domain: "git", code: 1)
        let vm = makeVM(gitService: mock)
        let repo = makeRepo(path: "/tmp/repo")
        let worktree = makeWorktree()
        vm.repositories = [repo]
        vm.worktrees[repo.id] = [worktree]

        _ = try? await vm.pullBranch(worktree: worktree, repo: repo)

        XCTAssertTrue(vm.updatingWorktreeIDs.isEmpty)
    }

    // MARK: - fetchBranchFromOrigin spinners

    func testFetchBranchFromOrigin_fetchingNameClearedAfterSuccess() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()
        vm.repositories = [repo]
        vm.worktrees[repo.id] = []

        try await vm.fetchBranchFromOrigin(repo: repo, branch: "feat/x")

        XCTAssertTrue(vm.fetchingBranchNames.isEmpty)
    }

    func testFetchBranchFromOrigin_fetchingNameClearedAfterError() async {
        let mock = MockGitService()
        mock.fetchBranchError = NSError(domain: "git", code: 1)
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()
        vm.repositories = [repo]
        vm.worktrees[repo.id] = []

        _ = try? await vm.fetchBranchFromOrigin(repo: repo, branch: "feat/x")

        XCTAssertTrue(vm.fetchingBranchNames.isEmpty)
    }

    // MARK: - setExpanded / setBranchSectionExpanded

    func testSetExpanded_insertsID() {
        let vm = makeVM()
        let id = UUID()
        vm.setExpanded(id, expanded: true)
        XCTAssertTrue(vm.expandedRepoIDs.contains(id))
    }

    func testSetExpanded_removesID() {
        let vm = makeVM()
        let id = UUID()
        vm.setExpanded(id, expanded: true)
        vm.setExpanded(id, expanded: false)
        XCTAssertFalse(vm.expandedRepoIDs.contains(id))
    }

    func testSetBranchSectionExpanded_insertsID() {
        let vm = makeVM()
        let id = UUID()
        vm.setBranchSectionExpanded(id, expanded: true)
        XCTAssertTrue(vm.expandedBranchSectionIDs.contains(id))
    }

    func testSetBranchSectionExpanded_removesID() {
        let vm = makeVM()
        let id = UUID()
        vm.setBranchSectionExpanded(id, expanded: true)
        vm.setBranchSectionExpanded(id, expanded: false)
        XCTAssertFalse(vm.expandedBranchSectionIDs.contains(id))
    }

    // MARK: - removeRepository

    func testRemoveRepository_removesFromList() async throws {
        let mock = MockGitService()
        let persistence = MockRepoPersistence()
        let vm = makeVM(gitService: mock, persistence: persistence)

        try await vm.addRepository(path: "/tmp/remove-test")
        let repo = vm.repositories.first { $0.path == "/tmp/remove-test" }
        XCTAssertNotNil(repo)

        vm.removeRepository(repo!)
        XCTAssertFalse(vm.repositories.contains { $0.path == "/tmp/remove-test" })
    }

    func testRemoveRepository_clearsWorktreesEntry() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)

        try await vm.addRepository(path: "/tmp/clear-test")
        let repo = vm.repositories.first { $0.path == "/tmp/clear-test" }!
        vm.worktrees[repo.id] = [makeWorktree()]

        vm.removeRepository(repo)
        XCTAssertNil(vm.worktrees[repo.id])
    }

    func testRemoveRepository_callsSave() async throws {
        let mock = MockGitService()
        let persistence = MockRepoPersistence()
        let vm = makeVM(gitService: mock, persistence: persistence)

        try await vm.addRepository(path: "/tmp/save-test")
        let repo = vm.repositories.first { $0.path == "/tmp/save-test" }!
        persistence.saveError = nil

        vm.removeRepository(repo)
        XCTAssertTrue(persistence.saveCalled)
    }

    // MARK: - updateRepository

    func testUpdateRepository_updatesName() {
        let vm = makeVM()
        let repo = makeRepo()
        vm.updateRepository(repo, name: "new-name", worktreeBasePath: nil)
        XCTAssertEqual(repo.name, "new-name")
    }

    func testUpdateRepository_updatesWorktreeBasePath() {
        let vm = makeVM()
        let repo = makeRepo()
        vm.updateRepository(repo, name: repo.name, worktreeBasePath: "/new/base")
        XCTAssertEqual(repo.worktreeBasePath, "/new/base")
    }

    func testUpdateRepository_updatesProtectedBranches() {
        let vm = makeVM()
        let repo = makeRepo()
        vm.updateRepository(
            repo, name: repo.name, worktreeBasePath: nil,
            protectedBranches: ["main", "develop"])
        XCTAssertEqual(repo.protectedBranches, ["main", "develop"])
    }

    func testUpdateRepository_callsSave() {
        let persistence = MockRepoPersistence()
        let vm = makeVM(persistence: persistence)
        let repo = makeRepo()
        vm.updateRepository(repo, name: "updated", worktreeBasePath: nil)
        XCTAssertTrue(persistence.saveCalled)
    }

    // MARK: - refreshWorktrees

    func testRefreshWorktrees_populatesWorktrees() async {
        let mock = MockGitService()
        mock.listWorktreesResult = [makeWorktree()]
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()

        await vm.refreshWorktrees(for: repo)

        XCTAssertEqual(vm.worktrees[repo.id]?.count, 1)
    }

    func testRefreshWorktrees_errorPreservesArray() async {
        let mock = MockGitService()
        mock.listWorktreesError = NSError(domain: "test", code: 1)
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()

        await vm.refreshWorktrees(for: repo)

        // On error with no previous data, we get an empty array
        XCTAssertEqual(vm.worktrees[repo.id]?.count, 0)
    }

    func testRefreshWorktrees_errorPreservesPriorData() async {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()

        // Seed prior data
        mock.listWorktreesResult = [makeWorktree(path: "/prior")]
        await vm.refreshWorktrees(for: repo)
        XCTAssertEqual(vm.worktrees[repo.id]?.count, 1)

        // Simulate error on next refresh — prior data preserved
        mock.listWorktreesError = NSError(domain: "test", code: 1)
        await vm.refreshWorktrees(for: repo)
        XCTAssertEqual(vm.worktrees[repo.id]?.count, 1)
    }

    // MARK: - refreshAvailableBranches

    func testRefreshAvailableBranches_filtersOccupiedBranches() async {
        let mock = MockGitService()
        mock.listWorktreesResult = [makeWorktree()]  // has branch "feat/test"
        mock.listBranchesResult = ["main", "develop", "feat/test"]
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()

        await vm.refreshWorktrees(for: repo)

        XCTAssertEqual(vm.availableBranches[repo.id]?.sorted(), ["develop", "main"])
    }

    func testRefreshAvailableBranches_errorPreservesExistingData() async {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()

        mock.listBranchesResult = ["main", "develop"]
        await vm.refreshAvailableBranches(for: repo)
        XCTAssertEqual(vm.availableBranches[repo.id]?.count, 2)

        mock.listBranchesError = NSError(domain: "test", code: 1)
        await vm.refreshAvailableBranches(for: repo)
        XCTAssertEqual(vm.availableBranches[repo.id]?.count, 2)
    }

    // MARK: - createWorktree

    func testCreateWorktree_callsGitService() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()

        try await vm.createWorktree(
            repo: repo, branchName: "feat/new", baseBranch: "main", path: "/tmp/new-wt")

        XCTAssertTrue(mock.addWorktreeCalled)
    }

    // MARK: - removeWorktree

    func testRemoveWorktree_mainWorktree_throws() async {
        let vm = makeVM()
        let repo = makeRepo()
        let mainWt = makeWorktree(isMain: true)

        do {
            try await vm.removeWorktree(repo: repo, worktree: mainWt)
            XCTFail("Expected throw for main worktree")
        } catch WorktreeOperationError.removingMainWorktree {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRemoveWorktree_nonMain_callsGitService() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()

        try await vm.removeWorktree(repo: repo, worktree: makeWorktree())

        XCTAssertTrue(mock.removeWorktreeCalled)
    }

    // MARK: - listBranches pass-through

    func testListBranches_returnsFromGitService() async throws {
        let mock = MockGitService()
        mock.listBranchesResult = ["main", "develop"]
        let vm = makeVM(gitService: mock)

        let branches = try await vm.listBranches(for: makeRepo())

        XCTAssertEqual(branches, ["main", "develop"])
    }

    // MARK: - defaultBranch pass-through

    func testDefaultBranch_returnsFromGitService() async {
        let mock = MockGitService()
        mock.defaultBranchResult = "trunk"
        let vm = makeVM(gitService: mock)

        let branch = await vm.defaultBranch(for: makeRepo())

        XCTAssertEqual(branch, "trunk")
    }

    // MARK: - lockWorktree / unlockWorktree

    func testLockWorktree_callsGitService() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)

        try await vm.lockWorktree(repo: makeRepo(), worktree: makeWorktree())

        XCTAssertTrue(mock.lockWorktreeCalled)
    }

    func testUnlockWorktree_callsGitService() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)

        try await vm.unlockWorktree(repo: makeRepo(), worktree: makeWorktree())

        XCTAssertTrue(mock.unlockWorktreeCalled)
    }

    // MARK: - pruneWorktreesDryRun

    func testPruneWorktreesDryRun_returnsResult() async throws {
        let mock = MockGitService()
        mock.pruneWorktreesDryRunResult = ["/prunable/one", "/prunable/two"]
        let vm = makeVM(gitService: mock)

        let result = try await vm.pruneWorktreesDryRun(repo: makeRepo())

        XCTAssertEqual(result, ["/prunable/one", "/prunable/two"])
    }

    // MARK: - mergedLocalBranches

    func testMergedLocalBranches_filtersProtectedFromRepoOverride() async throws {
        let mock = MockGitService()
        mock.mergedLocalBranchesResult = ["main", "feat/done", "develop"]
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()
        repo.protectedBranches = ["main", "develop"]

        let result = try await vm.mergedLocalBranches(repo: repo)

        XCTAssertEqual(result, ["feat/done"])
    }

    func testMergedLocalBranches_noProtection_returnsAll() async throws {
        let mock = MockGitService()
        mock.mergedLocalBranchesResult = ["feat/a", "feat/b"]
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()
        repo.protectedBranches = []  // explicit empty override

        let result = try await vm.mergedLocalBranches(repo: repo)

        XCTAssertEqual(result.sorted(), ["feat/a", "feat/b"])
    }

    // MARK: - deleteBranches

    func testDeleteBranches_callsDeleteForEach() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()

        try await vm.deleteBranches(repo: repo, branches: ["feat/a", "feat/b", "feat/c"])

        XCTAssertEqual(mock.deleteLocalBranchCalls, ["feat/a", "feat/b", "feat/c"])
    }

    func testDeleteBranches_emptyList_noOp() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)

        try await vm.deleteBranches(repo: makeRepo(), branches: [])

        XCTAssertTrue(mock.deleteLocalBranchCalls.isEmpty)
    }

    // MARK: - inferWorktreePath

    func testInferWorktreePath_emptyBranch_returnsEmpty() {
        let vm = makeVM()
        let path = vm.inferWorktreePath(for: makeRepo(), branchName: "")
        XCTAssertEqual(path, "")
    }

    func testInferWorktreePath_defaultBase() {
        let vm = makeVM()
        let repo = makeRepo(path: "/tmp/my-repo")
        let path = vm.inferWorktreePath(for: repo, branchName: "feat/foo")
        XCTAssertEqual(path, "/tmp/my-repo/.worktrees/feat/foo")
    }

    func testInferWorktreePath_customBase() {
        let vm = makeVM()
        let repo = makeRepo()
        repo.worktreeBasePath = "/custom/worktrees"
        let path = vm.inferWorktreePath(for: repo, branchName: "bugfix/issue-42")
        XCTAssertEqual(path, "/custom/worktrees/bugfix/issue-42")
    }

    func testInferWorktreePath_emptyBase_fallsBackToDefault() {
        let vm = makeVM()
        let repo = makeRepo(path: "/tmp/my-repo")
        repo.worktreeBasePath = ""
        let path = vm.inferWorktreePath(for: repo, branchName: "x")
        XCTAssertEqual(path, "/tmp/my-repo/.worktrees/x")
    }

    func testInferWorktreePath_preservesSlashInBranchName() {
        let vm = makeVM()
        let repo = makeRepo(path: "/r")
        let path = vm.inferWorktreePath(for: repo, branchName: "feat/nested/deep")
        XCTAssertEqual(path, "/r/.worktrees/feat/nested/deep")
    }

    // MARK: - save

    func testSave_callsPersistence() {
        let persistence = MockRepoPersistence()
        let vm = makeVM(persistence: persistence)
        vm.repositories = [makeRepo()]

        vm.save()

        XCTAssertTrue(persistence.saveCalled)
    }

    func testSave_passesRepositoriesToPersistence() {
        let persistence = MockRepoPersistence()
        let vm = makeVM(persistence: persistence)
        vm.repositories = [makeRepo(path: "/a"), makeRepo(path: "/b")]

        vm.save()

        XCTAssertEqual(persistence.config.repositories.count, 2)
    }

    // MARK: - refresh

    func testRefresh_reloadsFromPersistence() {
        let persistence = MockRepoPersistence()
        let vm = makeVM(persistence: persistence)
        let initialCount = vm.repositories.count

        // Add a repo externally
        persistence.config = RepoConfig(repositories: [
            GitRepository(name: "external", path: "/external")
        ])

        vm.refresh()

        XCTAssertEqual(vm.repositories.count, initialCount + 1)
    }

    // MARK: - refreshRepo

    func testRefreshRepo_updatesRemoteHeadAndRefreshesWorktrees() async {
        let mock = MockGitService()
        mock.listWorktreesResult = [makeWorktree()]
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()

        await vm.refreshRepo(for: repo)

        XCTAssertTrue(mock.fetchRemoteCalled)
        XCTAssertTrue(mock.updateRemoteHeadCalled)
        XCTAssertEqual(vm.worktrees[repo.id]?.count, 1)
    }

    // MARK: - collectPRPruneCandidates

    private func makeReadyPRService(openPRsJSON: String) -> GitHubPRService {
        let probe = GhCliProbe()
        probe.setStatusForTesting(.ready(ghPath: "/usr/bin/gh", login: "alice"))
        let runner = StubGhCommandRunner(json: openPRsJSON)
        return GitHubPRService(ghProbe: probe, commandRunner: runner)
    }

    func testCollectPRPruneCandidates_closedPRWorktree_isReturnedAsCandidate() async {
        let mock = MockGitService()
        let prService = makeReadyPRService(openPRsJSON: "[]")
        let vm = makeVM(gitService: mock, prService: prService)
        let repo = makeRepo()
        vm.worktrees[repo.id] = [makeWorktree(path: "/tmp/test-repo/.worktrees/pr-42")]

        let (closed, focus) = await vm.collectPRPruneCandidates(repo: repo, prService: prService)

        XCTAssertEqual(closed.map(\.prNumber), [42])
        XCTAssertTrue(focus.isEmpty)
    }

    func testCollectPRPruneCandidates_openPRWorktree_isNotReturnedAsCandidate() async {
        let mock = MockGitService()
        let prService = makeReadyPRService(openPRsJSON: openPRJSON(number: 42))
        let vm = makeVM(gitService: mock, prService: prService)
        let repo = makeRepo()
        vm.worktrees[repo.id] = [makeWorktree(path: "/tmp/test-repo/.worktrees/pr-42")]

        let (closed, focus) = await vm.collectPRPruneCandidates(repo: repo, prService: prService)

        XCTAssertTrue(closed.isEmpty)
        XCTAssertTrue(focus.isEmpty)
    }

    func testCollectPRPruneCandidates_focusWorktreesAreAlwaysCandidates() async {
        let mock = MockGitService()
        let prService = makeReadyPRService(openPRsJSON: "[]")
        let vm = makeVM(gitService: mock, prService: prService)
        let repo = makeRepo()
        vm.focusWorktrees[repo.id] = [makeWorktree(path: "/tmp/.termq/focus-worktrees/termq-focus--x")]

        let (closed, focus) = await vm.collectPRPruneCandidates(repo: repo, prService: prService)

        XCTAssertTrue(closed.isEmpty)
        XCTAssertEqual(focus.map(\.path), ["/tmp/.termq/focus-worktrees/termq-focus--x"])
    }

    func testCollectPRPruneCandidates_nothingToPrune_returnsEmpty() async {
        let mock = MockGitService()
        let prService = makeReadyPRService(openPRsJSON: "[]")
        let vm = makeVM(gitService: mock, prService: prService)
        let repo = makeRepo()

        let (closed, focus) = await vm.collectPRPruneCandidates(repo: repo, prService: prService)

        XCTAssertTrue(closed.isEmpty)
        XCTAssertTrue(focus.isEmpty)
    }

    private func openPRJSON(number: Int) -> String {
        """
        [
          {
            "number": \(number),
            "title": "Test PR",
            "headRefName": "feat/test",
            "headRefOid": "abc1234567890",
            "author": {"login": "alice"},
            "isCrossRepository": false,
            "isDraft": false,
            "reviewRequests": [],
            "assignees": []
          }
        ]
        """
    }

    // MARK: - Errors

    func testWorktreeOperationError_removingMainWorktree_hasDescription() {
        let error = WorktreeOperationError.removingMainWorktree
        XCTAssertNotNil(error.errorDescription)
    }

    func testWorktreeSidebarError_notAGitRepository_containsPath() {
        let error = WorktreeSidebarError.notAGitRepository(path: "/weird/path")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("/weird/path"))
    }

    // MARK: - Submodule initialization

    func testCreateWorktree_submodulesEnabled_initializesAtWorktreePath() async throws {
        let mock = MockGitService()
        let config = GitConfigStore(defaults: makeIsolatedDefaults())
        config.initializeSubmodules = true
        let vm = makeVM(gitService: mock, gitConfig: config)
        let repo = makeRepo()

        try await vm.createWorktree(
            repo: repo, branchName: "feat/x", baseBranch: nil, path: "/tmp/test-repo/.worktrees/feat-x")

        XCTAssertEqual(mock.initializeSubmodulesCalls, ["/tmp/test-repo/.worktrees/feat-x"])
    }

    func testCreateWorktree_submodulesDisabled_skipsInit() async throws {
        let mock = MockGitService()
        let config = GitConfigStore(defaults: makeIsolatedDefaults())
        config.initializeSubmodules = false
        let vm = makeVM(gitService: mock, gitConfig: config)
        let repo = makeRepo()

        try await vm.createWorktree(
            repo: repo, branchName: "feat/x", baseBranch: nil, path: "/tmp/test-repo/.worktrees/feat-x")

        XCTAssertTrue(mock.initializeSubmodulesCalls.isEmpty)
    }

    func testCreateWorktree_submoduleInitFailure_surfacesOperationError() async throws {
        let mock = MockGitService()
        mock.initializeSubmodulesError = NSError(
            domain: "git", code: 128,
            userInfo: [
                NSLocalizedDescriptionKey: "ssh: permission denied"
            ])
        let config = GitConfigStore(defaults: makeIsolatedDefaults())
        config.initializeSubmodules = true
        let vm = makeVM(gitService: mock, gitConfig: config)
        let repo = makeRepo()

        try await vm.createWorktree(
            repo: repo, branchName: "feat/x", baseBranch: nil, path: "/tmp/test-repo/.worktrees/feat-x")

        XCTAssertNotNil(vm.operationError)
        XCTAssertTrue(vm.operationError!.contains("ssh: permission denied"))
    }

    // MARK: - Workspace filtering & membership

    func testAddRepository_withActiveWorkspace_filesIntoIt() async throws {
        let ws = Self.makeIsolatedWorkspaceStore()
        let workspace = ws.create(name: "Work")
        ws.setActive(workspace.id)
        let mock = MockGitService()
        mock.isGitRepoResult = true
        let vm = makeVM(gitService: mock, workspaceStore: ws)

        try await vm.addRepository(path: "/tmp/ws-active")

        let repo = try XCTUnwrap(vm.repositories.first { $0.path == "/tmp/ws-active" })
        XCTAssertTrue(ws.contains(repoId: repo.id, in: workspace.id))
    }

    func testAddRepository_inAllView_leavesUnassigned() async throws {
        let ws = Self.makeIsolatedWorkspaceStore()
        let workspace = ws.create(name: "Work")  // exists but not active
        let mock = MockGitService()
        mock.isGitRepoResult = true
        let vm = makeVM(gitService: mock, workspaceStore: ws)

        try await vm.addRepository(path: "/tmp/ws-all")

        let repo = try XCTUnwrap(vm.repositories.first { $0.path == "/tmp/ws-all" })
        XCTAssertFalse(ws.contains(repoId: repo.id, in: workspace.id))
    }

    func testRemoveRepository_cleansWorkspaceMembership() async throws {
        let ws = Self.makeIsolatedWorkspaceStore()
        let workspace = ws.create(name: "Work")
        ws.setActive(workspace.id)
        let mock = MockGitService()
        mock.isGitRepoResult = true
        let vm = makeVM(gitService: mock, workspaceStore: ws)

        try await vm.addRepository(path: "/tmp/ws-remove")
        let repo = try XCTUnwrap(vm.repositories.first { $0.path == "/tmp/ws-remove" })
        XCTAssertTrue(ws.contains(repoId: repo.id, in: workspace.id))

        vm.removeRepository(repo)

        XCTAssertFalse(ws.contains(repoId: repo.id, in: workspace.id))
    }

    func testDisplayedRepositories_allView_showsEverything() {
        let persistence = MockRepoPersistence()
        persistence.config = RepoConfig(repositories: [
            GitRepository(name: "a", path: "/a"),
            GitRepository(name: "b", path: "/b"),
        ])
        let vm = makeVM(persistence: persistence)

        XCTAssertEqual(vm.displayedRepositories.count, 2)
    }

    func testDisplayedRepositories_activeWorkspace_showsOnlyMembers() {
        let repoA = GitRepository(name: "a", path: "/a")
        let repoB = GitRepository(name: "b", path: "/b")
        let persistence = MockRepoPersistence()
        persistence.config = RepoConfig(repositories: [repoA, repoB])
        let ws = Self.makeIsolatedWorkspaceStore()
        let workspace = ws.create(name: "Work")
        ws.add(repoId: repoA.id, to: workspace.id)
        ws.setActive(workspace.id)
        let vm = makeVM(persistence: persistence, workspaceStore: ws)

        XCTAssertEqual(vm.displayedRepositories.map(\.path), ["/a"])
    }

    func testDisplayedRepositories_emptyActiveWorkspace_isEmpty() {
        let persistence = MockRepoPersistence()
        persistence.config = RepoConfig(repositories: [
            GitRepository(name: "a", path: "/a"),
            GitRepository(name: "b", path: "/b"),
        ])
        let ws = Self.makeIsolatedWorkspaceStore()
        let workspace = ws.create(name: "Empty")  // no members
        ws.setActive(workspace.id)
        let vm = makeVM(persistence: persistence, workspaceStore: ws)

        XCTAssertTrue(vm.displayedRepositories.isEmpty)
    }

    // MARK: - Stacks

    private func makeStackGraph(branchName: String = "feat/test") -> StackGraph {
        StackGraph(
            branches: [
                StackBranch(
                    name: branchName, isCurrent: true, checkedOutElsewhere: nil, parent: nil,
                    children: [], needsRestack: false, changeRequest: nil, push: nil)
            ])
    }

    func testRefreshStack_noProviderAvailable_leavesStacksEmpty() async {
        let stackService = StackService(registry: StackProviderRegistry(providers: []))
        await stackService.probe()
        let vm = makeVM(stackService: stackService)
        let repo = makeRepo()

        await vm.refreshStack(for: repo)

        XCTAssertNil(vm.stacks[repo.id])
    }

    func testRefreshStack_providerAvailable_mirrorsGraphIntoStacksByRepoId() async {
        let fake = FakeStackProvider()
        await fake.setGraph(makeStackGraph(), for: "/tmp/test-repo")
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let vm = makeVM(stackService: stackService)
        let repo = makeRepo()

        await vm.refreshStack(for: repo)

        XCTAssertEqual(vm.stacks[repo.id]?.branches.map(\.name), ["feat/test"])
    }

    func testRefreshWorktrees_alsoRefreshesStack() async {
        let fake = FakeStackProvider()
        await fake.setGraph(makeStackGraph(), for: "/tmp/test-repo")
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let mock = MockGitService()
        mock.listWorktreesResult = [makeWorktree()]
        let vm = makeVM(gitService: mock, stackService: stackService)
        let repo = makeRepo()

        await vm.refreshWorktrees(for: repo)

        XCTAssertEqual(vm.stacks[repo.id]?.branches.map(\.name), ["feat/test"])
    }

    func testEnableStacking_success_populatesStack() async {
        let fake = FakeStackProvider()
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let mock = MockGitService()
        mock.defaultBranchResult = "main"
        let vm = makeVM(gitService: mock, stackService: stackService)
        let repo = makeRepo()

        await vm.enableStacking(for: repo)

        let calls = await fake.initializeCalls
        XCTAssertEqual(calls.first?.trunk, "main")
        XCTAssertTrue(stackService.isStacked(repo: repo.path))
        XCTAssertNil(vm.operationError)
    }

    func testEnableStacking_failure_setsOperationError() async {
        let fake = FakeStackProvider()
        await fake.setInitializeError(
            StackProviderError.commandFailed(command: "gs repo init", exitCode: 1, output: "boom"))
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let vm = makeVM(stackService: stackService)
        let repo = makeRepo()

        await vm.enableStacking(for: repo)

        XCTAssertNotNil(vm.operationError)
        XCTAssertTrue(vm.operationError?.contains("boom") ?? false)
    }

    func testRemoveRepository_evictsStackState() async {
        let fake = FakeStackProvider()
        await fake.setGraph(makeStackGraph(), for: "/tmp/test-repo")
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let persistence = MockRepoPersistence()
        let repo = makeRepo()
        persistence.config = RepoConfig(repositories: [repo.toGitRepository()])
        let vm = makeVM(persistence: persistence, stackService: stackService)
        await vm.refreshStack(for: repo)
        XCTAssertNotNil(vm.stacks[repo.id])

        vm.removeRepository(repo)

        XCTAssertNil(vm.stacks[repo.id])
        XCTAssertFalse(stackService.isStacked(repo: repo.path))
    }

    // MARK: - Stack groups (inventory section)

    private func makeBranch(
        _ name: String, parent: String? = nil, children: [String] = [], isCurrent: Bool = false
    ) -> StackBranch {
        StackBranch(
            name: name, isCurrent: isCurrent, checkedOutElsewhere: nil, parent: parent,
            children: children, needsRestack: false, changeRequest: nil, push: nil)
    }

    /// Trunk (develop) fanning out to two stacks and a lone branch — the multi-ups
    /// trunk shape observed live. The trunk is present in the graph (it's the only
    /// entry without a parent) and must never appear in any group.
    private func makeMultiStackVM() async -> (WorktreeSidebarViewModel, ObservableRepository) {
        let fake = FakeStackProvider()
        let graph = StackGraph(
            branches: [
                makeBranch("develop", children: ["zeta-base", "alpha-base", "lone-branch"], isCurrent: true),
                // Stack 1: zeta-base ← zeta-top (root sorts after stack 2's root)
                makeBranch("zeta-base", parent: "develop", children: ["zeta-top"]),
                makeBranch("zeta-top", parent: "zeta-base"),
                // Stack 2: alpha-base ← alpha-mid ← alpha-top
                makeBranch("alpha-base", parent: "develop", children: ["alpha-mid"]),
                makeBranch("alpha-mid", parent: "alpha-base", children: ["alpha-top"]),
                makeBranch("alpha-top", parent: "alpha-mid"),
                // Lone tracked branch on trunk — a one-entry stack (still a group)
                makeBranch("lone-branch", parent: "develop"),
            ])
        await fake.setGraph(graph, for: "/tmp/test-repo")
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let vm = makeVM(stackService: stackService)
        let repo = makeRepo()
        await vm.refreshStack(for: repo)
        return (vm, repo)
    }

    func testStackGroups_groupsByRootSortedByName_excludingOnlyTrunk() async {
        let (vm, repo) = await makeMultiStackVM()

        let groups = vm.stackGroups(for: repo)

        // lone-branch is a one-entry stack — a legitimate group, not a Local Branches
        // entry (Round-3 addendum).
        XCTAssertEqual(groups.map(\.rootName), ["alpha-base", "lone-branch", "zeta-base"])
        XCTAssertEqual(groups[0].branches.map(\.name), ["alpha-base", "alpha-mid", "alpha-top"])
        XCTAssertEqual(groups[1].branches.map(\.name), ["lone-branch"])
        XCTAssertEqual(groups[2].branches.map(\.name), ["zeta-base", "zeta-top"])
        // The trunk is a fan-out point — never a group title, never a member.
        XCTAssertFalse(groups.contains { $0.rootName == "develop" })
        XCTAssertFalse(groups.contains { $0.branches.contains { $0.name == "develop" } })
    }

    func testStackGroups_noGraph_returnsEmpty() {
        let vm = makeVM()
        XCTAssertTrue(vm.stackGroups(for: makeRepo()).isEmpty)
    }

    func testWorktreeForBranch_matchesWorktreeByBranchName() async {
        let (vm, repo) = await makeMultiStackVM()
        vm.worktrees[repo.id] = [
            GitWorktree(
                path: "/tmp/test-repo/.worktrees/alpha-mid", branch: "alpha-mid",
                commitHash: "abc12345", isMainWorktree: false, isLocked: false)
        ]

        XCTAssertEqual(
            vm.worktree(forBranch: "alpha-mid", repo: repo)?.path,
            "/tmp/test-repo/.worktrees/alpha-mid")
        XCTAssertNil(vm.worktree(forBranch: "alpha-top", repo: repo))
    }

    func testDisplayedLocalBranches_excludesStackGroupMembers() async {
        let (vm, repo) = await makeMultiStackVM()
        vm.availableBranches[repo.id] = ["alpha-mid", "lone-branch", "unrelated", "zeta-top"]

        // Stack members — including one-entry stacks like lone-branch — are listed in
        // the Stacks section only; only untracked branches stay in Local Branches.
        XCTAssertEqual(vm.displayedLocalBranches(for: repo), ["unrelated"])
    }

    func testDisplayedLocalBranches_noStacks_passesThrough() {
        let vm = makeVM()
        let repo = makeRepo()
        vm.availableBranches[repo.id] = ["a", "b"]
        XCTAssertEqual(vm.displayedLocalBranches(for: repo), ["a", "b"])
    }

    // MARK: - Restack outcome

    func testRestack_nothingNeedsRestack_reportsUpToDate() async throws {
        let (vm, _, repo) = await makeStackedVM()

        let report = try await vm.restack(repo: repo, worktree: makeWorktree(), scope: .stack)

        XCTAssertEqual(report.outcome, .upToDate)
        XCTAssertTrue(report.skipped.isEmpty)
    }

    func testRestack_resolvesNeedingBranches_reportsCount() async throws {
        let fake = FakeStackProvider()
        let needing = StackGraph(
            branches: [
                makeBranch("develop", children: ["feat/a"], isCurrent: true),
                StackBranch(
                    name: "feat/a", isCurrent: false, checkedOutElsewhere: nil, parent: "develop",
                    children: ["feat/b"], needsRestack: true, changeRequest: nil, push: nil),
                StackBranch(
                    name: "feat/b", isCurrent: false, checkedOutElsewhere: nil, parent: "feat/a",
                    children: [], needsRestack: true, changeRequest: nil, push: nil),
            ])
        await fake.setGraph(needing, for: "/tmp/test-repo")
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let vm = makeVM(stackService: stackService)
        let repo = makeRepo()
        await vm.refreshStack(for: repo)

        // The provider "restacks": afterwards nothing needs a restack.
        let clean = StackGraph(
            branches: [
                makeBranch("develop", children: ["feat/a"], isCurrent: true),
                makeBranch("feat/a", parent: "develop", children: ["feat/b"]),
                makeBranch("feat/b", parent: "feat/a"),
            ])
        await fake.setGraph(clean, for: "/tmp/test-repo")

        let report = try await vm.restack(repo: repo, worktree: makeWorktree(), scope: .stack)

        XCTAssertEqual(report.outcome, .restacked(2))
    }

    func testRestack_conflictPause_reportsPaused() async throws {
        let fake = FakeStackProvider()
        await fake.setGraph(makeStackGraph(), for: "/tmp/test-repo")
        await fake.setMutationError(
            StackProviderError.commandFailed(command: "gs stack restack", exitCode: 1, output: "conflict"))
        await fake.setPausedOperationResult(
            StackPausedOperation(kind: .restack, conflictedFiles: ["a.swift"]))
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let vm = makeVM(stackService: stackService)
        let repo = makeRepo()
        await vm.refreshStack(for: repo)

        let report = try await vm.restack(repo: repo, worktree: makeWorktree(), scope: .stack)

        XCTAssertEqual(report.outcome, .paused)
    }

    func testMainWorktree_returnsTheMainEntry() {
        let vm = makeVM()
        let repo = makeRepo()
        vm.worktrees[repo.id] = [
            makeWorktree(path: "/tmp/test-repo/.worktrees/feat", isMain: false),
            makeWorktree(path: "/tmp/test-repo", isMain: true),
        ]

        XCTAssertEqual(vm.mainWorktree(for: repo)?.path, "/tmp/test-repo")
    }

    func testMainWorktree_noWorktrees_returnsNil() {
        let vm = makeVM()
        XCTAssertNil(vm.mainWorktree(for: makeRepo()))
    }

    // MARK: - Reveal preparation

    func testPrepareRevealWorktree_expandsRepoAndWorktreesSection() {
        let vm = makeVM()
        let repo = makeRepo()
        // Start fully collapsed: rows are not emitted, so scrollTo has no target.
        vm.setExpanded(repo.id, expanded: false)
        vm.setWorktreeSectionExpanded(repo.id, expanded: false)

        vm.prepareRevealWorktree(for: repo)

        XCTAssertTrue(vm.expandedRepoIDs.contains(repo.id))
        XCTAssertTrue(vm.isWorktreeSectionExpanded(repo.id))
    }

    func testPrepareRevealWorktree_alreadyExpanded_isIdempotent() {
        let vm = makeVM()
        let repo = makeRepo()
        vm.setExpanded(repo.id, expanded: true)
        vm.setWorktreeSectionExpanded(repo.id, expanded: true)

        vm.prepareRevealWorktree(for: repo)

        XCTAssertTrue(vm.expandedRepoIDs.contains(repo.id))
        XCTAssertTrue(vm.isWorktreeSectionExpanded(repo.id))
    }

    // MARK: - Stack glyph

    func testStackRootName_stackedWorktree_returnsBottomBranch() async {
        // develop (trunk) ← feat/base ← feat/broken-out; the glyph names the bottom.
        let (vm, _, repo, _) = await makeOrchestrationVM()
        let worktree = GitWorktree(
            path: "/tmp/test-repo/.worktrees/feat-broken-out", branch: "feat/broken-out",
            commitHash: "abc12345", isMainWorktree: false, isLocked: false)

        XCTAssertEqual(vm.stackRootName(for: worktree, repo: repo), "feat/base")
    }

    func testStackRootName_trunkOrUnstackedWorktree_returnsNil() async {
        let (vm, _, repo, _) = await makeOrchestrationVM()
        let trunkWorktree = GitWorktree(
            path: "/tmp/test-repo", branch: "develop",
            commitHash: "abc12345", isMainWorktree: true, isLocked: false)
        let plainWorktree = GitWorktree(
            path: "/tmp/test-repo/.worktrees/plain", branch: "plain-branch",
            commitHash: "abc12345", isMainWorktree: false, isLocked: false)

        // The trunk fans out to stacks but is never a stack member itself.
        XCTAssertNil(vm.stackRootName(for: trunkWorktree, repo: repo))
        XCTAssertNil(vm.stackRootName(for: plainWorktree, repo: repo))
    }

    /// Regression test for the WORKTREES/STACKS dual-listing bug: a lone tracked
    /// branch with nothing above it is still a legitimate one-entry stack (mirrors
    /// `stackRoots`), so `stackRootName` must return non-nil — not just for
    /// multi-branch stacks.
    func testStackRootName_singleBranchStack_returnsOwnName() async {
        let fake = FakeStackProvider()
        let graph = StackGraph(
            branches: [
                makeBranch("develop", children: ["feat/lone"], isCurrent: true),
                makeBranch("feat/lone", parent: "develop"),
            ])
        await fake.setGraph(graph, for: "/tmp/test-repo")
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let vm = makeVM(stackService: stackService)
        let repo = makeRepo()
        await vm.refreshStack(for: repo)
        let worktree = GitWorktree(
            path: "/tmp/test-repo/.worktrees/feat-lone", branch: "feat/lone",
            commitHash: "abc12345", isMainWorktree: false, isLocked: false)

        XCTAssertEqual(vm.stackRootName(for: worktree, repo: repo), "feat/lone")
    }

    // MARK: - Cross-worktree restack orchestration

    /// Stack develop ← feat/base ← feat/broken-out, where feat/broken-out is checked
    /// out in its own (broken-out) worktree and still needs a restack — the shape gs
    /// silently skips.
    private func makeOrchestrationVM() async -> (
        vm: WorktreeSidebarViewModel, fake: FakeStackProvider, repo: ObservableRepository,
        ownerPath: String
    ) {
        let fake = FakeStackProvider()
        let graph = StackGraph(
            branches: [
                makeBranch("develop", children: ["feat/base"], isCurrent: true),
                makeBranch("feat/base", parent: "develop", children: ["feat/broken-out"]),
                StackBranch(
                    name: "feat/broken-out", isCurrent: false,
                    checkedOutElsewhere: "/tmp/test-repo/.worktrees/feat-broken-out",
                    parent: "feat/base", children: [], needsRestack: true,
                    changeRequest: nil, push: nil),
            ])
        await fake.setGraph(graph, for: "/tmp/test-repo")
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let vm = makeVM(stackService: stackService)
        vm.worktreeDirtyCheckOverride = { _ in false }
        vm.worktreeInUseCheckOverride = { _ in false }
        let repo = makeRepo()
        let ownerPath = "/tmp/test-repo/.worktrees/feat-broken-out"
        vm.worktrees[repo.id] = [
            makeWorktree(path: "/tmp/test-repo", isMain: true),
            GitWorktree(
                path: ownerPath, branch: "feat/broken-out", commitHash: "bbb22222",
                isMainWorktree: false, isLocked: false),
        ]
        await vm.refreshStack(for: repo)
        return (vm, fake, repo, ownerPath)
    }

    func testOrchestration_eligibleBrokenOutBranch_getsFollowUpRestackInOwningWorktree() async {
        let (vm, fake, repo, ownerPath) = await makeOrchestrationVM()

        let skipped = await vm.orchestrateCrossWorktreeRestacks(for: repo)

        XCTAssertTrue(skipped.isEmpty)
        let log = await fake.mutationLog
        XCTAssertTrue(
            log.contains("restack:branch(\"feat/broken-out\"):in=\(ownerPath)"),
            "expected a single-branch follow-up restack in the owning worktree, got \(log)")
    }

    func testOrchestration_dirtyOwningWorktree_skippedWithReason() async {
        let (vm, fake, repo, ownerPath) = await makeOrchestrationVM()
        vm.worktreeDirtyCheckOverride = { path in path == ownerPath }

        let skipped = await vm.orchestrateCrossWorktreeRestacks(for: repo)

        XCTAssertEqual(skipped.count, 1)
        XCTAssertEqual(skipped.first?.branch, "feat/broken-out")
        XCTAssertEqual(skipped.first?.worktreePath, ownerPath)
        XCTAssertEqual(skipped.first?.reason, .dirty)
        let log = await fake.mutationLog
        XCTAssertTrue(log.isEmpty, "dirty worktree must not be touched, got \(log)")
    }

    func testOrchestration_inUseOwningWorktree_skippedWithReason() async {
        let (vm, fake, repo, ownerPath) = await makeOrchestrationVM()
        vm.worktreeInUseCheckOverride = { path in path == ownerPath }

        let skipped = await vm.orchestrateCrossWorktreeRestacks(for: repo)

        XCTAssertEqual(skipped.first?.reason, .inUse)
        let log = await fake.mutationLog
        XCTAssertTrue(log.isEmpty, "in-use worktree must not be touched, got \(log)")
    }

    func testOrchestration_conflictInFollowUp_pausesOnOwningWorktree() async {
        let (vm, fake, repo, ownerPath) = await makeOrchestrationVM()
        await fake.setMutationError(
            StackProviderError.commandFailed(
                command: "gs branch restack", exitCode: 1, output: "conflict"))
        await fake.setPausedOperationResult(
            StackPausedOperation(kind: .restack, conflictedFiles: ["x.swift"]))

        _ = await vm.orchestrateCrossWorktreeRestacks(for: repo)

        // The banner must attach to the worktree that owns the paused rebase — the
        // broken-out worktree the follow-up ran in, not the main one.
        XCTAssertEqual(vm.stackService.conflicts[repo.path]?.worktree, ownerPath)
    }

    func testOrchestration_sweepsAreCapped() async {
        let (vm, fake, repo, _) = await makeOrchestrationVM()
        // The branch never converges: restack "succeeds" but needsRestack stays set.
        await fake.setClearsNeedsRestackOnBranchRestack(false)

        _ = await vm.orchestrateCrossWorktreeRestacks(for: repo)

        let log = await fake.mutationLog
        let followUps = log.filter { $0.hasPrefix("restack:branch") }
        XCTAssertEqual(followUps.count, 2, "sweeps must be capped at 2, got \(log)")
    }

    func testOrchestration_excludedWorktree_isNeverTouched() async {
        let (vm, fake, repo, ownerPath) = await makeOrchestrationVM()

        let skipped = await vm.orchestrateCrossWorktreeRestacks(for: repo, excluding: ownerPath)

        XCTAssertTrue(skipped.isEmpty)
        let log = await fake.mutationLog
        XCTAssertTrue(log.isEmpty, "the excluded worktree must not receive follow-ups, got \(log)")
    }

    // MARK: - Worktrees section expansion

    func testWorktreeSection_defaultsToExpanded() {
        let vm = makeVM()
        XCTAssertTrue(vm.isWorktreeSectionExpanded(UUID()))
    }

    func testWorktreeSection_collapseAndReexpand() {
        let vm = makeVM()
        let id = UUID()

        vm.setWorktreeSectionExpanded(id, expanded: false)
        XCTAssertFalse(vm.isWorktreeSectionExpanded(id))
        XCTAssertTrue(vm.collapsedWorktreeSectionIDs.contains(id))

        vm.setWorktreeSectionExpanded(id, expanded: true)
        XCTAssertTrue(vm.isWorktreeSectionExpanded(id))
        XCTAssertFalse(vm.collapsedWorktreeSectionIDs.contains(id))
    }

    // MARK: - Guarded stack switch

    private func makeStackedVM() async -> (
        vm: WorktreeSidebarViewModel, fake: FakeStackProvider, repo: ObservableRepository
    ) {
        let fake = FakeStackProvider()
        let graph = StackGraph(
            branches: [
                StackBranch(
                    name: "feat/test", isCurrent: true, checkedOutElsewhere: nil, parent: nil,
                    children: ["feat/next"], needsRestack: false, changeRequest: nil, push: nil),
                StackBranch(
                    name: "feat/next", isCurrent: false, checkedOutElsewhere: nil, parent: "feat/test",
                    children: [], needsRestack: false, changeRequest: nil, push: nil),
                StackBranch(
                    name: "feat/elsewhere", isCurrent: false, checkedOutElsewhere: "/other/wt",
                    parent: "feat/test", children: [], needsRestack: false, changeRequest: nil, push: nil),
            ])
        await fake.setGraph(graph, for: "/tmp/test-repo")
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let vm = makeVM(stackService: stackService)
        vm.worktreeDirtyCheckOverride = { _ in false }
        vm.worktreeInUseCheckOverride = { _ in false }
        let repo = makeRepo()
        await vm.refreshStack(for: repo)
        return (vm, fake, repo)
    }

    func testSwitchStackBranch_cleanAndUnused_invokesProvider() async throws {
        let (vm, fake, repo) = await makeStackedVM()

        try await vm.switchStackBranch(repo: repo, worktree: makeWorktree(), to: "feat/next")

        let log = await fake.mutationLog
        XCTAssertEqual(log.first, "switch:feat/next")
    }

    func testSwitchStackBranch_dirtyWorktree_blocksWithoutProviderCall() async {
        let (vm, fake, repo) = await makeStackedVM()
        vm.worktreeDirtyCheckOverride = { _ in true }

        do {
            try await vm.switchStackBranch(repo: repo, worktree: makeWorktree(), to: "feat/next")
            XCTFail("Expected worktreeDirty")
        } catch StackSwitchBlockedError.worktreeDirty {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let log = await fake.mutationLog
        XCTAssertTrue(log.isEmpty)
    }

    func testSwitchStackBranch_worktreeInUse_blocksWithoutProviderCall() async {
        let (vm, fake, repo) = await makeStackedVM()
        vm.worktreeInUseCheckOverride = { _ in true }

        do {
            try await vm.switchStackBranch(repo: repo, worktree: makeWorktree(), to: "feat/next")
            XCTFail("Expected worktreeInUse")
        } catch StackSwitchBlockedError.worktreeInUse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let log = await fake.mutationLog
        XCTAssertTrue(log.isEmpty)
    }

    func testSwitchStackBranch_targetCheckedOutElsewhere_blocksWithPath() async {
        let (vm, fake, repo) = await makeStackedVM()

        do {
            try await vm.switchStackBranch(repo: repo, worktree: makeWorktree(), to: "feat/elsewhere")
            XCTFail("Expected checkedOutElsewhere")
        } catch StackSwitchBlockedError.checkedOutElsewhere(let path) {
            XCTAssertEqual(path, "/other/wt")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let log = await fake.mutationLog
        XCTAssertTrue(log.isEmpty)
    }

    // MARK: - Add branch to stack

    func testAddBranchToStack_newBranch_createsStackedOnTarget() async throws {
        let (vm, fake, repo) = await makeStackedVM()

        try await vm.addBranchToStack(
            repo: repo, worktree: makeWorktree(), name: "feat/new", target: "feat/test")

        let log = await fake.mutationLog
        XCTAssertEqual(log.first, "create:feat/new:target=feat/test")
    }

    // MARK: - Submit + sync (Phase 3)

    func testSubmitStack_invokesProviderSubmit() async throws {
        let (vm, fake, repo) = await makeStackedVM()

        try await vm.submitStack(
            repo: repo, worktree: makeWorktree(), scope: .stack,
            options: StackSubmitOptions(draft: false, updateOnly: false))

        let log = await fake.mutationLog
        XCTAssertEqual(log.first, "submit:stack")
    }

    func testSyncStackRepo_reportsRemovedBranches() async throws {
        let (vm, fake, repo) = await makeStackedVM()
        XCTAssertEqual(vm.stacks[repo.id]?.branches.count, 3)

        // Simulate the provider deleting a merged local during sync: the graph the
        // refresh fetches afterwards no longer contains feat/next.
        let shrunk = StackGraph(
            branches: [
                StackBranch(
                    name: "feat/test", isCurrent: true, checkedOutElsewhere: nil, parent: nil,
                    children: [], needsRestack: false, changeRequest: nil, push: nil)
            ])
        await fake.setGraph(shrunk, for: "/tmp/test-repo")

        let report = try await vm.syncStackRepo(for: repo, worktree: makeWorktree())

        XCTAssertEqual(report.removedBranches, ["feat/elsewhere", "feat/next"])
        let log = await fake.mutationLog
        XCTAssertEqual(log.first, "sync")
    }

    func testRefreshRepo_stackedRepo_syncsInsteadOfFetching() async {
        let fake = FakeStackProvider()
        await fake.setGraph(makeStackGraph(), for: "/tmp/test-repo")
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let mock = MockGitService()
        mock.listWorktreesResult = [makeWorktree(path: "/tmp/test-repo", isMain: true)]
        let vm = makeVM(gitService: mock, stackService: stackService)
        let repo = makeRepo()
        // Populate worktrees + stack state first (startup refresh).
        await vm.refreshWorktrees(for: repo)

        await vm.refreshRepo(for: repo)

        let log = await fake.mutationLog
        XCTAssertEqual(log.first, "sync")
        XCTAssertFalse(mock.fetchRemoteCalled, "stacked repos must sync, not plain-fetch")
    }

    func testRefreshRepo_unstackedRepo_plainFetch() async {
        let fake = FakeStackProvider()  // ready but repo not initialized
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let mock = MockGitService()
        mock.listWorktreesResult = [makeWorktree(path: "/tmp/test-repo", isMain: true)]
        let vm = makeVM(gitService: mock, stackService: stackService)
        let repo = makeRepo()
        await vm.refreshWorktrees(for: repo)

        await vm.refreshRepo(for: repo)

        XCTAssertTrue(mock.fetchRemoteCalled)
        let log = await fake.mutationLog
        XCTAssertTrue(log.isEmpty)
    }

    func testAddBranchToStack_existingBranch_tracksWithCurrentBranchBase() async throws {
        let fake = FakeStackProvider()
        await fake.setGraph(makeStackGraph(), for: "/tmp/test-repo")
        let stackService = StackService(registry: StackProviderRegistry(providers: [fake]))
        await stackService.probe()
        let mock = MockGitService()
        mock.listBranchesResult = ["main", "feat/existing"]
        let vm = makeVM(gitService: mock, stackService: stackService)
        let repo = makeRepo()

        try await vm.addBranchToStack(
            repo: repo, worktree: makeWorktree(), name: "feat/existing", target: nil)

        let log = await fake.mutationLog
        // Base falls back to the worktree's current branch when no target is given.
        XCTAssertEqual(log.first, "track:feat/existing:base=feat/test")
    }
}
