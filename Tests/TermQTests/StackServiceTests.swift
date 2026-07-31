import TermQShared
import XCTest

@testable import TermQ

// MARK: - Fake Provider

/// In-memory `StackProvider` double. Lets `StackService` be tested against the neutral
/// protocol without a live `gs` binary, matching the "unit-test the mapping with fixture
/// data" approach used for `GitSpiceStackProviderTests`.
actor FakeStackProvider: StackProvider {
    static let id = StackProviderID(rawValue: "fake")

    /// Per-instance identity, so a test can register two distinguishable providers and
    /// assert which one a given repo resolved to.
    nonisolated let overrideID: StackProviderID
    nonisolated var providerID: StackProviderID { overrideID }

    nonisolated let overrideCapabilities: StackCapabilities
    nonisolated var capabilities: StackCapabilities { overrideCapabilities }

    init(
        id: StackProviderID = StackProviderID(rawValue: "fake"),
        // Default stands in for a fully-scoped provider (git-spice's shape): the
        // cross-worktree sweep and the per-branch menu items all require .scopedRestack /
        // .scopedSubmit, and most tests here exercise those paths. Tests covering a
        // provider that only handles whole stacks pass an explicit narrower set.
        capabilities: StackCapabilities = [
            .restack, .submit, .sync, .scopedRestack, .scopedSubmit,
        ]
    ) {
        self.overrideID = id
        self.overrideCapabilities = capabilities
    }

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

    /// Drop the repo's initialization evidence, modeling an untrack (or the tool's state
    /// being removed out from under TermQ).
    func setInitialized(_ initialized: Bool, for repo: String) {
        if initialized {
            initializedRepos.insert(repo)
        } else {
            initializedRepos.remove(repo)
        }
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

// MARK: - Capability gating

/// The sidebar offers actions per the ACTIVE provider's capabilities, not per
/// "stacking is available". These rules guard two traps rather than mere feature gaps.
@MainActor
final class StackProviderOptionTests: XCTestCase {
    private func options(
        gitSpice: StackProviderAvailability, gitHub: StackProviderAvailability
    ) -> [StackProviderOption] {
        StackProviderOption.options { id in
            switch id {
            case .gitSpice: return gitSpice
            case .gitHub: return gitHub
            default: return .missing
            }
        }
    }

    func testAutomatic_isAlwaysSelectable() {
        // "Let resolution decide" stays meaningful even with nothing installed — the
        // stacking section is still reachable, and the setting still records intent.
        let all = options(gitSpice: .missing, gitHub: .missing)
        XCTAssertTrue(all.first { $0.preference == .automatic }?.isSelectable ?? false)
    }

    func testUninstalledBackend_isNotSelectable_andSaysWhy() {
        // Resolution only considers ready providers, so picking a missing one silently
        // does nothing. A control that accepts a choice and ignores it is worse than one
        // that refuses and explains.
        let all = options(gitSpice: .ready(version: "0.31.0"), gitHub: .missing)
        let gitHub = all.first { $0.preference == .gitHub }
        XCTAssertEqual(gitHub?.isSelectable, false)
        XCTAssertTrue(gitHub?.label.contains(Strings.Settings.notInstalled) ?? false)

        let gitSpice = all.first { $0.preference == .gitSpice }
        XCTAssertEqual(gitSpice?.isSelectable, true)
        XCTAssertEqual(gitSpice?.label, "git-spice", "an available backend is named plainly")
    }

    func testUnusableBackend_isTreatedAsUnselectable() {
        // Installed but unauthenticated gh cannot own a repository either, so it must not
        // present as a working choice.
        let all = options(
            gitSpice: .missing, gitHub: .unusable(reason: "gh is not authenticated"))
        XCTAssertEqual(all.first { $0.preference == .gitHub }?.isSelectable, false)
    }

    func testEveryBackendKeepsItsRow_soASelectedOneNeverVanishes() {
        // The setting may already name a backend that has since been uninstalled.
        // Dropping its row would redraw the picker as Automatic and misreport what
        // happens if the tool reappears.
        XCTAssertEqual(options(gitSpice: .missing, gitHub: .missing).count, 3)
    }
}

final class StackActionAvailabilityTests: XCTestCase {
    /// What git-spice advertises today.
    private let gitSpice = StackActionAvailability(
        capabilities: [
            .restack, .submit, .sync, .trackExisting, .conflictResume, .branchInsertion,
            .destroyStack, .scopedRestack, .scopedSubmit,
        ])
    /// What gh-stack advertises today.
    private let gitHub = StackActionAvailability(
        capabilities: [
            .restack, .submit, .sync, .syncPushes, .conflictResume, .untrackStack, .mergeStack,
            .remoteDiscovery, .linkExisting,
        ])

    func testNone_offersNothing() {
        // A repo with no resolved provider must show no stack actions at all.
        let none = StackActionAvailability.none
        XCTAssertFalse(none.canRestack)
        XCTAssertFalse(none.canSubmit)
        XCTAssertFalse(none.canSync)
        XCTAssertFalse(none.canInsertBranch)
        XCTAssertFalse(none.canDestroyStack)
        XCTAssertFalse(none.canUntrackStack)
        XCTAssertFalse(none.canResumeConflict)
        XCTAssertFalse(none.syncNeedsConfirmation)
    }

    func testDestroyAndUntrack_areNeverImpliedByEachOther() {
        // The trap: the two actions look alike and have opposite blast radius.
        // git-spice's `stack delete` removes every branch; gh-stack's `unstack` leaves
        // them all in place. Neither flag may ever be inferred from the other.
        XCTAssertTrue(gitSpice.canDestroyStack)
        XCTAssertFalse(gitSpice.canUntrackStack)

        XCTAssertFalse(gitHub.canDestroyStack)
        XCTAssertTrue(gitHub.canUntrackStack)
    }

    func testBranchInsertion_gitSpiceOnly() {
        // gh-stack can only restructure inside its interactive `modify` TUI, which TermQ
        // must never spawn — so Before/After disappear rather than failing at click time.
        XCTAssertTrue(gitSpice.canInsertBranch)
        XCTAssertFalse(gitHub.canInsertBranch)
    }

    func testSyncConfirmation_onlyWhenSyncReachesTheRemote() {
        // gh-stack's sync force-pushes every branch and mutates the stack on GitHub;
        // git-spice's is local-only. A one-click Sync is only safe for the latter.
        XCTAssertFalse(gitSpice.syncNeedsConfirmation)
        XCTAssertTrue(gitHub.syncNeedsConfirmation)
        XCTAssertTrue(gitSpice.canSync)
        XCTAssertTrue(gitHub.canSync)
    }

    func testSyncNeedsConfirmation_isIndependentOfCanSync() {
        // Defensive: .syncPushes without .sync must not present as a runnable action.
        let odd = StackActionAvailability(capabilities: [.syncPushes])
        XCTAssertFalse(odd.canSync)
        XCTAssertTrue(odd.syncNeedsConfirmation)
    }

    func testScopedOperations_requireTheUnscopedFormToo() {
        // A conjunction, not a standalone flag: scoping a restack the provider cannot
        // perform is meaningless, and reading .scopedRestack alone would offer
        // "Restack from Here" to a provider with no restack at all.
        let scopedOnly = StackActionAvailability(capabilities: [.scopedRestack, .scopedSubmit])
        XCTAssertFalse(scopedOnly.canRestackNamedBranch)
        XCTAssertFalse(scopedOnly.canSubmitNamedBranch)
    }

    func testNamedBranchOperations_gitSpiceOnly() {
        // git-spice targets --branch=NAME; gh-stack's rebase pivots on HEAD and its
        // submit covers the whole stack. Offering the named-branch actions to gh-stack
        // would rebase a different range than the menu item claims.
        XCTAssertTrue(gitSpice.canRestackNamedBranch)
        XCTAssertTrue(gitSpice.canSubmitNamedBranch)
        XCTAssertFalse(gitHub.canRestackNamedBranch)
        XCTAssertFalse(gitHub.canSubmitNamedBranch)
    }

    func testOperatesOnCheckedOutStack_decidesTheWorkingDirectory() {
        // Drives which worktree a group-level mutation runs in: git-spice resolves the
        // stack from the branch name and can run from the main worktree; gh-stack must
        // run where one of the stack's branches is actually checked out.
        XCTAssertFalse(gitSpice.operatesOnCheckedOutStack)
        XCTAssertTrue(gitHub.operatesOnCheckedOutStack)
        XCTAssertTrue(StackActionAvailability.none.operatesOnCheckedOutStack)
    }

    func testSharedActions_offeredByBothProviders() {
        for availability in [gitSpice, gitHub] {
            XCTAssertTrue(availability.canRestack)
            XCTAssertTrue(availability.canSubmit)
            XCTAssertTrue(availability.canResumeConflict)
        }
    }

    func testEachFlagTracksExactlyItsOwnCapability() {
        XCTAssertTrue(StackActionAvailability(capabilities: [.restack]).canRestack)
        XCTAssertFalse(StackActionAvailability(capabilities: [.submit]).canRestack)
        XCTAssertTrue(StackActionAvailability(capabilities: [.conflictResume]).canResumeConflict)
        XCTAssertFalse(StackActionAvailability(capabilities: [.restack]).canResumeConflict)
    }
}

// MARK: - Per-repo provider resolution

/// With two providers installed they own different repositories. A single app-wide
/// `activeProvider` would hand every repo to whichever probed first — and because an
/// uninitialized repo is a deliberately silent state, repos owned by the other tool
/// would report "not stacked" with no warning at all.
/// Mutable preference holder for the resolution tests.
///
/// `StackService` takes its preference as an escaping `@Sendable` closure, so capturing a
/// local `var` and mutating it afterwards is a data race the compiler rightly warns
/// about. A `@MainActor` reference box gives the tests the same "flip it and re-read"
/// shape with the mutation properly isolated.
@MainActor
final class PreferenceBox {
    var value: PreferredStackProvider
    init(_ value: PreferredStackProvider) { self.value = value }
}

@MainActor
final class StackServiceProviderResolutionTests: XCTestCase {
    private let spiceID = StackProviderID.gitSpice
    private let githubID = StackProviderID.gitHub

    private func makeGraph(_ name: String) -> StackGraph {
        StackGraph(
            branches: [
                StackBranch(
                    name: name, isCurrent: true, checkedOutElsewhere: nil, parent: nil,
                    children: [], needsRestack: false, changeRequest: nil, push: nil)
            ])
    }

    func testRefreshGraph_resolvesEachRepoToItsOwningProvider() async {
        let spice = FakeStackProvider(id: spiceID)
        let github = FakeStackProvider(id: githubID)
        await spice.setGraph(makeGraph("spice-branch"), for: "/spice-repo")
        await github.setGraph(makeGraph("github-branch"), for: "/github-repo")

        let service = StackService(registry: StackProviderRegistry(providers: [spice, github]))
        await service.probe()
        await service.refreshGraph(repo: "/spice-repo")
        await service.refreshGraph(repo: "/github-repo")

        XCTAssertEqual(service.providerIDByRepo["/spice-repo"], spiceID)
        XCTAssertEqual(service.providerIDByRepo["/github-repo"], githubID)
        XCTAssertEqual(service.graphsByRepo["/spice-repo"]?.branches.first?.name, "spice-branch")
        XCTAssertEqual(service.graphsByRepo["/github-repo"]?.branches.first?.name, "github-branch")
    }

    func testMutation_runsAgainstTheProviderThatOwnsTheRepo() async throws {
        let spice = FakeStackProvider(id: spiceID)
        let github = FakeStackProvider(id: githubID)
        await spice.setGraph(makeGraph("a"), for: "/spice-repo")
        await github.setGraph(makeGraph("b"), for: "/github-repo")

        let service = StackService(registry: StackProviderRegistry(providers: [spice, github]))
        await service.probe()
        try await service.submit(
            repo: "/github-repo", worktree: "/github-repo/wt", scope: .stack,
            options: StackSubmitOptions())

        let spiceLog = await spice.mutationLog
        let githubLog = await github.mutationLog
        XCTAssertTrue(spiceLog.isEmpty, "mutation must not reach the non-owning provider")
        XCTAssertEqual(githubLog, ["submit:stack"])
    }

    func testResolution_evidenceBeatsPreference() async {
        let spice = FakeStackProvider(id: spiceID)
        let github = FakeStackProvider(id: githubID)
        await spice.setGraph(makeGraph("a"), for: "/repo")

        let service = StackService(
            registry: StackProviderRegistry(providers: [spice, github]),
            preference: { .gitHub })
        await service.probe()
        await service.refreshGraph(repo: "/repo")

        XCTAssertEqual(service.providerIDByRepo["/repo"], spiceID)
    }

    func testEnableStacking_uninitializedRepo_usesPreferredProvider() async throws {
        let spice = FakeStackProvider(id: spiceID)
        let github = FakeStackProvider(id: githubID)
        let service = StackService(
            registry: StackProviderRegistry(providers: [spice, github]),
            preference: { .gitHub })
        await service.probe()

        try await service.enableStacking(repo: "/fresh", trunk: "develop")

        let spiceCalls = await spice.initializeCalls
        let githubCalls = await github.initializeCalls
        XCTAssertTrue(spiceCalls.isEmpty)
        XCTAssertEqual(githubCalls.count, 1)
        XCTAssertEqual(githubCalls.first?.trunk, "develop")
    }

    func testProbe_keepsResolutionThatStillHolds() async {
        // The cache is what `capabilities(forRepo:)` answers from, and the sidebar gates
        // every stack action on it. Clearing it on each re-probe would read as "this
        // provider can do nothing" and blank the stack menus until some later refresh.
        let spice = FakeStackProvider(id: spiceID)
        await spice.setGraph(makeGraph("a"), for: "/repo")
        let service = StackService(registry: StackProviderRegistry(providers: [spice]))
        await service.probe()
        await service.refreshGraph(repo: "/repo")
        XCTAssertEqual(service.providerIDByRepo["/repo"], spiceID)

        await service.probe()

        XCTAssertEqual(service.providerIDByRepo["/repo"], spiceID)
        XCTAssertFalse(
            service.capabilities(forRepo: "/repo").isEmpty,
            "a re-probe must not make a still-valid provider look capability-less")
    }

    func testProbe_dropsResolutionWhenTheProviderIsNoLongerReady() async {
        // The uninstall case: the cached owner must not keep answering for the repo.
        let spice = FakeStackProvider(id: spiceID)
        await spice.setGraph(makeGraph("a"), for: "/repo")
        let service = StackService(registry: StackProviderRegistry(providers: [spice]))
        await service.probe()
        await service.refreshGraph(repo: "/repo")
        XCTAssertEqual(service.providerIDByRepo["/repo"], spiceID)

        await spice.setAvailability(.missing)
        await service.probe()

        XCTAssertNil(service.providerIDByRepo["/repo"])
        XCTAssertTrue(service.capabilities(forRepo: "/repo").isEmpty)
    }

    func testProbe_dropsResolutionWhenTheRepoLosesItsEvidence() async {
        // Untracking a stack removes the provider's claim, which is what lets a newly
        // installed second provider pick the repo up on the next resolution.
        let spice = FakeStackProvider(id: spiceID)
        await spice.setGraph(makeGraph("a"), for: "/repo")
        let service = StackService(registry: StackProviderRegistry(providers: [spice]))
        await service.probe()
        await service.refreshGraph(repo: "/repo")
        XCTAssertEqual(service.providerIDByRepo["/repo"], spiceID)

        await spice.setInitialized(false, for: "/repo")
        await service.probe()

        XCTAssertNil(service.providerIDByRepo["/repo"])
    }

    func testPreference_isReadThroughOnEveryResolution() async {
        // Read through rather than cached: flipping the setting must take effect without
        // anything having to push the new value into the service.
        let preference = PreferenceBox(.gitSpice)
        let service = StackService(
            registry: StackProviderRegistry(providers: []), preference: { preference.value })
        XCTAssertEqual(service.preferredProviderID, spiceID)

        preference.value = .gitHub
        XCTAssertEqual(service.preferredProviderID, githubID)

        preference.value = .automatic
        XCTAssertNil(service.preferredProviderID, "automatic means registry order, not a provider")
    }

    func testPreferenceChange_keepsRepositoriesTheirEvidenceOwns() async {
        // A repo already stacked with one tool must not be handed to the other because a
        // preference changed — evidence beats preference, always.
        let spice = FakeStackProvider(id: spiceID)
        let github = FakeStackProvider(id: githubID)
        await spice.setGraph(makeGraph("a"), for: "/repo")
        let preference = PreferenceBox(.automatic)
        let service = StackService(
            registry: StackProviderRegistry(providers: [spice, github]),
            preference: { preference.value })
        await service.probe()
        await service.refreshGraph(repo: "/repo")
        XCTAssertEqual(service.providerIDByRepo["/repo"], spiceID)

        preference.value = .gitHub
        await service.preferredProviderDidChange()

        XCTAssertEqual(service.providerIDByRepo["/repo"], spiceID)
    }

    func testPreferenceChange_reresolvesRepositoriesDecidedByFallback() async {
        // The other half: a repo nothing has claimed was resolved by preference/order, so
        // it must be re-resolved when the preference moves.
        let spice = FakeStackProvider(id: spiceID)
        let github = FakeStackProvider(id: githubID)
        let preference = PreferenceBox(.gitSpice)
        let service = StackService(
            registry: StackProviderRegistry(providers: [spice, github]),
            preference: { preference.value })
        await service.probe()
        try? await service.enableStacking(repo: "/fresh", trunk: "develop")
        XCTAssertEqual(service.providerIDByRepo["/fresh"], spiceID)

        // `enableStacking` gave the repo evidence, so drop it to model the
        // never-initialized case the fallback path actually covers.
        await spice.setInitialized(false, for: "/fresh")
        preference.value = .gitHub
        await service.preferredProviderDidChange()

        XCTAssertNil(service.providerIDByRepo["/fresh"])
    }

    func testCapabilities_reportTheOwningProvidersFeatureSet() async {
        let spice = FakeStackProvider(id: spiceID, capabilities: [.restack, .destroyStack])
        let github = FakeStackProvider(id: githubID, capabilities: [.restack, .untrackStack, .syncPushes])
        await spice.setGraph(makeGraph("a"), for: "/spice-repo")
        await github.setGraph(makeGraph("b"), for: "/github-repo")

        let service = StackService(registry: StackProviderRegistry(providers: [spice, github]))
        await service.probe()
        await service.refreshGraph(repo: "/spice-repo")
        await service.refreshGraph(repo: "/github-repo")

        XCTAssertTrue(service.capabilities(forRepo: "/spice-repo").contains(.destroyStack))
        XCTAssertFalse(service.capabilities(forRepo: "/spice-repo").contains(.untrackStack))
        XCTAssertTrue(service.capabilities(forRepo: "/github-repo").contains(.untrackStack))
        XCTAssertFalse(service.capabilities(forRepo: "/github-repo").contains(.destroyStack))
        // Sync force-pushes for one provider and not the other — the flag is what tells
        // the UI whether to confirm first.
        XCTAssertTrue(service.capabilities(forRepo: "/github-repo").contains(.syncPushes))
        XCTAssertFalse(service.capabilities(forRepo: "/spice-repo").contains(.syncPushes))
    }

    func testCapabilities_unresolvedRepo_isEmpty() async {
        let service = StackService(registry: StackProviderRegistry(providers: []))
        await service.probe()
        XCTAssertTrue(service.capabilities(forRepo: "/unknown").isEmpty)
    }

    func testActionAvailability_followsTheProviderThatOwnsTheRepo() async {
        // End to end: two repos, two providers, two different sets of offered actions.
        let spice = FakeStackProvider(
            id: spiceID, capabilities: [.restack, .branchInsertion, .destroyStack])
        let github = FakeStackProvider(
            id: githubID, capabilities: [.restack, .untrackStack, .syncPushes, .sync])
        await spice.setGraph(makeGraph("a"), for: "/spice-repo")
        await github.setGraph(makeGraph("b"), for: "/github-repo")

        let service = StackService(registry: StackProviderRegistry(providers: [spice, github]))
        await service.probe()
        await service.refreshGraph(repo: "/spice-repo")
        await service.refreshGraph(repo: "/github-repo")

        let spiceActions = StackActionAvailability(
            capabilities: service.capabilities(forRepo: "/spice-repo"))
        let githubActions = StackActionAvailability(
            capabilities: service.capabilities(forRepo: "/github-repo"))

        XCTAssertTrue(spiceActions.canInsertBranch)
        XCTAssertTrue(spiceActions.canDestroyStack)
        XCTAssertFalse(spiceActions.canUntrackStack)
        XCTAssertFalse(spiceActions.syncNeedsConfirmation)

        XCTAssertFalse(githubActions.canInsertBranch)
        XCTAssertFalse(githubActions.canDestroyStack)
        XCTAssertTrue(githubActions.canUntrackStack)
        XCTAssertTrue(githubActions.syncNeedsConfirmation)
    }

    func testAvailability_readyProviderWins_overUnusableOne() async {
        let unusable = FakeStackProvider(id: spiceID)
        await unusable.setAvailability(.unusable(reason: "wrong binary"))
        let ready = FakeStackProvider(id: githubID)
        let service = StackService(registry: StackProviderRegistry(providers: [unusable, ready]))
        await service.probe()

        XCTAssertTrue(service.isAvailable)
        XCTAssertEqual(service.availability, .ready(version: "0.0.0"))
    }

    func testAvailability_noReadyProvider_prefersUnusableReasonOverMissing() async {
        // An explanation the user can act on beats a bare "not installed".
        let missing = FakeStackProvider(id: spiceID)
        await missing.setAvailability(.missing)
        let unusable = FakeStackProvider(id: githubID)
        await unusable.setAvailability(.unusable(reason: "gh is not authenticated"))
        let service = StackService(registry: StackProviderRegistry(providers: [missing, unusable]))
        await service.probe()

        XCTAssertFalse(service.isAvailable)
        XCTAssertEqual(service.availability, .unusable(reason: "gh is not authenticated"))
    }

    func testAvailabilityForProvider_isReportedIndividually() async {
        let spice = FakeStackProvider(id: spiceID)
        await spice.setAvailability(.unusable(reason: "wrong binary"))
        let github = FakeStackProvider(id: githubID)
        let service = StackService(registry: StackProviderRegistry(providers: [spice, github]))
        await service.probe()

        XCTAssertEqual(service.availability(for: spiceID), .unusable(reason: "wrong binary"))
        XCTAssertEqual(service.availability(for: githubID), .ready(version: "0.0.0"))
        XCTAssertEqual(service.availability(for: StackProviderID(rawValue: "nope")), .missing)
    }

    func testUntrackStack_defaultProviderReportsUnsupported() async {
        // FakeStackProvider inherits the protocol default — the backstop for a caller
        // that forgot to gate on .untrackStack.
        let fake = FakeStackProvider(id: spiceID)
        await fake.setGraph(makeGraph("a"), for: "/repo")
        let service = StackService(registry: StackProviderRegistry(providers: [fake]))
        await service.probe()
        await service.refreshGraph(repo: "/repo")

        do {
            try await service.untrackStack(repo: "/repo", worktree: "/repo/wt")
            XCTFail("expected unsupported error")
        } catch let error as StackProviderError {
            guard case .unsupported = error else {
                return XCTFail("expected .unsupported, got \(error)")
            }
        } catch {
            XCTFail("expected StackProviderError, got \(error)")
        }
    }
}
