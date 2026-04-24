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
    var forceDeleteWorktreeError: Error?
    var pruneWorktreesError: Error?
    var pullBranchError: Error?
    var fetchBranchError: Error?
    var inferRepoNameResult: String = "mock-repo"

    private(set) var forceDeleteWorktreeCalled = false
    private(set) var pruneWorktreesCalled = false
    private(set) var isGitRepoCalled = false

    func isGitRepo(path: String) async throws -> Bool {
        isGitRepoCalled = true
        if let error = isGitRepoError { throw error }
        return isGitRepoResult
    }

    func listWorktrees(repoPath: String) async throws -> [GitWorktree] {
        if let error = listWorktreesError { throw error }
        return listWorktreesResult
    }

    func addWorktree(repo: GitRepository, branch: String, path: String, baseBranch: String?) async throws {}
    func removeWorktree(repo: GitRepository, path: String) async throws {}
    func checkoutBranchAsWorktree(repo: GitRepository, branch: String, path: String) async throws {}

    func forceDeleteWorktree(repoPath: String, worktreePath: String) async throws {
        forceDeleteWorktreeCalled = true
        if let error = forceDeleteWorktreeError { throw error }
    }

    func lockWorktree(repoPath: String, worktreePath: String) async throws {}
    func unlockWorktree(repoPath: String, worktreePath: String) async throws {}
    func pruneWorktreesDryRun(repoPath: String) async throws -> [String] { [] }

    func pruneWorktrees(repoPath: String) async throws {
        pruneWorktreesCalled = true
        if let error = pruneWorktreesError { throw error }
    }

    func listBranches(repoPath: String) async throws -> [String] { listBranchesResult }
    func mergedLocalBranches(repoPath: String) async throws -> [String] { [] }
    func deleteLocalBranch(repoPath: String, branch: String) async throws {}
    func forceDeleteLocalBranch(repoPath: String, branch: String) async throws {}
    func fetchBranchFromOrigin(repoPath: String, branch: String) async throws {
        if let error = fetchBranchError { throw error }
    }
    func pullBranch(worktreePath: String) async throws {
        if let error = pullBranchError { throw error }
    }
    func defaultBranch(repoPath: String) async -> String { "main" }
    func updateRemoteHead(repoPath: String) async {}
    func inferRepoName(repoPath: String) async -> String { inferRepoNameResult }
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
}
