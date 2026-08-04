import Foundation
import XCTest

@testable import TermQ
@testable import TermQShared

/// Exercises `RemoteStackDiscoveryService` and `StackMergeReadinessService` against a REAL
/// repository, through a real `gh`.
///
/// ## Why decode tests were not enough
///
/// Both services already have thorough fixture tests, and both fixtures were captured from
/// the live endpoints, so the decoding is faithful. What neither covers is the call around
/// the decode — and that is precisely where this feature's worst bug lived: the tracking
/// file held the stack number, the DTO decoded it correctly, and a rebuild in between
/// dropped it, hiding two menu items with every test still green.
///
/// The same shape of mistake is available here:
///
/// - `RemoteStackDiscoveryService` asks for `repos/{owner}/{repo}/stacks` with the
///   placeholders literal, relying on `gh` to resolve them from the working directory. If
///   that resolution failed, the fetch would return an empty list — indistinguishable from
///   "this repository has no stacks".
/// - `StackMergeReadinessService` fans `gh pr view` out concurrently and then has to put
///   the results back into the caller's order, because that order is merge order. A task
///   group completes in whatever order it likes.
/// - Both read `GhCliProbe.shared.status.ghPath`, which is `.missing` until `probe()` has
///   run. Without it they fail silently: no stacks, or a thrown `binaryMissing`.
///
/// ## Gating and cleanup
///
/// Same contract as `GitHubStackLiveRepoTests`:
///
///     TERMQ_GH_STACK_LIVE_REPO=owner/repo swift test --filter RemoteStackLive
///
/// It deliberately shares that suite's `termq-live` branch prefix, so either suite's sweep
/// collects debris left by the other.
@MainActor
final class RemoteStackLiveTests: XCTestCase {
    private var root: URL!
    private var slug: String!
    private var runID: String!
    private var base: String!
    private var ghPath: String!
    private var lowerPR: Int!
    private var upperPR: Int!
    private var repo: String { root.appendingPathComponent("repo").path }

    override func setUp() async throws {
        try await super.setUp()
        guard let slug = ProcessInfo.processInfo.environment["TERMQ_GH_STACK_LIVE_REPO"],
            !slug.isEmpty
        else {
            throw XCTSkip(
                "set TERMQ_GH_STACK_LIVE_REPO=owner/repo (a throwaway repository) to run")
        }
        self.slug = slug
        let availability = await GitHubStackProvider().probe()
        try XCTSkipUnless(
            availability.isReady, "gh stack is not installed or usable: \(availability)")
        ghPath = try XCTUnwrap(GitHubStackProvider.findGhBinary())

        // Both services read the shared probe rather than looking for gh themselves.
        // Skipping this leaves ghPath nil and every assertion below fails for the wrong
        // reason, which is itself worth knowing.
        await GhCliProbe.shared.probe()

        runID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
            .lowercased()
        base = "termq-live-\(runID!)-base"
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("termq-remote-live-\(runID!)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try await gh(["repo", "clone", slug, repo, "--", "--quiet"], cwd: nil)
        try await git(["config", "user.email", "test@example.com"])
        try await git(["config", "user.name", "TermQ Test"])

        try await git(["checkout", "--quiet", "-b", base])
        try write("base\n", to: "base.txt")
        try await git(["add", "-A"])
        try await git(["commit", "--quiet", "-m", "base for \(runID!)"])
        try await git(["push", "--quiet", "-u", "origin", base])

        // A real two-PR stack, built through the provider so the shape matches what the
        // sidebar would be looking at.
        let provider = GitHubStackProvider()
        try await git(["checkout", "--quiet", "-b", branch("lower")])
        try write("lower\n", to: "lower.txt")
        try await git(["add", "-A"])
        try await git(["commit", "--quiet", "-m", "lower"])
        try await provider.initialize(repo: repo, trunk: base)
        try await provider.createBranch(name: branch("upper"), target: nil, in: repo)
        try write("upper\n", to: "upper.txt")
        try await git(["add", "-A"])
        try await git(["commit", "--quiet", "-m", "upper"])
        try await provider.submit(scope: .stack, options: StackSubmitOptions(), in: repo)

        lowerPR = try await pullRequestNumber(head: branch("lower"))
        upperPR = try await pullRequestNumber(head: branch("upper"))
    }

    override func tearDown() async throws {
        if let runID, let slug {
            let names =
                (try? await gh(
                    [
                        "api", "repos/\(slug)/branches", "--paginate",
                        "--jq", ".[] | select(.name | contains(\"\(runID)\")) | .name",
                    ], cwd: nil)) ?? ""
            for name in names.split(separator: "\n").map(String.init) {
                _ = try? await gh(
                    ["api", "-X", "DELETE", "repos/\(slug)/git/refs/heads/\(name)"], cwd: nil)
            }
        }
        if let root { try? FileManager.default.removeItem(at: root) }
        try await super.tearDown()
    }

    // MARK: - Discovery

    func testDiscovery_findsTheStackFromTheWorkingDirectoryAlone() async throws {
        let service = RemoteStackDiscoveryService()

        let stacks = await service.refresh(repoPath: repo)

        // The service never names the repository — `{owner}/{repo}` is resolved by gh from
        // the working directory. Getting anything back at all is the assertion.
        let stack = try XCTUnwrap(
            stacks.first { $0.pullRequests.contains { $0.number == lowerPR } },
            "the submitted stack must be discoverable from the repo path alone")
        XCTAssertEqual(
            stack.pullRequests.map(\.number), [lowerPR, upperPR],
            "the stack must list its PRs bottom-first, which is merge order")
        XCTAssertEqual(stack.baseRef, base)
        XCTAssertTrue(stack.isOpen)

        // The pure lookup the PR feed calls while rendering must agree, for either member.
        XCTAssertEqual(service.stack(containingPR: upperPR, repoPath: repo)?.number, stack.number)
        XCTAssertEqual(service.stack(containingPR: lowerPR, repoPath: repo)?.number, stack.number)
    }

    func testDiscovery_reportsNoStacksForAPullRequestThatHasNone() async throws {
        let service = RemoteStackDiscoveryService()
        await service.refresh(repoPath: repo)
        // A number that cannot belong to this run's stack. The lookup must answer "no",
        // not hand back whatever it found first.
        XCTAssertNil(service.stack(containingPR: 999_999, repoPath: repo))
    }

    // MARK: - Readiness

    func testReadiness_reportsEveryPullRequestInMergeOrder() async throws {
        let service = StackMergeReadinessService()

        let readiness = try await service.readiness(
            repoPath: repo, prNumbers: [lowerPR, upperPR])

        // Order is the contract: the fan-out is concurrent, and this is the order the
        // merge sheet lists and gh-stack merges in.
        XCTAssertEqual(readiness.prs.map(\.number), [lowerPR, upperPR])
        XCTAssertFalse(readiness.prs.contains { $0.blocksStackMerge })
        XCTAssertNil(readiness.blocker, "a stack of open, ready PRs must not report a blocker")
        // Display only, but the sheet states it as fact, so it must actually arrive.
        XCTAssertNotNil(
            readiness.defaultMergeMethod,
            "the repository's default merge method must be readable")
    }

    func testReadiness_identifiesADraftPartWayUpAsTheBlocker() async throws {
        // The case the merge sheet exists to catch: nothing above a draft can merge, so the
        // user is told before confirming rather than after gh-stack refuses.
        try await gh(["pr", "ready", String(upperPR), "--undo", "-R", slug], cwd: nil)

        let readiness = try await StackMergeReadinessService()
            .readiness(repoPath: repo, prNumbers: [lowerPR, upperPR])

        XCTAssertEqual(
            readiness.blocker?.number, upperPR, "the draft PR must be named as the blocker")
        let lower = try XCTUnwrap(readiness.prs.first { $0.number == lowerPR })
        XCTAssertFalse(
            lower.blocksStackMerge,
            "a ready PR below the draft must not itself be reported as blocking")
    }

    // MARK: - Helpers

    private func branch(_ suffix: String) -> String { "termq-live-\(runID!)-\(suffix)" }

    private func pullRequestNumber(head: String) async throws -> Int {
        let output = try await gh(
            ["pr", "list", "-R", slug, "--head", head, "--state", "all", "--json", "number"],
            cwd: nil)
        struct Row: Decodable { let number: Int }
        let rows = try JSONDecoder().decode([Row].self, from: Data(output.utf8))
        return try XCTUnwrap(rows.first?.number, "no pull request found for \(head)")
    }

    @discardableResult
    private func gh(_ arguments: [String], cwd: String?) async throws -> String {
        let result = try await StackProcessRunner.run(ghPath, arguments, cwd: cwd, env: [:])
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
    private func git(_ arguments: [String]) async throws -> String {
        guard let gitPath = GitServiceShared.findGitPath() else { throw XCTSkip("git not found") }
        let result = try await StackProcessRunner.run(gitPath, arguments, cwd: repo, env: [:])
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
}
