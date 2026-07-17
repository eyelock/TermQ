import Foundation
import XCTest

@testable import TermQShared

/// Tests the pure NDJSON→neutral-model mapping and identity-detection logic against
/// fixture data. Deliberately does not require a live `gs` binary — git-spice may not
/// be installed on CI or a developer's machine, and that must remain the ship-safe case.
final class GitSpiceStackProviderTests: XCTestCase {

    // MARK: - Version identity (Ghostscript disambiguation)

    func testIdentifyGitSpice_realOutput_returnsVersion() {
        let output = "gs version 0.31.0\n"
        XCTAssertEqual(GitSpiceStackProvider.identifyGitSpice(versionOutput: output), "0.31.0")
    }

    func testIdentifyGitSpice_alternateFormat_returnsVersion() {
        let output = "git-spice (gs) 0.31.0\n"
        XCTAssertEqual(GitSpiceStackProvider.identifyGitSpice(versionOutput: output), "0.31.0")
    }

    func testIdentifyGitSpice_ghostscriptOutput_returnsNil() {
        // Real Ghostscript --version output: just a bare version number, no "spice" mention.
        let output = "10.03.1\n"
        XCTAssertNil(GitSpiceStackProvider.identifyGitSpice(versionOutput: output))
    }

    func testIdentifyGitSpice_ghostscriptHelpBanner_returnsNil() {
        let output = "GPL Ghostscript 10.03.1 (2024-03-27)\n"
        XCTAssertNil(GitSpiceStackProvider.identifyGitSpice(versionOutput: output))
    }

    func testIdentifyGitSpice_emptyOutput_returnsNil() {
        XCTAssertNil(GitSpiceStackProvider.identifyGitSpice(versionOutput: ""))
    }

    // MARK: - Not-initialized detection

    func testIsNotInitializedError_matchesCanonicalMessage() {
        let stderr = "spice has not been initialized in this repository. Run `gs repo init` to get started.\n"
        XCTAssertTrue(GitSpiceStackProvider.isNotInitializedError(stderr))
    }

    func testIsNotInitializedError_unrelatedError_returnsFalse() {
        let stderr = "fatal: not a git repository\n"
        XCTAssertFalse(GitSpiceStackProvider.isNotInitializedError(stderr))
    }

    // MARK: - Rebase-in-progress detection

    func testIsRebaseInProgressError_matches() {
        XCTAssertTrue(GitSpiceStackProvider.isRebaseInProgressError("a rebase is already in progress"))
        XCTAssertTrue(GitSpiceStackProvider.isRebaseInProgressError("resolve the conflict and continue the rebase"))
    }

    func testIsRebaseInProgressError_unrelated_returnsFalse() {
        XCTAssertFalse(GitSpiceStackProvider.isRebaseInProgressError("no such branch"))
    }

    // MARK: - NDJSON parsing

    /// Linear stack modeled on live `gs log short --json` output: the trunk (main) is
    /// included as the only entry without a `down` edge, and stack bottoms carry
    /// down = trunk. main ← checkout-api ← checkout-ui ← checkout-tests.
    private let linearStackFixture = """
        {"name":"main","current":true,"down":null,"ups":[{"name":"checkout-api"}],"change":null,"push":null}
        {"name":"checkout-api","current":false,"down":{"name":"main","needsRestack":false},"ups":[{"name":"checkout-ui"}],"change":{"id":401,"url":"https://github.com/o/r/pull/401","status":"open","comments":2},"push":{"ahead":0,"behind":0,"needsPush":false}}
        {"name":"checkout-ui","current":false,"down":{"name":"checkout-api","needsRestack":true},"ups":[{"name":"checkout-tests"}],"change":{"id":402,"url":"https://github.com/o/r/pull/402","status":"open","comments":0},"push":{"ahead":1,"behind":0,"needsPush":true}}
        {"name":"checkout-tests","current":false,"down":{"name":"checkout-ui","needsRestack":false},"ups":[],"change":null,"push":{"ahead":2,"behind":0,"needsPush":true}}
        """

    func testParseLogShortNDJSON_decodesAllBranches() {
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(linearStackFixture)
        XCTAssertEqual(branches.count, 4)
        XCTAssertEqual(
            Set(branches.map(\.name)), ["main", "checkout-api", "checkout-ui", "checkout-tests"])
    }

    func testParseLogShortNDJSON_trunk_hasNilParent() {
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(linearStackFixture)
        let trunk = branches.first { $0.name == "main" }
        XCTAssertNotNil(trunk)
        XCTAssertNil(trunk?.parent)
        XCTAssertEqual(trunk?.children, ["checkout-api"])
    }

    func testParseLogShortNDJSON_stackBottom_isParentedOnTrunk() {
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(linearStackFixture)
        let root = branches.first { $0.name == "checkout-api" }
        XCTAssertNotNil(root)
        XCTAssertEqual(root?.parent, "main")
        XCTAssertEqual(root?.children, ["checkout-ui"])
        XCTAssertFalse(root?.isCurrent ?? true)
    }

    func testParseLogShortNDJSON_middleBranch_hasParentAndChild() {
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(linearStackFixture)
        let middle = branches.first { $0.name == "checkout-ui" }
        XCTAssertEqual(middle?.parent, "checkout-api")
        XCTAssertEqual(middle?.children, ["checkout-tests"])
        XCTAssertTrue(middle?.needsRestack ?? false)
        XCTAssertEqual(middle?.push?.ahead, 1)
        XCTAssertEqual(middle?.push?.needsPush, true)
    }

    func testParseLogShortNDJSON_topBranch_hasNoChildren() {
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(linearStackFixture)
        let top = branches.first { $0.name == "checkout-tests" }
        XCTAssertEqual(top?.children, [])
        XCTAssertNil(top?.changeRequest)
    }

    func testParseLogShortNDJSON_changeRequest_normalizesIntegerIdToString() {
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(linearStackFixture)
        let root = branches.first { $0.name == "checkout-api" }
        XCTAssertEqual(root?.changeRequest?.id, "401")
        XCTAssertEqual(root?.changeRequest?.status, .open)
        XCTAssertEqual(root?.changeRequest?.commentCount, 2)
    }

    func testParseLogShortNDJSON_changeRequest_stripsLeadingHashFromStringId() {
        // Live gs emits pre-formatted ids like "#678"; the neutral model stores the
        // bare identifier and the UI prepends exactly one "#".
        let fixture = """
            {"name":"feat/x","current":false,"down":{"name":"main"},"ups":[],"change":{"id":"#678","url":"https://github.com/o/r/pull/678","status":"open"},"push":null}
            """
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(fixture)
        XCTAssertEqual(branches.first?.changeRequest?.id, "678")
    }

    func testParseLogShortNDJSON_changeRequest_bareStringIdKeptAsIs() {
        let fixture = """
            {"name":"feat/y","current":false,"down":{"name":"main"},"ups":[],"change":{"id":"679","status":"open"},"push":null}
            """
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(fixture)
        XCTAssertEqual(branches.first?.changeRequest?.id, "679")
    }

    func testParseLogShortNDJSON_mergedAndClosedStatuses() {
        let fixture = """
            {"name":"a","current":false,"down":null,"ups":[],"change":{"id":"1","status":"merged"},"push":null}
            {"name":"b","current":false,"down":null,"ups":[],"change":{"id":"2","status":"closed"},"push":null}
            {"name":"c","current":false,"down":null,"ups":[],"change":{"id":"3","status":"weird-future-value"},"push":null}
            """
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(fixture)
        XCTAssertEqual(branches.first { $0.name == "a" }?.changeRequest?.status, .merged)
        XCTAssertEqual(branches.first { $0.name == "b" }?.changeRequest?.status, .closed)
        XCTAssertEqual(branches.first { $0.name == "c" }?.changeRequest?.status, .unknown)
    }

    func testParseLogShortNDJSON_checkedOutElsewhere_mapsWorktreeField() {
        let fixture = """
            {"name":"other-feature","current":false,"worktree":"/Users/dev/other-worktree","down":null,"ups":[]}
            """
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(fixture)
        XCTAssertEqual(branches.first?.checkedOutElsewhere, "/Users/dev/other-worktree")
    }

    func testParseLogShortNDJSON_ignoresBlankLines() {
        let fixture = "\n\(linearStackFixture)\n\n"
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(fixture)
        XCTAssertEqual(branches.count, 4)
    }

    func testParseLogShortNDJSON_skipsUnparseableLines_decodesRest() {
        let fixture = "not json at all\n\(linearStackFixture)"
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(fixture)
        XCTAssertEqual(branches.count, 4)
    }

    func testParseLogShortNDJSON_missingOptionalFields_defaultGracefully() {
        // Only `name` is required — a future gs release adding/removing optional fields
        // must not break decoding entirely.
        let fixture = #"{"name":"lone-branch"}"#
        let branches = GitSpiceStackProvider.parseLogShortNDJSON(fixture)
        XCTAssertEqual(branches.count, 1)
        XCTAssertEqual(branches.first?.name, "lone-branch")
        XCTAssertFalse(branches.first?.isCurrent ?? true)
        XCTAssertNil(branches.first?.parent)
        XCTAssertEqual(branches.first?.children, [])
        XCTAssertFalse(branches.first?.needsRestack ?? true)
        XCTAssertNil(branches.first?.changeRequest)
        XCTAssertNil(branches.first?.push)
    }

    func testParseLogShortNDJSON_emptyOutput_returnsEmptyArray() {
        XCTAssertEqual(GitSpiceStackProvider.parseLogShortNDJSON(""), [])
    }

    // MARK: - Graph command construction

    func testGraphLogArguments_includeAll() {
        // Without --all, gs log only reports the stack related to the CWD's current
        // branch — the graph silently shrinks to one stack in multi-stack repos.
        let args = GitSpiceStackProvider.graphLogArguments()
        XCTAssertEqual(args, ["log", "short", "--all", "--json", "-S", "--no-prompt"])
    }

    /// Multi-stack output is the NORM with --all: one trunk fanning out to several
    /// stacks plus lone tracked branches, all in one NDJSON stream.
    func testParseLogShortNDJSON_multiStackOutput_yieldsAllStacks() {
        let fixture = """
            {"name":"develop","current":true,"down":null,"ups":[{"name":"design/adr"},{"name":"feat/evals"},{"name":"feat/routing"}]}
            {"name":"design/adr","current":false,"down":{"name":"develop"},"ups":[]}
            {"name":"feat/evals","current":false,"down":{"name":"develop"},"ups":[{"name":"feat/evals-ui"}]}
            {"name":"feat/evals-ui","current":false,"down":{"name":"feat/evals"},"ups":[]}
            {"name":"feat/routing","current":false,"down":{"name":"develop"},"ups":[{"name":"feat/routing-tests"}]}
            {"name":"feat/routing-tests","current":false,"down":{"name":"feat/routing"},"ups":[]}
            """
        let graph = StackGraph(branches: GitSpiceStackProvider.parseLogShortNDJSON(fixture))
        XCTAssertEqual(graph.branches.count, 6)
        // design/adr is a lone tracked branch on trunk — still a legitimate (one-entry)
        // stack root.
        XCTAssertEqual(
            graph.stackRoots.map(\.name).sorted(), ["design/adr", "feat/evals", "feat/routing"])
        XCTAssertEqual(
            graph.chain(containing: "feat/routing-tests").map(\.name),
            ["feat/routing", "feat/routing-tests"])
    }

    // MARK: - Mutation command construction (pure, no process spawn)

    func testRestackArguments_branchScope() {
        XCTAssertEqual(
            GitSpiceStackProvider.restackArguments(for: .branch("checkout-ui")),
            ["branch", "restack", "--branch=checkout-ui", "--no-prompt"])
    }

    func testRestackArguments_upstackScope_currentBranch() {
        XCTAssertEqual(
            GitSpiceStackProvider.restackArguments(for: .upstack(from: nil)),
            ["upstack", "restack", "--no-prompt"])
    }

    func testRestackArguments_upstackScope_namedBranch() {
        XCTAssertEqual(
            GitSpiceStackProvider.restackArguments(for: .upstack(from: "checkout-ui")),
            ["upstack", "restack", "--branch=checkout-ui", "--no-prompt"])
    }

    func testRestackArguments_stackScope() {
        XCTAssertEqual(
            GitSpiceStackProvider.restackArguments(for: .stack),
            ["stack", "restack", "--no-prompt"])
    }

    func testSubmitArguments_defaultOptions() {
        XCTAssertEqual(
            GitSpiceStackProvider.submitArguments(for: .stack, options: StackSubmitOptions()),
            ["stack", "submit", "--fill", "--no-prompt"])
    }

    func testSubmitArguments_draftAndUpdateOnly() {
        let options = StackSubmitOptions(draft: true, updateOnly: true)
        XCTAssertEqual(
            GitSpiceStackProvider.submitArguments(for: .branch("checkout-ui"), options: options),
            [
                "branch", "submit", "--branch=checkout-ui", "--fill", "--no-prompt",
                "--draft", "--update-only",
            ])
    }

    func testSubmitArguments_upstackWithNamedBranch() {
        XCTAssertEqual(
            GitSpiceStackProvider.submitArguments(for: .upstack(from: "mid"), options: StackSubmitOptions()),
            ["upstack", "submit", "--branch=mid", "--fill", "--no-prompt"])
    }

    // MARK: - Binary discovery

    func testFindGsBinary_returnsExecutableOrNil() {
        let path = GitSpiceStackProvider.findGsBinary()
        if let p = path {
            XCTAssertTrue(
                FileManager.default.isExecutableFile(atPath: p),
                "findGsBinary returned \(p) but it is not executable")
        }
    }

    // MARK: - Initialization check (must never invoke gs — gs log auto-initializes)

    /// Create a throwaway git repo with one commit. Skips when git isn't available.
    private func makeTempGitRepo() async throws -> URL {
        guard GitServiceShared.findGitPath() != nil else {
            throw XCTSkip("git not available")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gs-provider-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try await GitServiceShared.runGitCommand(repoPath: dir.path, args: ["init", "-q"])
        _ = try await GitServiceShared.runGitCommand(
            repoPath: dir.path,
            args: [
                "-c", "user.email=t@t", "-c", "user.name=t",
                "commit", "--allow-empty", "-m", "init",
            ])
        return dir
    }

    func testIsInitialized_repoWithoutSpiceRef_returnsFalse() async throws {
        let repo = try await makeTempGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let provider = GitSpiceStackProvider()
        let initialized = await provider.isInitialized(repo: repo.path)
        XCTAssertFalse(initialized)
    }

    func testIsInitialized_repoWithSpiceRef_returnsTrue() async throws {
        let repo = try await makeTempGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        _ = try await GitServiceShared.runGitCommand(
            repoPath: repo.path, args: ["update-ref", "refs/spice/data", "HEAD"])
        let provider = GitSpiceStackProvider()
        let initialized = await provider.isInitialized(repo: repo.path)
        XCTAssertTrue(initialized)
    }

    func testIsInitialized_nonRepoDirectory_returnsFalse() async {
        let provider = GitSpiceStackProvider()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gs-provider-nonrepo-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let initialized = await provider.isInitialized(repo: dir.path)
        XCTAssertFalse(initialized)
    }

    /// Regression for the auto-initialization bug: `graph()` on an uninitialized repo
    /// must throw `.notInitialized` WITHOUT invoking gs. The initialization gate runs
    /// before binary resolution, so this holds (and is testable) whether or not
    /// git-spice is installed — a binaryMissing error here would mean gs was consulted.
    func testGraph_uninitializedRepo_throwsNotInitializedWithoutInvokingGs() async throws {
        let repo = try await makeTempGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let provider = GitSpiceStackProvider()
        do {
            _ = try await provider.graph(repo: repo.path)
            XCTFail("Expected notInitialized")
        } catch StackProviderError.notInitialized {
            // expected — and no gs process was spawned to get here
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Same guarantee for the paused-operation probe: uninitialized repo → nil, no gs.
    func testPausedOperation_uninitializedRepo_returnsNil() async throws {
        let repo = try await makeTempGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let provider = GitSpiceStackProvider()
        let paused = await provider.pausedOperation(repo: repo.path)
        XCTAssertNil(paused)
    }

    // MARK: - Probe integration (skips cleanly when gs isn't installed)

    func testProbe_reflectsBinaryPresence() async {
        let provider = GitSpiceStackProvider()
        let availability = await provider.probe()
        if GitSpiceStackProvider.findGsBinary() == nil {
            XCTAssertEqual(availability, .missing)
        } else {
            // A `gs` binary is present on this machine — it must at least resolve to a
            // definite state, not hang or crash.
            switch availability {
            case .missing, .unusable, .ready:
                break
            }
        }
    }
}

// MARK: - StackGraph tests

final class StackGraphTests: XCTestCase {

    private func branch(
        _ name: String, parent: String?, children: [String] = [], isCurrent: Bool = false
    ) -> StackBranch {
        StackBranch(
            name: name, isCurrent: isCurrent, checkedOutElsewhere: nil, parent: parent,
            children: children, needsRestack: false, changeRequest: nil, push: nil)
    }

    /// Mirrors live gs output: the trunk (develop) is present with no `down` edge and
    /// fans out to a stack and a lone tracked branch.
    private func makeGraph() -> StackGraph {
        StackGraph(
            branches: [
                branch("develop", parent: nil, children: ["checkout-api", "lone-on-trunk"], isCurrent: true),
                branch("checkout-api", parent: "develop", children: ["checkout-ui"]),
                branch("checkout-ui", parent: "checkout-api", children: ["checkout-tests"]),
                branch("checkout-tests", parent: "checkout-ui"),
                branch("lone-on-trunk", parent: "develop"),
            ])
    }

    /// Trunk fanning out to MULTIPLE stacks — the shape observed live (develop with
    /// three ups). The trunk is a fan-out point, never a member of any chain.
    private func makeMultiStackGraph() -> StackGraph {
        StackGraph(
            branches: [
                branch(
                    "develop", parent: nil,
                    children: ["design/adr", "feat/evals-engine", "feat/skill-routing"]),
                branch("design/adr", parent: "develop"),
                branch("feat/evals-engine", parent: "develop", children: ["feat/evals-ui"]),
                branch("feat/evals-ui", parent: "feat/evals-engine"),
                branch("feat/skill-routing", parent: "develop", children: ["feat/skill-routing-tests"]),
                branch("feat/skill-routing-tests", parent: "feat/skill-routing"),
            ])
    }

    func testIsTrunk_trueOnlyForParentlessEntry() {
        let graph = makeGraph()
        XCTAssertTrue(graph.isTrunk("develop"))
        XCTAssertFalse(graph.isTrunk("checkout-api"))
        XCTAssertFalse(graph.isTrunk("lone-on-trunk"))
        XCTAssertFalse(graph.isTrunk("not-tracked"))
    }

    func testIsStacked_trueForStackMembers() {
        let graph = makeGraph()
        XCTAssertTrue(graph.isStacked("checkout-api"))
        XCTAssertTrue(graph.isStacked("checkout-ui"))
        XCTAssertTrue(graph.isStacked("checkout-tests"))
    }

    func testIsStacked_falseForTrunkEvenWithChildren() {
        XCTAssertFalse(makeGraph().isStacked("develop"))
    }

    func testIsStacked_falseForLoneTrunkBranch() {
        XCTAssertFalse(makeGraph().isStacked("lone-on-trunk"))
    }

    func testIsStacked_falseForUntrackedBranch() {
        XCTAssertFalse(makeGraph().isStacked("not-tracked"))
    }

    func testRootBranch_walksDownToLastNonTrunkBranch() {
        let graph = makeGraph()
        XCTAssertEqual(graph.rootBranch(for: "checkout-tests")?.name, "checkout-api")
        XCTAssertEqual(graph.rootBranch(for: "checkout-ui")?.name, "checkout-api")
        XCTAssertEqual(graph.rootBranch(for: "checkout-api")?.name, "checkout-api")
    }

    func testRootBranch_trunk_returnsNil() {
        XCTAssertNil(makeGraph().rootBranch(for: "develop"))
    }

    func testRootBranch_unknownBranch_returnsNil() {
        XCTAssertNil(makeGraph().rootBranch(for: "ghost"))
    }

    func testChain_ordersBottomToTop_excludingTrunk() {
        let chain = makeGraph().chain(containing: "checkout-tests")
        XCTAssertEqual(chain.map(\.name), ["checkout-api", "checkout-ui", "checkout-tests"])
    }

    func testChain_sameResultRegardlessOfEntryPoint() {
        let graph = makeGraph()
        let fromTop = graph.chain(containing: "checkout-tests").map(\.name)
        let fromMiddle = graph.chain(containing: "checkout-ui").map(\.name)
        let fromBottom = graph.chain(containing: "checkout-api").map(\.name)
        XCTAssertEqual(fromTop, fromMiddle)
        XCTAssertEqual(fromMiddle, fromBottom)
    }

    func testChain_trunk_returnsEmpty() {
        // The trunk belongs to no single stack — a worktree checked out on trunk gets
        // no stack disclosure even when stacks hang off it.
        XCTAssertEqual(makeGraph().chain(containing: "develop"), [])
        XCTAssertEqual(makeMultiStackGraph().chain(containing: "develop"), [])
    }

    func testChain_loneTrunkBranch_returnsSingleEntry() {
        XCTAssertEqual(makeGraph().chain(containing: "lone-on-trunk").map(\.name), ["lone-on-trunk"])
    }

    func testChain_untrackedBranch_returnsEmpty() {
        XCTAssertEqual(makeGraph().chain(containing: "ghost"), [])
    }

    func testChain_multiStackTrunk_neverIncludesTrunk() {
        let graph = makeMultiStackGraph()
        XCTAssertEqual(
            graph.chain(containing: "feat/evals-ui").map(\.name),
            ["feat/evals-engine", "feat/evals-ui"])
        XCTAssertEqual(
            graph.chain(containing: "feat/skill-routing").map(\.name),
            ["feat/skill-routing", "feat/skill-routing-tests"])
        for name in ["feat/evals-ui", "feat/skill-routing-tests", "design/adr"] {
            XCTAssertFalse(
                graph.chain(containing: name).contains { $0.name == "develop" },
                "trunk leaked into chain for \(name)")
        }
    }

    func testStackRoots_multiStackTrunk_oneRootPerStack_includingLoners() {
        let roots = makeMultiStackGraph().stackRoots.map(\.name).sorted()
        // design/adr is a lone tracked branch on trunk (no ups) — still a legitimate
        // one-entry stack root (Round-3 addendum: "New Stack…" / "Start a stack"
        // produce exactly this shape, and gs tracks it).
        XCTAssertEqual(roots, ["design/adr", "feat/evals-engine", "feat/skill-routing"])
    }

    func testStackRoots_simpleGraph_excludesOnlyTrunk() {
        XCTAssertEqual(makeGraph().stackRoots.map(\.name).sorted(), ["checkout-api", "lone-on-trunk"])
    }

    func testChain_doesNotInfiniteLoopOnCycle() {
        // Defensive: a malformed/cyclical graph (should never happen from real gs output)
        // must not hang the sidebar.
        let cyclical = StackGraph(
            branches: [
                StackBranch(
                    name: "a", isCurrent: false, checkedOutElsewhere: nil, parent: "b",
                    children: ["b"], needsRestack: false, changeRequest: nil, push: nil),
                StackBranch(
                    name: "b", isCurrent: false, checkedOutElsewhere: nil, parent: "a",
                    children: ["a"], needsRestack: false, changeRequest: nil, push: nil),
            ])
        let chain = cyclical.chain(containing: "a")
        XCTAssertLessThanOrEqual(chain.count, 2)
    }
}

// MARK: - StackProviderRegistry / error tests

final class StackProviderRegistryTests: XCTestCase {
    func testResolveProvider_missingBinary_returnsNil() async throws {
        // Ship-safe case: git-spice not installed → registry finds nothing usable.
        guard GitSpiceStackProvider.findGsBinary() == nil else {
            throw XCTSkip("gs is installed on this machine; behavior covered by probe test instead")
        }
        let registry = StackProviderRegistry()
        let resolved = await registry.resolveProvider()
        XCTAssertNil(resolved)
    }
}

final class StackProviderErrorTests: XCTestCase {
    func testBinaryMissing_hasDescription() {
        XCTAssertNotNil(StackProviderError.binaryMissing.errorDescription)
    }

    func testNotInitialized_mentionsRepo() {
        let error = StackProviderError.notInitialized(repo: "/repo/path")
        XCTAssertTrue(error.errorDescription?.contains("/repo/path") ?? false)
    }

    func testCommandFailed_mentionsExitCodeAndOutput() {
        let error = StackProviderError.commandFailed(command: "gs log short --json", exitCode: 1, output: "boom")
        XCTAssertTrue(error.errorDescription?.contains("1") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("boom") ?? false)
    }
}
