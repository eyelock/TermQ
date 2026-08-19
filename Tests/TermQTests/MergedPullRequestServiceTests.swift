import Foundation
import TermQShared
import XCTest

@testable import TermQ

/// Covers the service that answers "which pull requests are merged".
///
/// gh-stack's tracking file records a pull request number and nothing about its state, and
/// the stack graph is built from that file, so a merged stack rendered as open
/// indefinitely: the merge confirmation said "Already merged" against every pull request
/// while the sidebar behind it still showed them live.
///
/// Fetched rather than remembered. An in-memory note of what this process merged is wrong
/// after a restart, and wrong for a stack merged on github.com or by a teammate — both of
/// which were observed before this replaced that approach.
@MainActor
final class MergedPullRequestServiceTests: XCTestCase {

    /// Records what it was asked to run, so the tests can assert the SHAPE of the query
    /// and not merely its result.
    private final class RecordingRunner: YNHCommandRunner, @unchecked Sendable {
        var stdout: String = "[]"
        var exitCode: Int32 = 0
        private(set) var invocations: [[String]] = []

        // swiftlint:disable:next function_parameter_count
        func run(
            executable: String,
            arguments: [String],
            environment: [String: String]?,
            currentDirectory: String?,
            onStdoutLine: (@Sendable (String) -> Void)?,
            onStderrLine: (@Sendable (String) -> Void)?
        ) async throws -> CommandRunner.Result {
            invocations.append(arguments)
            return CommandRunner.Result(
                exitCode: exitCode, stdout: stdout, stderr: "", duration: 0)
        }
    }

    private func makeService(_ runner: RecordingRunner) -> MergedPullRequestService {
        MergedPullRequestService(ghPathProvider: { "/usr/bin/gh" }, commandRunner: runner)
    }

    func testMergedNumbersAreReadFromTheRepository() async {
        let runner = RecordingRunner()
        runner.stdout = #"[{"number":126},{"number":127},{"number":128}]"#
        let service = makeService(runner)

        await service.refresh(repoPath: "/repo", force: true)

        XCTAssertEqual(service.mergedNumbers(repoPath: "/repo"), [126, 127, 128])
    }

    /// One bounded call, not a per-PR fan-out: this is paid on every stack refresh, unlike
    /// the readiness fetch that runs once when a merge sheet opens.
    func testItAsksForMergedPullRequestsInOneBoundedCall() async throws {
        let runner = RecordingRunner()
        let service = makeService(runner)

        await service.refresh(repoPath: "/repo", force: true)

        XCTAssertEqual(runner.invocations.count, 1, "it must not fan out per pull request")
        let args = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(args.first, "pr")
        XCTAssertTrue(args.contains("merged"), "arguments were: \(args)")
        XCTAssertTrue(args.contains("--limit"), "the query must be bounded")
    }

    /// A transient gh failure must not report merged pull requests as open again — that is
    /// precisely the regression this service exists to fix.
    func testAFailedFetchKeepsWhatIsAlreadyKnown() async {
        let runner = RecordingRunner()
        runner.stdout = #"[{"number":126}]"#
        let service = makeService(runner)
        await service.refresh(repoPath: "/repo", force: true)

        runner.stdout = ""
        runner.exitCode = 1
        await service.refresh(repoPath: "/repo", force: true)

        XCTAssertEqual(
            service.mergedNumbers(repoPath: "/repo"), [126],
            "a failed fetch must not flip merged pull requests back to open")
    }

    func testTheTTLAbsorbsRepeatedRefreshes() async {
        let runner = RecordingRunner()
        let service = makeService(runner)

        await service.refresh(repoPath: "/repo", force: true)
        await service.refresh(repoPath: "/repo")
        await service.refresh(repoPath: "/repo")

        XCTAssertEqual(runner.invocations.count, 1, "the TTL should absorb the repeats")
    }

    func testAnUnresolvedGhBinaryYieldsNothingRatherThanFailing() async {
        let runner = RecordingRunner()
        let service = MergedPullRequestService(
            ghPathProvider: { nil }, commandRunner: runner)

        await service.refresh(repoPath: "/repo", force: true)

        XCTAssertTrue(service.mergedNumbers(repoPath: "/repo").isEmpty)
        XCTAssertTrue(runner.invocations.isEmpty, "it should not shell out with no gh path")
    }

    func testEvictForgetsTheRepository() async {
        let runner = RecordingRunner()
        runner.stdout = #"[{"number":1}]"#
        let service = makeService(runner)
        await service.refresh(repoPath: "/repo", force: true)

        service.evict(repoPath: "/repo")

        XCTAssertTrue(service.mergedNumbers(repoPath: "/repo").isEmpty)
    }
}
