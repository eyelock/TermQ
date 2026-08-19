import Foundation
import XCTest

@testable import TermQShared

/// Exercises the `GitHubStackProvider` operations that MUTATE GITHUB, against a real
/// repository over the network.
///
/// ## Why this exists separately from `GitHubStackProviderIntegrationTests`
///
/// That suite uses a bare repository on disk as `origin`, so it covers everything that is
/// local — the tracking file, the graph, rebases and conflicts — without a single API
/// call. Seven operations fall outside it because they exist to talk to GitHub:
/// `submit` (ready and draft), `sync`, `linkStack`, `checkoutStack`, and `mergeStack`.
///
/// Those were argued to be thin wrappers over argument construction, which is unit-tested.
/// The project's own history says otherwise: `checkoutStack` shipped reading the local
/// tracking file, so it could only ever offer stacks that were already checked out, and
/// only a live run found it. The same is true of the path-spelling bug in the switch guard
/// and the progress-line leak into error alerts. Three defects, none reachable by fixtures
/// the author also wrote.
///
/// ## Why it is doubly opt-in
///
/// It creates and deletes real branches and pull requests. It runs only when
/// `TERMQ_GH_STACK_LIVE_REPO` names a repository to use as a scratch pad:
///
///     TERMQ_GH_STACK_LIVE_REPO=owner/repo swift test --filter GitHubStackLiveRepo
///
/// Point it at a THROWAWAY repository. It assumes exclusive use: `setUp` sweeps stale
/// branches left by earlier failed runs, which would disrupt a concurrent one.
///
/// ## Why the default branch is never touched
///
/// Every run creates its own base branch off the default and stacks on top of that, so
/// merges land there rather than on `main`. Nothing accumulates on the default branch, and
/// a failed run leaves debris confined to one prefix that the next run collects.
final class GitHubStackLiveRepoTests: XCTestCase {
    /// Every branch this suite creates starts with this, which is what makes the sweep
    /// safe: it can never match a branch the repository actually cares about.
    private static let branchPrefix = "termq-live"

    /// How old a leftover branch must be before the sweep removes it. Long enough that a
    /// run in progress elsewhere is not destroyed, short enough to stay tidy.
    private static let staleAfter: TimeInterval = 2 * 60 * 60

    private var root: URL!
    private var slug: String!
    private var runID: String!
    private var base: String!
    private var ghPath: String!
    private var repo: String { root.appendingPathComponent("repo").path }

    override func setUp() async throws {
        try await super.setUp()
        let environment = ProcessInfo.processInfo.environment
        guard let slug = environment["TERMQ_GH_STACK_LIVE_REPO"], !slug.isEmpty else {
            throw XCTSkip(
                "set TERMQ_GH_STACK_LIVE_REPO=owner/repo (a throwaway repository) to run")
        }
        self.slug = slug
        let availability = await GitHubStackProvider().probe()
        try XCTSkipUnless(
            availability.isReady, "gh stack is not installed or usable: \(availability)")
        ghPath = try XCTUnwrap(GitHubStackProvider.findGhBinary())

        try await sweepStaleTestBranches()

        runID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
            .lowercased()
        base = "\(Self.branchPrefix)-\(runID!)-base"

        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("termq-gh-live-\(runID!)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try await gh(["repo", "clone", slug, repo, "--", "--quiet"])
        try await git(["config", "user.email", "test@example.com"])
        try await git(["config", "user.name", "TermQ Test"])

        // The per-run base, branched from whatever the repository's default is.
        try await git(["checkout", "--quiet", "-b", base])
        try write("base\n", to: "file.txt")
        try await git(["add", "-A"])
        try await git(["commit", "--quiet", "-m", "base for \(runID!)"])
        try await git(["push", "--quiet", "-u", "origin", base])
    }

    override func tearDown() async throws {
        // Deleting the head branch closes any pull request that pointed at it, so branch
        // removal is the whole cleanup. Best-effort: a failure here must not mask a test
        // failure, but it is reported so debris is never silent.
        if let runID {
            for branch in (try? await remoteTestBranches()) ?? [] where branch.contains(runID) {
                do { try await deleteRemoteBranch(branch) } catch {
                    XCTFail("failed to clean up \(branch): \(error)")
                }
            }
        }
        if let root { try? FileManager.default.removeItem(at: root) }
        try await super.tearDown()
    }

    // MARK: - Submit

    func testSubmit_createsReadyPullRequestsTargetingTheBranchBelow() async throws {
        let provider = GitHubStackProvider()
        let (lower, upper) = try await buildTwoBranchStack()

        try await provider.submit(scope: .stack, options: StackSubmitOptions(), in: repo)

        let lowerPR = try await pullRequest(head: lower)
        let upperPR = try await pullRequest(head: upper)
        XCTAssertFalse(lowerPR.isDraft, "submit without draft must open ready-for-review PRs")
        XCTAssertFalse(upperPR.isDraft)
        // This is what makes it a stack rather than two PRs: each targets the one below,
        // so the diff reads against its real parent instead of the trunk.
        XCTAssertEqual(lowerPR.baseRefName, base)
        XCTAssertEqual(upperPR.baseRefName, lower)
    }

    /// The path that has never run anywhere. It was recorded as blocked by a local hook,
    /// which was wrong — the hook intercepts shell commands, not `Process` calls from
    /// Swift. What actually blocked it was the absence of a real repository to submit to.
    func testSubmit_draft_createsDraftPullRequests() async throws {
        let provider = GitHubStackProvider()
        let (lower, upper) = try await buildTwoBranchStack()

        try await provider.submit(
            scope: .stack, options: StackSubmitOptions(draft: true), in: repo)

        // `--open` is the inverse of draft, so omitting it is the entire mechanism here.
        // A regression that always passed `--open` would publish someone's unfinished work
        // for review, which is why this asserts rather than trusting the argument test.
        let lowerPR = try await pullRequest(head: lower)
        let upperPR = try await pullRequest(head: upper)
        XCTAssertTrue(lowerPR.isDraft, "draft submit must leave PRs in draft")
        XCTAssertTrue(upperPR.isDraft)
    }

    // MARK: - Sync

    func testSync_rebasesTheStackOntoAMovedBaseAndPushes() async throws {
        let provider = GitHubStackProvider()
        let (lower, upper) = try await buildTwoBranchStack()
        try await provider.submit(scope: .stack, options: StackSubmitOptions(), in: repo)

        // Move the base on the remote, the way a merged PR would. A file no stack branch
        // touches, so the rebase is clean and any conflict is a real failure.
        try await git(["checkout", "--quiet", base])
        try write("moved\n", to: "base-moved.txt")
        try await git(["add", "-A"])
        try await git(["commit", "--quiet", "-m", "base moves"])
        try await git(["push", "--quiet", "origin", base])
        let movedBase = try await revParse(base)
        try await git(["checkout", "--quiet", upper])

        try await provider.sync(repo: repo, worktree: repo)

        // Both branches must now sit on top of the new base commit...
        for branch in [lower, upper] {
            let contains = try await isAncestor(movedBase, of: branch)
            XCTAssertTrue(contains, "\(branch) must be rebased onto the moved base")
        }
        // ...and the remote must agree, since sync force-pushes. A sync that rebased
        // locally but failed to push would leave the PRs showing a stale diff.
        let localTip = try await revParse(upper)
        let remoteTip = try await revParse("origin/\(upper)")
        XCTAssertEqual(localTip, remoteTip, "sync must push the rebased branch")
    }

    // MARK: - Link

    func testLinkStack_adoptsExistingPullRequestsWithoutCreatingMore() async throws {
        let lower = branch("link-lower")
        let upper = branch("link-upper")

        // Two ordinary pull requests, deliberately NOT created through the provider —
        // this is the "I already have PRs" case the menu item exists for.
        try await git(["checkout", "--quiet", "-b", lower, base])
        try write("lower\n", to: "file.txt")
        try await git(["commit", "--quiet", "-am", "lower"])
        try await git(["push", "--quiet", "-u", "origin", lower])
        try await gh(
            [
                "pr", "create", "-R", slug, "--base", base, "--head", lower,
                "--title", "live lower \(runID!)", "--body", "test",
            ])

        try await git(["checkout", "--quiet", "-b", upper, lower])
        try write("lower\nupper\n", to: "file.txt")
        try await git(["commit", "--quiet", "-am", "upper"])
        try await git(["push", "--quiet", "-u", "origin", upper])
        try await gh(
            [
                "pr", "create", "-R", slug, "--base", lower, "--head", upper,
                "--title", "live upper \(runID!)", "--body", "test",
            ])

        let numbersBefore = [
            try await pullRequest(head: lower).number, try await pullRequest(head: upper).number,
        ]

        try await GitHubStackProvider()
            .linkStack(branches: [lower, upper], base: base, in: repo)

        // Adoption, not creation: the same two PRs must survive with their numbers intact.
        let numbersAfter = [
            try await pullRequest(head: lower).number, try await pullRequest(head: upper).number,
        ]
        XCTAssertEqual(
            numbersAfter, numbersBefore, "link must adopt the existing PRs, not open new ones")
        // And they must now belong to a stack on the forge.
        let stack = try await remoteStackNumber(containingPR: numbersBefore[0])
        XCTAssertNotNil(stack, "the linked PRs must be part of a stack on GitHub")
    }

    // MARK: - Checkout

    func testCheckoutStack_bringsTheWholeStackIntoAFreshClone() async throws {
        let provider = GitHubStackProvider()
        let (lower, upper) = try await buildTwoBranchStack()
        try await provider.submit(scope: .stack, options: StackSubmitOptions(), in: repo)
        let stackNumber = try unwrap(
            try await provider.graph(repo: repo, worktrees: [repo])
                .branch(named: upper)?.remoteStackID,
            "the submitted stack must carry a GitHub stack number")

        // A clone with no gh-stack state at all — the situation the sidebar's "Check Out
        // Whole Stack" exists for, and the one the first implementation could not serve
        // because it read the local tracking file.
        let fresh = root.appendingPathComponent("fresh").path
        try await gh(["repo", "clone", slug, fresh, "--", "--quiet"])
        let before = await provider.isInitialized(repo: fresh)
        XCTAssertFalse(before, "a fresh clone must start with no stack tracking")

        try await provider.checkoutStack(remoteStackID: stackNumber, in: fresh)

        let after = await provider.isInitialized(repo: fresh)
        XCTAssertTrue(after, "checkout must write local tracking")
        let branches = try await git(["branch", "--format=%(refname:short)"], in: fresh)
        for branch in [lower, upper] {
            XCTAssertTrue(
                branches.contains(branch),
                "checkout must bring down every branch in the stack — \(branch) is missing")
        }
        let graph = try await provider.graph(repo: fresh, worktrees: [fresh])
        XCTAssertEqual(
            graph.branch(named: upper)?.parent, lower,
            "the reconstructed graph must match the stack on the forge")
    }

    // MARK: - Merge

    func testMergeStack_mergesEveryPullRequestIntoTheBase() async throws {
        let provider = GitHubStackProvider()
        let (lower, upper) = try await buildTwoBranchStack()
        try await provider.submit(scope: .stack, options: StackSubmitOptions(), in: repo)
        let stackNumber = try unwrap(
            try await provider.graph(repo: repo, worktrees: [repo])
                .branch(named: upper)?.remoteStackID,
            "the submitted stack must carry a GitHub stack number")

        // nil method: gh-stack resolves the repository's own default. Naming one here
        // could pick a method the repository forbids — the reason the sheet displays the
        // inherited method rather than choosing.
        try await provider.mergeStack(remoteStackID: stackNumber, method: nil, in: repo)

        for branch in [lower, upper] {
            let pr = try await pullRequest(head: branch)
            XCTAssertEqual(pr.state, "MERGED", "\(branch)'s PR must be merged, not just closed")
        }
        // The point of the whole operation: the work is on the base branch.
        try await git(["fetch", "--quiet", "origin", base])
        // `base!`, not `base`: interpolating an implicitly-unwrapped optional yields
        // "Optional(...)" rather than the branch name.
        let files = try await git(["ls-tree", "--name-only", "origin/\(base!)"])
        XCTAssertTrue(
            files.contains("lower.txt") && files.contains("upper.txt"),
            "the merged base must carry every branch's changes, got: \(files)")
    }

    // MARK: - Fixtures

    /// A two-branch stack on top of this run's base, tracked by gh-stack but not yet
    /// submitted. The shape every test here starts from.
    /// Each branch owns a DIFFERENT file. Sharing one would make every rebase a content
    /// conflict, so `sync` would fail for reasons that have nothing to do with sync.
    private func buildTwoBranchStack() async throws -> (lower: String, upper: String) {
        let provider = GitHubStackProvider()
        let lower = branch("lower")
        let upper = branch("upper")
        try await git(["checkout", "--quiet", "-b", lower])
        try write("lower\n", to: "lower.txt")
        try await git(["add", "-A"])
        try await git(["commit", "--quiet", "-m", "lower"])
        try await provider.initialize(repo: repo, trunk: base)
        try await provider.createBranch(name: upper, target: nil, in: repo)
        try write("upper\n", to: "upper.txt")
        try await git(["add", "-A"])
        try await git(["commit", "--quiet", "-m", "upper"])
        return (lower, upper)
    }

    private func branch(_ suffix: String) -> String {
        "\(Self.branchPrefix)-\(runID!)-\(suffix)"
    }

    // MARK: - Cleanup

    /// Remove branches from earlier runs that failed before their own teardown.
    ///
    /// Age-gated rather than unconditional: deleting every prefixed branch would destroy a
    /// run happening elsewhere against the same repository.
    private func sweepStaleTestBranches() async throws {
        let formatter = ISO8601DateFormatter()
        for branch in try await remoteTestBranches() {
            guard
                let raw = try? await gh([
                    "api", "repos/\(slug!)/commits/\(branch)",
                    "--jq", ".commit.committer.date",
                ]),
                let date = formatter.date(
                    from: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                Date().timeIntervalSince(date) > Self.staleAfter
            else { continue }
            try? await deleteRemoteBranch(branch)
        }
    }

    private func remoteTestBranches() async throws -> [String] {
        let output = try await gh([
            "api", "repos/\(slug!)/branches", "--paginate",
            "--jq", ".[] | select(.name | startswith(\"\(Self.branchPrefix)-\")) | .name",
        ])
        return output.split(separator: "\n").map(String.init)
    }

    private func deleteRemoteBranch(_ name: String) async throws {
        try await gh(["api", "-X", "DELETE", "repos/\(slug!)/git/refs/heads/\(name)"])
    }

    // MARK: - Queries

    private struct PullRequestInfo: Decodable {
        let number: Int
        let isDraft: Bool
        let baseRefName: String
        let state: String
    }

    private func pullRequest(head: String) async throws -> PullRequestInfo {
        let output = try await gh([
            "pr", "list", "-R", slug, "--head", head, "--state", "all",
            "--json", "number,isDraft,baseRefName,state",
        ])
        let all = try JSONDecoder().decode(
            [PullRequestInfo].self, from: Data(output.utf8))
        return try XCTUnwrap(all.first, "no pull request found for \(head)")
    }

    private func remoteStackNumber(containingPR number: Int) async throws -> Int? {
        let output = try await gh([
            "api", "repos/\(slug!)/stacks?pull_request=\(number)", "--jq", ".[].number",
        ])
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func revParse(_ revision: String) async throws -> String {
        try await git(["rev-parse", revision]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isAncestor(_ commit: String, of branch: String) async throws -> Bool {
        guard let gitPath = GitServiceShared.findGitPath() else { throw XCTSkip("git not found") }
        let result = try await StackProcessRunner.run(
            gitPath, ["merge-base", "--is-ancestor", commit, branch], cwd: repo, env: [:])
        return result.exitCode == 0
    }

    // MARK: - Process helpers

    /// The clone directory once it exists, otherwise nil.
    ///
    /// The sweep and the clone itself both run before there is a checkout to stand in, and
    /// every `gh` call here addresses the repository explicitly (`-R`, or a full API path),
    /// so the working directory is never load-bearing.
    private var ghWorkingDirectory: String? {
        guard root != nil, FileManager.default.fileExists(atPath: repo) else { return nil }
        return repo
    }

    @discardableResult
    private func gh(_ arguments: [String]) async throws -> String {
        let result = try await StackProcessRunner.run(
            ghPath, arguments, cwd: ghWorkingDirectory, env: [:])
        guard result.exitCode == 0 else {
            throw NSError(
                domain: "gh", code: Int(result.exitCode),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "gh \(arguments.joined(separator: " ")) failed: \(result.stderr)"
                ])
        }
        return result.stdout
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: String? = nil) async throws -> String {
        guard let gitPath = GitServiceShared.findGitPath() else { throw XCTSkip("git not found") }
        let result = try await StackProcessRunner.run(
            gitPath, arguments, cwd: directory ?? repo, env: [:])
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

    private func write(_ contents: String, to name: String) throws {
        try contents.write(
            to: URL(fileURLWithPath: repo).appendingPathComponent(name),
            atomically: true, encoding: .utf8)
    }

    /// `XCTUnwrap` cannot be applied to an already-awaited optional inside an async
    /// autoclosure, so this is the plain-value equivalent.
    private func unwrap<T>(
        _ value: T?, _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) throws -> T {
        guard let value else {
            XCTFail(message, file: file, line: line)
            throw NSError(domain: "unwrap", code: 1)
        }
        return value
    }
}
