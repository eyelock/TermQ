import TermQShared
import XCTest

@testable import TermQ

// MARK: - Fake Provider

/// In-memory `StackProvider` double. Lets `StackService` be tested against the neutral
/// protocol without a live `gs` binary, matching the "unit-test the mapping with fixture
/// data" approach used for `GitSpiceStackProviderTests`.
actor FakeStackProvider: StackProvider {
    static let id = StackProviderID(rawValue: "fake")

    nonisolated var capabilities: StackCapabilities { [.restack, .submit, .sync] }

    var availability: StackProviderAvailability = .ready(version: "0.0.0")
    var initializedRepos: Set<String> = []
    var graphs: [String: StackGraph] = [:]
    var initializeCalls: [(repo: String, trunk: String)] = []
    var initializeError: Error?

    func probe() async -> StackProviderAvailability { availability }

    func isInitialized(repo: String) async -> Bool { initializedRepos.contains(repo) }

    func initialize(repo: String, trunk: String) async throws {
        initializeCalls.append((repo, trunk))
        if let initializeError { throw initializeError }
        initializedRepos.insert(repo)
        // A freshly initialized repo has a valid (empty) graph, like real gs.
        if graphs[repo] == nil {
            graphs[repo] = StackGraph(branches: [])
        }
    }

    func graph(repo: String) async throws -> StackGraph {
        guard let graph = graphs[repo] else {
            throw StackProviderError.notInitialized(repo: repo)
        }
        return graph
    }

    /// Ordered log of mutation invocations, e.g. "create:feat-b:target=feat-a".
    var mutationLog: [String] = []
    var mutationError: Error?
    var pausedOperationResult: StackPausedOperation?
    /// Artificial per-mutation delay (nanoseconds) to expose serialization races.
    var mutationDelayNs: UInt64 = 0
    /// Count of mutations currently inside `record` — >1 means serialization is broken.
    var concurrentMutations = 0
    var maxConcurrentMutations = 0

    private func record(_ entry: String) async throws {
        concurrentMutations += 1
        maxConcurrentMutations = max(maxConcurrentMutations, concurrentMutations)
        defer { concurrentMutations -= 1 }
        if mutationDelayNs > 0 {
            try? await Task.sleep(nanoseconds: mutationDelayNs)
        }
        mutationLog.append(entry)
        if let mutationError { throw mutationError }
    }

    func createBranch(name: String, target: String?, in worktree: String) async throws {
        try await record("create:\(name):target=\(target ?? "nil")")
    }

    func trackBranch(_ name: String, base: String, in worktree: String) async throws {
        try await record("track:\(name):base=\(base)")
    }

    func switchBranch(to name: String, in worktree: String) async throws {
        try await record("switch:\(name)")
    }

    /// When true (default), a single-branch restack clears that branch's needsRestack
    /// flag in the stored graphs — modeling a successful real restack so orchestration
    /// sweeps converge. Disable to model a branch that never converges (sweep-cap test).
    var clearsNeedsRestackOnBranchRestack = true

    func restack(scope: StackScope, in worktree: String) async throws {
        try await record("restack:\(scope):in=\(worktree)")
        guard clearsNeedsRestackOnBranchRestack, case .branch(let name) = scope else { return }
        for (repo, graph) in graphs {
            let updated = graph.branches.map { branch -> StackBranch in
                guard branch.name == name else { return branch }
                return StackBranch(
                    name: branch.name, isCurrent: branch.isCurrent,
                    checkedOutElsewhere: branch.checkedOutElsewhere, parent: branch.parent,
                    children: branch.children, needsRestack: false,
                    changeRequest: branch.changeRequest, push: branch.push)
            }
            graphs[repo] = StackGraph(branches: updated)
        }
    }

    func submit(scope: StackScope, options: StackSubmitOptions, in worktree: String) async throws {
        try await record("submit:\(scope)")
    }

    func sync(repo: String) async throws {
        try await record("sync")
    }

    func continueOperation(in worktree: String) async throws {
        try await record("continue")
    }

    func abortOperation(in worktree: String) async throws {
        try await record("abort")
    }

    func pausedOperation(repo: String) async -> StackPausedOperation? { pausedOperationResult }

    func destroyStack(in worktree: String) async throws {
        try await record("destroy:in=\(worktree)")
    }

    // MARK: - Test helpers

    func setAvailability(_ availability: StackProviderAvailability) {
        self.availability = availability
    }

    func setGraph(_ graph: StackGraph, for repo: String) {
        graphs[repo] = graph
        initializedRepos.insert(repo)
    }

    func setInitializeError(_ error: Error?) {
        initializeError = error
    }

    /// Mark the repo initialized without providing a graph — `graph()` will throw
    /// `.notInitialized`, modeling the race where state changes between check and fetch.
    func setInitializedWithoutGraph(_ repo: String) {
        initializedRepos.insert(repo)
    }

    func setMutationError(_ error: Error?) {
        mutationError = error
    }

    func setPausedOperationResult(_ paused: StackPausedOperation?) {
        pausedOperationResult = paused
    }

    func setMutationDelayNs(_ delay: UInt64) {
        mutationDelayNs = delay
    }

    func setClearsNeedsRestackOnBranchRestack(_ value: Bool) {
        clearsNeedsRestackOnBranchRestack = value
    }
}

// MARK: - Tests

@MainActor
final class StackServiceTests: XCTestCase {
    private func makeGraph(branchName: String = "feat-a") -> StackGraph {
        StackGraph(
            branches: [
                StackBranch(
                    name: branchName, isCurrent: true, checkedOutElsewhere: nil, parent: nil,
                    children: [], needsRestack: false, changeRequest: nil, push: nil)
            ])
    }

    func testProbe_missingProvider_resultsInMissingAvailability() async {
        let registry = StackProviderRegistry(providers: [])
        let service = StackService(registry: registry)
        await service.probe()
        XCTAssertEqual(service.availability, .missing)
        XCTAssertFalse(service.isAvailable)
    }

    func testProbe_readyProvider_resultsInReadyAvailability() async {
        let fake = FakeStackProvider()
        let registry = StackProviderRegistry(providers: [fake])
        let service = StackService(registry: registry)
        await service.probe()
        XCTAssertTrue(service.isAvailable)
        XCTAssertEqual(service.availability, .ready(version: "0.0.0"))
    }

    func testProbe_unusableProvider_isNotAvailable() async {
        let fake = FakeStackProvider()
        await fake.setAvailability(.unusable(reason: "wrong binary"))
        let registry = StackProviderRegistry(providers: [fake])
        let service = StackService(registry: registry)
        await service.probe()
        XCTAssertFalse(service.isAvailable)
    }

    func testRefreshGraph_beforeProbe_noProviderActive_clearsState() async {
        let service = StackService(registry: StackProviderRegistry(providers: []))
        await service.refreshGraph(repo: "/repo")
        XCTAssertNil(service.graphsByRepo["/repo"])
        XCTAssertFalse(service.isStacked(repo: "/repo"))
    }

    func testRefreshGraph_notInitializedRepo_leavesGraphAbsent() async {
        let fake = FakeStackProvider()
        let service = StackService(registry: StackProviderRegistry(providers: [fake]))
        await service.probe()
        await service.refreshGraph(repo: "/repo")
        XCTAssertNil(service.graphsByRepo["/repo"])
        XCTAssertFalse(service.isStacked(repo: "/repo"))
    }

    func testRefreshGraph_notInitializedRepo_recordsNoError() async {
        // Regression: an uninitialized repo is a normal state — polling it must not
        // accumulate error entries (which previously drove per-repo warning spam).
        let fake = FakeStackProvider()
        let service = StackService(registry: StackProviderRegistry(providers: [fake]))
        await service.probe()
        for _ in 0..<3 {
            await service.refreshGraph(repo: "/repo")
        }
        XCTAssertNil(service.errorByRepo["/repo"])
    }

    func testRefreshGraph_graphThrowsNotInitialized_treatedAsUninitializedNotError() async {
        // The check-then-fetch race: isInitialized says yes, graph() then reports
        // notInitialized. Must clear state silently rather than record an error.
        let fake = FakeStackProvider()
        await fake.setInitializedWithoutGraph("/repo")
        let service = StackService(registry: StackProviderRegistry(providers: [fake]))
        await service.probe()
        await service.refreshGraph(repo: "/repo")
        XCTAssertNil(service.errorByRepo["/repo"])
        XCTAssertFalse(service.isStacked(repo: "/repo"))
        XCTAssertNil(service.graphsByRepo["/repo"])
    }

    func testRefreshGraph_initializedRepo_populatesGraph() async {
        let fake = FakeStackProvider()
        await fake.setGraph(makeGraph(), for: "/repo")
        let service = StackService(registry: StackProviderRegistry(providers: [fake]))
        await service.probe()
        await service.refreshGraph(repo: "/repo")
        XCTAssertTrue(service.isStacked(repo: "/repo"))
        XCTAssertEqual(service.graphsByRepo["/repo"]?.branches.map(\.name), ["feat-a"])
    }

    func testEnableStacking_callsProviderInitializeWithDefaultBranch() async throws {
        let fake = FakeStackProvider()
        let service = StackService(registry: StackProviderRegistry(providers: [fake]))
        await service.probe()
        try await service.enableStacking(repo: "/repo", trunk: "main")
        let calls = await fake.initializeCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.repo, "/repo")
        XCTAssertEqual(calls.first?.trunk, "main")
        XCTAssertTrue(service.isStacked(repo: "/repo"))
    }

    func testEnableStacking_noProviderActive_throwsBinaryMissing() async {
        let service = StackService(registry: StackProviderRegistry(providers: []))
        await service.probe()
        do {
            try await service.enableStacking(repo: "/repo", trunk: "main")
            XCTFail("Expected binaryMissing to be thrown")
        } catch StackProviderError.binaryMissing {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnableStacking_providerThrows_propagatesError() async {
        let fake = FakeStackProvider()
        await fake.setInitializeError(
            StackProviderError.commandFailed(command: "gs repo init", exitCode: 1, output: "boom"))
        let service = StackService(registry: StackProviderRegistry(providers: [fake]))
        await service.probe()
        do {
            try await service.enableStacking(repo: "/repo", trunk: "main")
            XCTFail("Expected error to propagate")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("boom"))
        }
    }

    // MARK: - Mutations

    private func makeReadyService(_ fake: FakeStackProvider) async -> StackService {
        let service = StackService(registry: StackProviderRegistry(providers: [fake]))
        await service.probe()
        return service
    }

    func testSwitchBranch_invokesProvider() async throws {
        let fake = FakeStackProvider()
        let service = await makeReadyService(fake)
        try await service.switchBranch(repo: "/repo", worktree: "/repo/wt", to: "feat-b")
        let log = await fake.mutationLog
        XCTAssertEqual(log, ["switch:feat-b"])
        XCTAssertFalse(service.isMutating(repo: "/repo"))
    }

    func testMutation_noProviderActive_throwsBinaryMissing() async {
        let service = StackService(registry: StackProviderRegistry(providers: []))
        await service.probe()
        do {
            try await service.restack(repo: "/repo", worktree: "/repo/wt", scope: .stack)
            XCTFail("Expected binaryMissing")
        } catch StackProviderError.binaryMissing {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMutations_serializePerRepo() async throws {
        let fake = FakeStackProvider()
        await fake.setMutationDelayNs(50_000_000)  // 50 ms inside each mutation
        let service = await makeReadyService(fake)

        async let first: Void = service.restack(repo: "/repo", worktree: "/repo/wt", scope: .stack)
        async let second: Void = service.switchBranch(repo: "/repo", worktree: "/repo/wt", to: "feat-b")
        _ = try await (first, second)

        let maxConcurrent = await fake.maxConcurrentMutations
        XCTAssertEqual(maxConcurrent, 1, "mutations for the same repo must not overlap")
        let log = await fake.mutationLog
        XCTAssertEqual(log.count, 2)
    }

    func testMutation_failureWithPausedOperation_entersConflictStateWithoutThrowing() async throws {
        let fake = FakeStackProvider()
        await fake.setMutationError(
            StackProviderError.commandFailed(command: "gs stack restack", exitCode: 1, output: "conflict"))
        await fake.setPausedOperationResult(
            StackPausedOperation(kind: .restack, conflictedFiles: ["a.swift", "b.swift"]))
        let service = await makeReadyService(fake)

        try await service.restack(repo: "/repo", worktree: "/repo/wt", scope: .stack)

        let conflict = service.conflict(repo: "/repo")
        XCTAssertNotNil(conflict)
        XCTAssertEqual(conflict?.worktree, "/repo/wt")
        XCTAssertEqual(conflict?.operation.conflictedFiles.count, 2)
        XCTAssertFalse(service.isMutating(repo: "/repo"))
    }

    func testMutation_failureWithoutPausedOperation_throws() async {
        let fake = FakeStackProvider()
        await fake.setMutationError(
            StackProviderError.commandFailed(command: "gs branch checkout", exitCode: 1, output: "boom"))
        let service = await makeReadyService(fake)

        do {
            try await service.switchBranch(repo: "/repo", worktree: "/repo/wt", to: "feat-b")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("boom"))
        }
        XCTAssertNil(service.conflict(repo: "/repo"))
    }

    func testContinuePaused_success_clearsConflict() async throws {
        let fake = FakeStackProvider()
        await fake.setMutationError(
            StackProviderError.commandFailed(command: "gs stack restack", exitCode: 1, output: "conflict"))
        await fake.setPausedOperationResult(
            StackPausedOperation(kind: .restack, conflictedFiles: ["a.swift"]))
        let service = await makeReadyService(fake)
        try await service.restack(repo: "/repo", worktree: "/repo/wt", scope: .stack)
        XCTAssertNotNil(service.conflict(repo: "/repo"))

        // User resolved; continue now succeeds and no rebase remains in progress.
        await fake.setMutationError(nil)
        await fake.setPausedOperationResult(nil)
        try await service.continuePaused(repo: "/repo", worktree: "/repo/wt")

        XCTAssertNil(service.conflict(repo: "/repo"))
        let log = await fake.mutationLog
        XCTAssertEqual(log.last, "continue")
    }

    func testContinuePaused_furtherConflict_reentersPausedState() async throws {
        let fake = FakeStackProvider()
        await fake.setMutationError(
            StackProviderError.commandFailed(command: "gs rebase continue", exitCode: 1, output: "conflict"))
        await fake.setPausedOperationResult(
            StackPausedOperation(kind: .restack, conflictedFiles: ["c.swift"]))
        let service = await makeReadyService(fake)

        try await service.continuePaused(repo: "/repo", worktree: "/repo/wt")

        XCTAssertEqual(service.conflict(repo: "/repo")?.operation.conflictedFiles, ["c.swift"])
    }

    func testAbortPaused_clearsConflict() async throws {
        let fake = FakeStackProvider()
        await fake.setMutationError(
            StackProviderError.commandFailed(command: "gs stack restack", exitCode: 1, output: "conflict"))
        await fake.setPausedOperationResult(
            StackPausedOperation(kind: .restack, conflictedFiles: ["a.swift"]))
        let service = await makeReadyService(fake)
        try await service.restack(repo: "/repo", worktree: "/repo/wt", scope: .stack)
        XCTAssertNotNil(service.conflict(repo: "/repo"))

        await fake.setMutationError(nil)
        await fake.setPausedOperationResult(nil)
        try await service.abortPaused(repo: "/repo", worktree: "/repo/wt")

        XCTAssertNil(service.conflict(repo: "/repo"))
        let log = await fake.mutationLog
        XCTAssertEqual(log.last, "abort")
    }

    func testSubmit_invokesProviderWithScopeAndOptions() async throws {
        let fake = FakeStackProvider()
        let service = await makeReadyService(fake)
        try await service.submit(
            repo: "/repo", worktree: "/repo/wt", scope: .stack,
            options: StackSubmitOptions(draft: true, updateOnly: false))
        let log = await fake.mutationLog
        XCTAssertEqual(log, ["submit:stack"])
    }

    func testSync_invokesProvider() async throws {
        let fake = FakeStackProvider()
        let service = await makeReadyService(fake)
        try await service.sync(repo: "/repo", worktree: "/repo/wt")
        let log = await fake.mutationLog
        XCTAssertEqual(log, ["sync"])
        XCTAssertFalse(service.isMutating(repo: "/repo"))
    }

    func testDestroyStack_invokesProvider() async throws {
        let fake = FakeStackProvider()
        let service = await makeReadyService(fake)
        try await service.destroyStack(repo: "/repo", worktree: "/repo/wt")
        let log = await fake.mutationLog
        XCTAssertEqual(log, ["destroy:in=/repo/wt"])
        XCTAssertFalse(service.isMutating(repo: "/repo"))
    }

    func testEvict_removesCachedStateForRepo() async {
        let fake = FakeStackProvider()
        await fake.setGraph(makeGraph(), for: "/repo")
        let service = StackService(registry: StackProviderRegistry(providers: [fake]))
        await service.probe()
        await service.refreshGraph(repo: "/repo")
        XCTAssertTrue(service.isStacked(repo: "/repo"))

        service.evict(repo: "/repo")
        XCTAssertFalse(service.isStacked(repo: "/repo"))
        XCTAssertNil(service.graphsByRepo["/repo"])
    }
}
