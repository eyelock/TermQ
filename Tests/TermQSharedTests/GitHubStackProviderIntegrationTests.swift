import Foundation
import XCTest

@testable import TermQShared

/// Exercises `GitHubStackProvider` against a REAL `gh stack`, in a throwaway repository
/// this test builds and tears down itself.
///
/// ## Why this exists
///
/// Every other test in this file's neighbourhood is fixture-based: the tracking-file
/// schema, the command arguments, and the exit-code classification were all derived by
/// reading the extension's source. That is enough to be careful with, and not enough to
/// be confident about — a field rename or a changed exit code would leave those tests
/// green while the feature broke.
///
/// ## Why it is opt-in
///
/// It shells out to a third-party extension that CI does not have and most contributors
/// will not have installed, and it writes to a temporary git repository. It runs only
/// when `TERMQ_GH_STACK_INTEGRATION=1` is set AND `gh stack` is actually present, and
/// skips cleanly otherwise. Run it after upgrading the extension:
///
///     TERMQ_GH_STACK_INTEGRATION=1 swift test --filter GitHubStackProviderIntegration
///
/// Everything here is local: a bare repository on disk stands in for the remote, so no
/// network call is made and no pull request is ever created.
final class GitHubStackProviderIntegrationTests: XCTestCase {
    private var root: URL!
    private var repo: String { root.appendingPathComponent("repo").path }
    private var remote: String { root.appendingPathComponent("remote.git").path }

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TERMQ_GH_STACK_INTEGRATION"] == "1",
            "set TERMQ_GH_STACK_INTEGRATION=1 to run against a live gh stack")
        let availability = await GitHubStackProvider().probe()
        try XCTSkipUnless(
            availability.isReady, "gh stack is not installed or usable: \(availability)")

        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("termq-gh-stack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // A bare repo as `origin`: `gh stack rebase` fetches trunk and refuses outright
        // with "no remotes configured", so a remote is required even for local-only work.
        try await git(["init", "--quiet", "--bare", remote], in: root.path)
        try await git(["init", "--quiet", "-b", "main", repo], in: root.path)
        try await git(["config", "user.email", "test@example.com"], in: repo)
        try await git(["config", "user.name", "TermQ Test"], in: repo)
        try await git(["remote", "add", "origin", remote], in: repo)
        try write("l1\nl2\nl3\n", to: "file.txt")
        try await git(["add", "-A"], in: repo)
        try await git(["commit", "--quiet", "-m", "base"], in: repo)
        try await git(["push", "--quiet", "-u", "origin", "main"], in: repo)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try await super.tearDown()
    }

    // MARK: - Detection

    func testProbeAndIsInitialized_trackTheRealTrackingFile() async throws {
        let provider = GitHubStackProvider()
        // A repo with no stack must read as uninitialized — this is what stops the
        // registry handing a git-spice repo to this provider.
        let before = await provider.isInitialized(repo: repo)
        XCTAssertFalse(before)

        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await provider.initialize(repo: repo, trunk: "main")

        let after = await provider.isInitialized(repo: repo)
        XCTAssertTrue(after, "the tracking file gh stack init writes must be found")
    }

    func testInitialize_onTrunk_refusesWithAnActionableMessage() async throws {
        // gh-stack starts a stack from the checked-out branch, so standing on the trunk
        // there is nothing to adopt. Refusing beats inventing a branch name.
        do {
            try await GitHubStackProvider().initialize(repo: repo, trunk: "main")
            XCTFail("expected a refusal while on the trunk")
        } catch let error as StackProviderError {
            guard case .preconditionFailed(let detail) = error else {
                return XCTFail("expected .preconditionFailed, got \(error)")
            }
            XCTAssertTrue(detail.contains("main"), "the message must name the trunk")
        }
    }

    // MARK: - Graph mapping

    func testGraph_mapsRealTrackingFileOntoTheNeutralModel() async throws {
        let provider = GitHubStackProvider()
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await provider.initialize(repo: repo, trunk: "main")
        try await provider.createBranch(name: "feat-b", target: nil, in: repo)
        try await commitAll(message: "b", contents: "l1\nA\nl3\nB\n")

        let graph = try await provider.graph(repo: repo, worktrees: [repo])

        XCTAssertEqual(
            Set(graph.branches.map(\.name)), ["main", "feat-a", "feat-b"],
            "the trunk must be synthesized alongside the stack members")

        // The whole point of deriving parents from array order: `base` in the real file
        // is the parent's HEAD SHA, and reading it as a parent would produce a
        // plausible-looking but wrong graph.
        XCTAssertNil(graph.branch(named: "main")?.parent)
        XCTAssertEqual(graph.branch(named: "feat-a")?.parent, "main")
        XCTAssertEqual(graph.branch(named: "feat-b")?.parent, "feat-a")
        XCTAssertEqual(graph.branch(named: "feat-a")?.children, ["feat-b"])
        XCTAssertTrue(graph.isTrunk("main"))
        XCTAssertEqual(graph.chain(containing: "feat-b").map(\.name), ["feat-a", "feat-b"])

        // No PR exists locally, and `Queued` is never persisted.
        XCTAssertNil(graph.branch(named: "feat-b")?.changeRequest)
        XCTAssertFalse(graph.branch(named: "feat-b")?.isQueued ?? true)
    }

    func testGraph_needsRestack_reflectsAMovedTrunk() async throws {
        let provider = GitHubStackProvider()
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await provider.initialize(repo: repo, trunk: "main")

        let clean = try await provider.graph(repo: repo, worktrees: [repo])
        XCTAssertEqual(clean.branch(named: "feat-a")?.needsRestack, false)

        try await git(["checkout", "--quiet", "main"], in: repo)
        try await commitAll(message: "trunk moves", contents: "l1\nTRUNK\nl3\n")
        try await git(["checkout", "--quiet", "feat-a"], in: repo)

        let stale = try await provider.graph(repo: repo, worktrees: [repo])
        XCTAssertEqual(
            stale.branch(named: "feat-a")?.needsRestack, true,
            "a trunk that is no longer an ancestor must surface as needing a restack")
    }

    /// The architectural premise of this provider: gh-stack resolves its tracking file
    /// against `git rev-parse --git-dir`, which inside a linked worktree is that
    /// worktree's private directory. Each worktree therefore carries an INDEPENDENT
    /// stack, and a repo-wide view only exists because this provider assembles one.
    func testGraph_unionsStacksAcrossWorktrees() async throws {
        let provider = GitHubStackProvider()
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await provider.initialize(repo: repo, trunk: "main")

        let linked = root.appendingPathComponent("linked").path
        try await git(["checkout", "--quiet", "main"], in: repo)
        try await git(["worktree", "add", "--quiet", linked, "-b", "feat-x"], in: repo)
        try write("l1\nl2\nl3\nX\n", to: "file.txt", in: linked)
        try await git(["commit", "--quiet", "-am", "x"], in: linked)
        try await provider.initialize(repo: linked, trunk: "main")

        // Each worktree alone sees only its own stack...
        let fromMainOnly = try await provider.graph(repo: repo, worktrees: [repo])
        XCTAssertTrue(fromMainOnly.branches.contains { $0.name == "feat-a" })
        XCTAssertTrue(
            fromMainOnly.branches.contains { $0.name == "feat-x" },
            "the union reads every worktree's file from the common dir, not just the CWD's")

        // ...and the linked worktree's branch is reported as checked out elsewhere, which
        // is what makes the sidebar's jump target land somewhere real.
        let full = try await provider.graph(repo: repo, worktrees: [repo, linked])
        XCTAssertEqual(full.branch(named: "feat-x")?.checkedOutElsewhere, linked)
        XCTAssertEqual(
            Set(full.stackRoots.map(\.name)), ["feat-a", "feat-x"],
            "two independent stacks, one per worktree")
    }

    // MARK: - Mutations

    func testCreateBranch_refusesFromTheMiddleOfTheStack() async throws {
        let provider = GitHubStackProvider()
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await provider.initialize(repo: repo, trunk: "main")
        try await provider.createBranch(name: "feat-b", target: nil, in: repo)
        try await commitAll(message: "b", contents: "l1\nA\nl3\nB\n")
        try await git(["checkout", "--quiet", "feat-a"], in: repo)

        // gh-stack only extends a stack at its top and exits 5 otherwise. The mapping
        // must surface that as a fixable state, with the tool's own wording.
        do {
            try await provider.createBranch(name: "feat-c", target: nil, in: repo)
            XCTFail("expected a refusal from the middle of the stack")
        } catch let error as StackProviderError {
            guard case .preconditionFailed(let detail) = error else {
                return XCTFail("expected .preconditionFailed, got \(error)")
            }
            XCTAssertTrue(
                detail.lowercased().contains("top"),
                "gh-stack's own explanation should reach the user, got: \(detail)")
        }
    }

    func testRestack_conflict_isReportedAsAPausedOperation_andResumes() async throws {
        let provider = GitHubStackProvider()
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await provider.initialize(repo: repo, trunk: "main")

        // Move the trunk over the same line feat-a changed.
        try await git(["checkout", "--quiet", "main"], in: repo)
        try await commitAll(message: "trunk moves", contents: "l1\nTRUNK\nl3\n")
        try await git(["push", "--quiet", "origin", "main"], in: repo)
        try await git(["checkout", "--quiet", "feat-a"], in: repo)

        let noPauseYet = await provider.pausedOperation(repo: repo)
        XCTAssertNil(noPauseYet)

        do {
            try await provider.restack(scope: .stack, in: repo)
            XCTFail("expected the restack to stop on a conflict")
        } catch {
            // Exit 3 must NOT classify as a precondition failure: the conflict is
            // reported through pausedOperation and surfaces as the sidebar's banner.
            guard case StackProviderError.commandFailed(_, let code, _)? = error as? StackProviderError
            else { return XCTFail("expected .commandFailed, got \(error)") }
            XCTAssertEqual(code, 3)
        }

        let paused = await provider.pausedOperation(repo: repo)
        XCTAssertEqual(paused?.kind, .restack)
        XCTAssertEqual(paused?.conflictedFiles, ["file.txt"])

        try write("l1\nRESOLVED\nl3\n", to: "file.txt")
        try await git(["add", "file.txt"], in: repo)
        try await provider.continueOperation(in: repo)

        let resolved = await provider.pausedOperation(repo: repo)
        XCTAssertNil(resolved, "the banner must clear once the rebase completes")
    }

    /// The other way out of a conflict. `continueOperation` above was covered from the
    /// start while this was not, which is the wrong way round: abort is what the user
    /// reaches for when they cannot resolve the conflict, so it runs on the worse day.
    func testAbortOperation_leavesTheConflictedRestackFullyUnwound() async throws {
        let provider = GitHubStackProvider()
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await provider.initialize(repo: repo, trunk: "main")
        let headBeforeRestack = try await git(["rev-parse", "feat-a"], in: repo)

        try await git(["checkout", "--quiet", "main"], in: repo)
        try await commitAll(message: "trunk moves", contents: "l1\nTRUNK\nl3\n")
        try await git(["push", "--quiet", "origin", "main"], in: repo)
        try await git(["checkout", "--quiet", "feat-a"], in: repo)

        do {
            try await provider.restack(scope: .stack, in: repo)
            XCTFail("expected the restack to stop on a conflict")
        } catch {
            // Precondition for the abort, not the assertion under test.
        }
        let paused = await provider.pausedOperation(repo: repo)
        XCTAssertEqual(paused?.kind, .restack, "the rebase must actually be paused")

        try await provider.abortOperation(in: repo)

        let cleared = await provider.pausedOperation(repo: repo)
        XCTAssertNil(cleared, "aborting must clear the sidebar's conflict banner")
        // A half-unwound abort would strand the user mid-rebase with no banner telling
        // them so, which is worse than the conflict they were escaping.
        let headAfterAbort = try await git(["rev-parse", "feat-a"], in: repo)
        XCTAssertEqual(
            headAfterAbort, headBeforeRestack, "feat-a must return to its pre-restack commit")
        let branch = try await git(["rev-parse", "--abbrev-ref", "HEAD"], in: repo)
        XCTAssertEqual(
            branch.trimmingCharacters(in: .whitespacesAndNewlines), "feat-a",
            "the abort must leave the original branch checked out, not a detached HEAD")
        let status = try await git(["status", "--porcelain"], in: repo)
        XCTAssertTrue(
            status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "no conflict markers or staged leftovers may survive the abort")
    }

    /// Unlike its siblings this one is deliberately NOT `gh stack`: the extension's own
    /// `switch` is a full-screen picker, so the provider shells out to plain git. That
    /// makes it worth pinning that it moves HEAD at all.
    func testSwitchBranch_movesHeadWithinTheStack() async throws {
        let provider = GitHubStackProvider()
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await provider.initialize(repo: repo, trunk: "main")
        try await provider.createBranch(name: "feat-b", target: nil, in: repo)
        try await commitAll(message: "b", contents: "l1\nA\nl3\nB\n")

        try await provider.switchBranch(to: "feat-a", in: repo)
        var head = try await git(["rev-parse", "--abbrev-ref", "HEAD"], in: repo)
        XCTAssertEqual(head.trimmingCharacters(in: .whitespacesAndNewlines), "feat-a")

        try await provider.switchBranch(to: "feat-b", in: repo)
        head = try await git(["rev-parse", "--abbrev-ref", "HEAD"], in: repo)
        XCTAssertEqual(head.trimmingCharacters(in: .whitespacesAndNewlines), "feat-b")

        // A failed checkout must surface as an error rather than silently doing nothing.
        do {
            try await provider.switchBranch(to: "no-such-branch", in: repo)
            XCTFail("expected switching to a missing branch to throw")
        } catch {
            // Any StackProviderError is fine; the point is that it does not succeed.
        }
    }

    /// `.trackExisting` is not advertised for this backend, because gh-stack has no
    /// "adopt this one branch onto this base" — `init` takes a whole set and `link` also
    /// creates pull requests. This pins the refusal so the capability cannot be quietly
    /// switched on without an implementation behind it.
    func testTrackBranch_isRefused() async throws {
        let provider = GitHubStackProvider()
        XCTAssertFalse(provider.capabilities.contains(.trackExisting))
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await provider.initialize(repo: repo, trunk: "main")
        try await git(["checkout", "--quiet", "-b", "loose"], in: repo)

        do {
            try await provider.trackBranch("loose", base: "main", in: repo)
            XCTFail("expected tracking a single branch to be unsupported")
        } catch let error as StackProviderError {
            guard case .unsupported = error else {
                return XCTFail("must be .unsupported, not a fixable precondition: \(error)")
            }
        }
    }

    /// The counterpart to Destroy Stack, and the reason they are separate capabilities:
    /// this one must leave every branch alive.
    func testUntrackStack_dropsTrackingAndKeepsEveryBranch() async throws {
        let provider = GitHubStackProvider()
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await provider.initialize(repo: repo, trunk: "main")
        try await provider.createBranch(name: "feat-b", target: nil, in: repo)
        try await commitAll(message: "b", contents: "l1\nA\nl3\nB\n")

        try await provider.untrackStack(in: repo)

        let stillInitialized = await provider.isInitialized(repo: repo)
        XCTAssertTrue(stillInitialized, "the tracking file remains, now holding no stacks")
        let graph = try await provider.graph(repo: repo, worktrees: [repo])
        XCTAssertTrue(graph.branches.isEmpty, "no stack is tracked any more")

        let branches = try await git(["branch", "--format=%(refname:short)"], in: repo)
        for branch in ["main", "feat-a", "feat-b"] {
            XCTAssertTrue(
                branches.contains(branch),
                "untracking must never delete a branch — \(branch) is gone")
        }
    }

    func testDestroyStack_refuses_ratherThanFallingBackToUntrack() async throws {
        let provider = GitHubStackProvider()
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await provider.initialize(repo: repo, trunk: "main")

        do {
            try await provider.destroyStack(in: repo)
            XCTFail("expected a refusal")
        } catch let error as StackProviderError {
            guard case .unsupported = error else {
                return XCTFail("expected .unsupported, got \(error)")
            }
        }
        let branches = try await git(["branch", "--format=%(refname:short)"], in: repo)
        XCTAssertTrue(branches.contains("feat-a"), "a refusal must not have deleted anything")
    }

    /// Regression: `applyNeedsRestack` rebuilds every branch that has a parent, and
    /// `remoteStackID` is both the LAST parameter and defaulted — so omitting it compiled
    /// cleanly and blanked the stack number on every branch of every graph. Merge Stack and
    /// Check Out Whole Stack both gate on that value being present, so the two headline
    /// operations of this backend were unreachable in the sidebar while every unit test
    /// stayed green. A live run found it.
    func testApplyNeedsRestack_preservesTheRemoteStackNumber() async throws {
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")
        try await GitHubStackProvider().initialize(repo: repo, trunk: "main")

        // The trunk short-circuits (no parent), so feat-a is the branch that proves it:
        // it is the one that goes through the rebuild.
        let input = [
            StackBranch(
                name: "main", isCurrent: false, checkedOutElsewhere: nil, parent: nil,
                children: ["feat-a"], needsRestack: false, changeRequest: nil, push: nil,
                isQueued: false, remoteStackID: "42"),
            StackBranch(
                name: "feat-a", isCurrent: true, checkedOutElsewhere: nil, parent: "main",
                children: [], needsRestack: false, changeRequest: nil, push: nil,
                isQueued: false, remoteStackID: "42"),
        ]

        let output = await GitHubStackProvider.applyNeedsRestack(input, repo: repo)

        XCTAssertEqual(
            output.map(\.remoteStackID), ["42", "42"],
            "restack detection must not drop the stack number it was handed")
    }

    // MARK: - Stacks unavailable

    /// Exit 9 — "stacked PRs not enabled for this repository".
    ///
    /// This was long assumed to need a specially-configured repository, and so went
    /// untested. It does not: gh-stack raises it whenever `GET /repos/{o}/{r}/stacks`
    /// fails, and a remote naming a repository the token cannot read fails with the 404
    /// it treats as "not enabled". A random name is used rather than a fixed one so the
    /// repository can never come into existence and quietly turn this test green.
    ///
    /// Unlike its neighbours this one does reach the network. No extra guard is needed:
    /// `probe()` reports ready only when `gh auth status` succeeds, and `setUp` already
    /// skips the whole suite unless it does.
    func testStacksUnavailable_isReportedAsAFixablePrecondition() async throws {
        try await git(
            [
                "remote", "set-url", "origin",
                "https://github.com/eyelock/termq-exit9-\(UUID().uuidString.lowercased()).git",
            ], in: repo)
        try await checkoutNewBranch("feat-a", change: "l1\nA\nl3\n")

        do {
            try await GitHubStackProvider()
                .linkStack(branches: ["main", "feat-a"], base: nil, in: repo)
            XCTFail("expected a refusal when the stacks endpoint is unreachable")
        } catch let error as StackProviderError {
            guard case .preconditionFailed(let detail) = error else {
                return XCTFail("exit 9 must be fixable, not a raw command failure: \(error)")
            }
            // gh-stack writes progress to stderr even without a TTY, so the raw output is
            // "Checking existing stacks...\n⚠ Stacked PRs are not enabled...". Asserting
            // equality — not `contains` — is the point: it pins that neither the progress
            // line nor the glyph reaches the alert.
            XCTAssertEqual(detail, "Stacked PRs are not enabled for this repository")
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func git(_ arguments: [String], in directory: String) async throws -> String {
        guard let gitPath = GitServiceShared.findGitPath() else {
            throw XCTSkip("git not found")
        }
        let result = try await StackProcessRunner.run(gitPath, arguments, cwd: directory, env: [:])
        guard result.exitCode == 0 else {
            throw NSError(
                domain: "git", code: Int(result.exitCode),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "git \(arguments.joined(separator: " ")) failed: \(result.stderr)"
                ])
        }
        return result.stdout
    }

    private func write(_ contents: String, to name: String, in directory: String? = nil) throws {
        let target = URL(fileURLWithPath: directory ?? repo).appendingPathComponent(name)
        try contents.write(to: target, atomically: true, encoding: .utf8)
    }

    private func checkoutNewBranch(_ name: String, change: String) async throws {
        try await git(["checkout", "--quiet", "-b", name], in: repo)
        try write(change, to: "file.txt")
        try await git(["commit", "--quiet", "-am", name], in: repo)
    }

    private func commitAll(message: String, contents: String) async throws {
        try write(contents, to: "file.txt")
        try await git(["commit", "--quiet", "-am", message], in: repo)
    }
}
