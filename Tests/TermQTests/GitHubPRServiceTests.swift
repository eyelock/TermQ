import Foundation
import TermQShared
import XCTest

@testable import TermQ

// MARK: - Stub command runner

/// Returns a canned result for every command invocation.
final class StubGhCommandRunner: YNHCommandRunner, @unchecked Sendable {
    nonisolated(unsafe) var result: CommandRunner.Result

    init(json: String, exitCode: Int32 = 0) {
        result = CommandRunner.Result(
            exitCode: exitCode,
            stdout: json,
            stderr: "",
            duration: 0
        )
    }

    init(stdout: String = "", stderr: String = "", exitCode: Int32 = 1) {
        result = CommandRunner.Result(
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
            duration: 0
        )
    }

    nonisolated func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        currentDirectory: String?,
        onStdoutLine: (@Sendable (String) -> Void)?,
        onStderrLine: (@Sendable (String) -> Void)?
    ) async throws -> CommandRunner.Result {
        result
    }
}

// MARK: - Canned fixtures

private let singlePRJSON = """
    [
      {
        "number": 42,
        "title": "Fix yaml parsing",
        "headRefName": "fix/yaml",
        "headRefOid": "abc1234567890",
        "author": {"login": "alice"},
        "isCrossRepository": false,
        "isDraft": false,
        "reviewRequests": [{"login": "bob"}],
        "assignees": []
      }
    ]
    """

private let crossRepoPRJSON = """
    [
      {
        "number": 99,
        "title": "Fork PR",
        "headRefName": "feature",
        "headRefOid": "deadbeef1234",
        "author": {"login": "external-dev"},
        "isCrossRepository": true,
        "isDraft": false,
        "reviewRequests": [],
        "assignees": [{"login": "alice"}]
      }
    ]
    """

private let emptyJSON = "[]"

// MARK: - Tests

@MainActor
final class GitHubPRServiceDecodeTests: XCTestCase {

    func test_singlePR_decodesCorrectly() throws {
        let prs = try JSONDecoder().decode([GitHubPR].self, from: Data(singlePRJSON.utf8))
        XCTAssertEqual(prs.count, 1)
        let pr = prs[0]
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.title, "Fix yaml parsing")
        XCTAssertEqual(pr.headRefName, "fix/yaml")
        XCTAssertEqual(pr.headRefOid, "abc1234567890")
        XCTAssertEqual(pr.author.login, "alice")
        XCTAssertFalse(pr.isCrossRepository)
        XCTAssertFalse(pr.isDraft)
        XCTAssertEqual(pr.reviewRequests.count, 1)
        XCTAssertEqual(pr.reviewRequests[0].login, "bob")
    }

    func test_sameRepoPR_localBranchIsHeadRefName() throws {
        let prs = try JSONDecoder().decode([GitHubPR].self, from: Data(singlePRJSON.utf8))
        XCTAssertEqual(prs[0].localBranchName(), "fix/yaml")
    }

    func test_crossRepoPR_localBranchUsesAuthorPrefix() throws {
        let prs = try JSONDecoder().decode([GitHubPR].self, from: Data(crossRepoPRJSON.utf8))
        XCTAssertEqual(prs[0].localBranchName(), "external-dev-feature")
    }

    func test_emptyArray_decodesSuccessfully() throws {
        let prs = try JSONDecoder().decode([GitHubPR].self, from: Data(emptyJSON.utf8))
        XCTAssertTrue(prs.isEmpty)
    }
}

@MainActor
final class GitHubPRServiceRefreshTests: XCTestCase {

    func test_refresh_whenGhMissing_doesNotLoad() async {
        let probe = GhCliProbe()
        // probe.status defaults to .missing
        let runner = StubGhCommandRunner(json: singlePRJSON)
        let service = GitHubPRService(ghProbe: probe, commandRunner: runner)

        await service.refresh(repoPath: "/tmp/repo")

        XCTAssertNil(service.prsByRepo["/tmp/repo"])
        XCTAssertFalse(service.loadingRepos.contains("/tmp/repo"))
    }

    func test_refresh_whenCommandFails_setsError() async {
        let probe = GhCliProbe()
        await probe.setStatusForTesting(GhCliStatus.ready(ghPath: "/usr/bin/gh", login: "alice"))
        let runner = StubGhCommandRunner(stderr: "no remote", exitCode: 1)
        let service = GitHubPRService(ghProbe: probe, commandRunner: runner)

        await service.refresh(repoPath: "/tmp/repo")

        XCTAssertNotNil(service.errorByRepo["/tmp/repo"])
        XCTAssertNil(service.prsByRepo["/tmp/repo"])
    }

    func test_refresh_populatesPRs() async {
        let probe = GhCliProbe()
        await probe.setStatusForTesting(GhCliStatus.ready(ghPath: "/usr/bin/gh", login: "alice"))
        let runner = StubGhCommandRunner(json: singlePRJSON)
        let service = GitHubPRService(ghProbe: probe, commandRunner: runner)

        await service.refresh(repoPath: "/tmp/repo")

        let prs = service.prsByRepo["/tmp/repo"]
        XCTAssertEqual(prs?.count, 1)
        XCTAssertEqual(prs?.first?.number, 42)
    }

    func test_refresh_withinTTL_doesNotRefetch() async {
        let probe = GhCliProbe()
        await probe.setStatusForTesting(GhCliStatus.ready(ghPath: "/usr/bin/gh", login: "alice"))
        nonisolated(unsafe) var callCount = 0
        let runner = CountingStubRunner(json: singlePRJSON, onCall: { callCount += 1 })
        let service = GitHubPRService(ghProbe: probe, commandRunner: runner)

        await service.refresh(repoPath: "/tmp/repo")
        await service.refresh(repoPath: "/tmp/repo")  // should be a no-op (within TTL)

        XCTAssertEqual(callCount, 1)
    }

    func test_refresh_forceBypassesTTL() async {
        let probe = GhCliProbe()
        await probe.setStatusForTesting(GhCliStatus.ready(ghPath: "/usr/bin/gh", login: "alice"))
        nonisolated(unsafe) var callCount = 0
        let runner = CountingStubRunner(json: singlePRJSON, onCall: { callCount += 1 })
        let service = GitHubPRService(ghProbe: probe, commandRunner: runner)

        await service.refresh(repoPath: "/tmp/repo")
        await service.refresh(repoPath: "/tmp/repo", force: true)

        XCTAssertEqual(callCount, 2)
    }

    func test_evict_removesAllState() async {
        let probe = GhCliProbe()
        await probe.setStatusForTesting(GhCliStatus.ready(ghPath: "/usr/bin/gh", login: "alice"))
        let runner = StubGhCommandRunner(json: singlePRJSON)
        let service = GitHubPRService(ghProbe: probe, commandRunner: runner)

        await service.refresh(repoPath: "/tmp/repo")
        XCTAssertNotNil(service.prsByRepo["/tmp/repo"])

        service.evict(repoPath: "/tmp/repo")
        XCTAssertNil(service.prsByRepo["/tmp/repo"])
    }
}

@MainActor
final class PRWorktreeMatchTests: XCTestCase {

    func test_matchBySHA() throws {
        let prs = try JSONDecoder().decode([GitHubPR].self, from: Data(singlePRJSON.utf8))
        let worktrees = [
            GitWorktree(
                path: "/repo/.worktrees/fix-yaml",
                branch: "fix/yaml",
                commitHash: "abc1234",
                isMainWorktree: false,
                isLocked: false,
                isDirty: false
            )
        ]
        let matches = GitHubPRService.matchPRsToWorktrees(prs: prs, worktrees: worktrees)
        XCTAssertEqual(matches[42], "/repo/.worktrees/fix-yaml")
    }

    func test_matchByBranchFallback() throws {
        let prs = try JSONDecoder().decode([GitHubPR].self, from: Data(singlePRJSON.utf8))
        let worktrees = [
            GitWorktree(
                path: "/repo/.worktrees/fix-yaml",
                branch: "fix/yaml",
                commitHash: "999000",  // SHA doesn't match
                isMainWorktree: false,
                isLocked: false,
                isDirty: false
            )
        ]
        let matches = GitHubPRService.matchPRsToWorktrees(prs: prs, worktrees: worktrees)
        XCTAssertEqual(matches[42], "/repo/.worktrees/fix-yaml")
    }

    func test_noMatch_returnsEmpty() throws {
        let prs = try JSONDecoder().decode([GitHubPR].self, from: Data(singlePRJSON.utf8))
        let worktrees = [
            GitWorktree(
                path: "/repo/.worktrees/unrelated",
                branch: "unrelated",
                commitHash: "000000",
                isMainWorktree: false,
                isLocked: false,
                isDirty: false
            )
        ]
        let matches = GitHubPRService.matchPRsToWorktrees(prs: prs, worktrees: worktrees)
        XCTAssertNil(matches[42])
    }

    func test_crossRepoPR_matchesByBranchWithAuthorPrefix() throws {
        let prs = try JSONDecoder().decode([GitHubPR].self, from: Data(crossRepoPRJSON.utf8))
        let worktrees = [
            GitWorktree(
                path: "/repo/.worktrees/fork-pr",
                branch: "external-dev-feature",
                commitHash: "deadbeef",
                isMainWorktree: false,
                isLocked: false,
                isDirty: false
            )
        ]
        let matches = GitHubPRService.matchPRsToWorktrees(prs: prs, worktrees: worktrees)
        XCTAssertEqual(matches[99], "/repo/.worktrees/fork-pr")
    }
}

// MARK: - Counting stub

final class CountingStubRunner: YNHCommandRunner, @unchecked Sendable {
    private let json: String
    nonisolated(unsafe) private var callCount = 0
    private let onCallBlock: () -> Void

    init(json: String, onCall: @escaping () -> Void) {
        self.json = json
        self.onCallBlock = onCall
    }

    nonisolated func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        currentDirectory: String?,
        onStdoutLine: (@Sendable (String) -> Void)?,
        onStderrLine: (@Sendable (String) -> Void)?
    ) async throws -> CommandRunner.Result {
        onCallBlock()
        return CommandRunner.Result(exitCode: 0, stdout: json, stderr: "", duration: 0)
    }
}
