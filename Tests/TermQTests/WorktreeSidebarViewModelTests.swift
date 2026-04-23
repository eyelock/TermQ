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
    var pruneWorktreesDryRunResult: [String] = []
    var mergedLocalBranchesResult: [String] = []
    var inferRepoNameResult: String = "mock-repo"
    var defaultBranchResult: String = "main"

    private(set) var forceDeleteWorktreeCalled = false
    private(set) var pruneWorktreesCalled = false
    private(set) var isGitRepoCalled = false
    private(set) var addWorktreeCalled = false
    private(set) var removeWorktreeCalled = false
    private(set) var checkoutBranchAsWorktreeCalled = false
    private(set) var lockWorktreeCalled = false
    private(set) var unlockWorktreeCalled = false
    private(set) var deleteLocalBranchCalls: [String] = []
    private(set) var updateRemoteHeadCalled = false

    func isGitRepo(path: String) async throws -> Bool {
        isGitRepoCalled = true
        if let error = isGitRepoError { throw error }
        return isGitRepoResult
    }

    func listWorktrees(repoPath: String) async throws -> [GitWorktree] {
        if let error = listWorktreesError { throw error }
        return listWorktreesResult
    }

    func addWorktree(repo: GitRepository, branch: String, path: String, baseBranch: String?) async throws {
        addWorktreeCalled = true
    }

    func removeWorktree(repo: GitRepository, path: String) async throws {
        removeWorktreeCalled = true
    }

    func checkoutBranchAsWorktree(repo: GitRepository, branch: String, path: String) async throws {
        checkoutBranchAsWorktreeCalled = true
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

    func deleteLocalBranch(repoPath: String, branch: String) async throws {
        deleteLocalBranchCalls.append(branch)
    }

    func defaultBranch(repoPath: String) async -> String { defaultBranchResult }

    func updateRemoteHead(repoPath: String) async {
        updateRemoteHeadCalled = true
    }

    func inferRepoName(repoPath: String) async -> String { inferRepoNameResult }
}

@MainActor
final class MockRepoPersistence: RepoPersistenceProtocol {
    var config = RepoConfig(repositories: [])
    var saveError: Error?
    private(set) var saveCalled = false

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
        persistence: MockRepoPersistence = MockRepoPersistence()
    ) -> WorktreeSidebarViewModel {
        WorktreeSidebarViewModel(gitService: gitService, persistence: persistence)
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

    // MARK: - checkoutBranchAsWorktree

    func testCheckoutBranchAsWorktree_callsGitService() async throws {
        let mock = MockGitService()
        let vm = makeVM(gitService: mock)
        let repo = makeRepo()

        try await vm.checkoutBranchAsWorktree(
            repo: repo, branch: "feat/existing", path: "/tmp/wt")

        XCTAssertTrue(mock.checkoutBranchAsWorktreeCalled)
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

        XCTAssertTrue(mock.updateRemoteHeadCalled)
        XCTAssertEqual(vm.worktrees[repo.id]?.count, 1)
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
}
