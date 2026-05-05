import Foundation
import TermQShared
import XCTest

@testable import TermQ

/// Stub `YNHCommandRunner` that records invocations and returns a canned
/// `CommandRunner.Result`. Tests inject this to exercise the success and
/// failure branches of `HarnessSearchService.search` without spawning a
/// real `ynh` subprocess.
private final class StubYNHCommandRunner: YNHCommandRunner, @unchecked Sendable {
    enum Outcome {
        case stdout(String, exitCode: Int32 = 0)
        case failure(stderr: String, exitCode: Int32)
        case throwing(Error)
    }

    var outcome: Outcome
    private(set) var capturedArguments: [[String]] = []
    private(set) var capturedEnvironment: [String: String]?

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        currentDirectory: String?,
        onStdoutLine: (@Sendable (String) -> Void)?,
        onStderrLine: (@Sendable (String) -> Void)?
    ) async throws -> CommandRunner.Result {
        capturedArguments.append(arguments)
        capturedEnvironment = environment
        switch outcome {
        case .stdout(let stdout, let exit):
            return CommandRunner.Result(exitCode: exit, stdout: stdout, stderr: "", duration: 0)
        case .failure(let stderr, let exit):
            return CommandRunner.Result(exitCode: exit, stdout: "", stderr: stderr, duration: 0)
        case .throwing(let error):
            throw error
        }
    }
}

/// Tests for `HarnessSearchService`. Cover state management (`reset`),
/// the guard behaviour when the detector reports non-ready status, and —
/// via the injected `commandRunner` seam — the success and failure
/// branches of `search(_:)` without touching a real `ynh` binary.
@MainActor
final class HarnessSearchServiceTests: XCTestCase {

    // MARK: - Helpers

    private static let readyStatus = YNHStatus.ready(
        ynhPath: "/usr/local/bin/ynh",
        yndPath: "/usr/local/bin/ynd",
        paths: YNHPaths(
            home: "/tmp/ynh-home",
            config: "/tmp/ynh-home/config",
            harnesses: "/tmp/ynh-home/harnesses",
            symlinks: "/tmp/ynh-home/symlinks",
            cache: "/tmp/ynh-home/cache",
            run: "/tmp/ynh-home/run",
            bin: "/tmp/ynh-home/bin"
        )
    )

    private func makeService(
        runner: StubYNHCommandRunner,
        status: YNHStatus = HarnessSearchServiceTests.readyStatus
    ) -> HarnessSearchService {
        HarnessSearchService(
            ynhDetector: MockYNHDetector(status: status),
            commandRunner: runner
        )
    }

    /// Wait long enough for the 350ms debounce + the stub's synchronous
    /// completion. Tests that drive non-empty queries must wait this out.
    private func waitForDebouncedSearch() async {
        try? await Task.sleep(for: .milliseconds(450))
    }

    // MARK: - reset()

    func test_reset_clearsResults() async {
        let service = HarnessSearchService()
        // Trigger a search that will bail early (detector is `.missing`)
        service.search("anything")
        // Give the Task a tick to settle
        await Task.yield()
        service.reset()
        XCTAssertTrue(service.results.isEmpty)
    }

    func test_reset_clearsError() async {
        let service = HarnessSearchService()
        service.search("query")
        await Task.yield()
        service.reset()
        XCTAssertNil(service.error)
    }

    func test_reset_clearsIsSearching() async {
        let service = HarnessSearchService()
        service.search("query")
        await Task.yield()
        service.reset()
        XCTAssertFalse(service.isSearching)
    }

    func test_reset_isIdempotent() {
        let service = HarnessSearchService()
        service.reset()
        service.reset()
        XCTAssertTrue(service.results.isEmpty)
        XCTAssertFalse(service.isSearching)
        XCTAssertNil(service.error)
    }

    // MARK: - search() guard: detector not ready

    func test_search_whenDetectorNotReady_resultsAreEmpty() async {
        // YNHDetector.shared.status == .missing in test process → guard fires
        let service = HarnessSearchService()
        service.search("termq")
        // Allow the async Task to complete
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(service.results.isEmpty)
    }

    func test_search_emptyQuery_whenDetectorNotReady_resultsAreEmpty() async {
        let service = HarnessSearchService()
        service.search("")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(service.results.isEmpty)
    }

    func test_search_whitespaceOnlyQuery_whenDetectorNotReady_resultsAreEmpty() async {
        let service = HarnessSearchService()
        service.search("   ")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(service.results.isEmpty)
    }

    // MARK: - Initial state

    func test_initialState_resultsEmpty() {
        let service = HarnessSearchService()
        XCTAssertTrue(service.results.isEmpty)
    }

    func test_initialState_notSearching() {
        let service = HarnessSearchService()
        XCTAssertFalse(service.isSearching)
    }

    func test_initialState_noError() {
        let service = HarnessSearchService()
        XCTAssertNil(service.error)
    }

    // MARK: - search() success path (via injected command runner)

    func test_search_withResults_decodesAndPublishesThem() async {
        let json = """
            [
              {
                "name": "claude-flow",
                "description": "A flow harness",
                "keywords": ["claude"],
                "repo": null,
                "path": null,
                "vendors": ["claude"],
                "version": "1.0.0",
                "from": { "type": "registry", "name": "default" }
              }
            ]
            """
        let runner = StubYNHCommandRunner(outcome: .stdout(json))
        let service = makeService(runner: runner)

        service.search("claude")
        await waitForDebouncedSearch()

        XCTAssertEqual(service.results.count, 1)
        XCTAssertEqual(service.results.first?.name, "claude-flow")
        XCTAssertNil(service.error)
        XCTAssertFalse(service.isSearching)
        XCTAssertEqual(runner.capturedArguments.last, ["search", "claude", "--format", "json"])
    }

    func test_search_emptyQuery_browsesAllHarnesses() async {
        // Empty query has zero debounce and emits `["search", "--format", "json"]`
        // (no positional term). Verifies the args branch.
        let runner = StubYNHCommandRunner(outcome: .stdout("[]"))
        let service = makeService(runner: runner)

        service.search("")
        // No debounce on empty queries — settle the Task
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(service.results.isEmpty)
        XCTAssertNil(service.error)
        XCTAssertEqual(runner.capturedArguments.last, ["search", "--format", "json"])
    }

    func test_search_whitespaceOnlyQuery_treatedAsBrowse() async {
        let runner = StubYNHCommandRunner(outcome: .stdout("[]"))
        let service = makeService(runner: runner)

        service.search("   ")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(runner.capturedArguments.last, ["search", "--format", "json"])
    }

    // MARK: - search() failure paths

    func test_search_commandNonZeroExit_setsError() async {
        let runner = StubYNHCommandRunner(
            outcome: .failure(stderr: "something failed", exitCode: 2))
        let service = makeService(runner: runner)

        service.search("foo")
        await waitForDebouncedSearch()

        XCTAssertNotNil(service.error)
        XCTAssertTrue(service.results.isEmpty)
        XCTAssertFalse(service.isSearching)
    }

    func test_search_malformedJSON_setsError() async {
        let runner = StubYNHCommandRunner(outcome: .stdout("not valid json"))
        let service = makeService(runner: runner)

        service.search("foo")
        await waitForDebouncedSearch()

        XCTAssertNotNil(service.error)
        XCTAssertTrue(service.results.isEmpty)
    }

    func test_search_runnerThrows_setsError() async {
        struct TestError: Error {}
        let runner = StubYNHCommandRunner(outcome: .throwing(TestError()))
        let service = makeService(runner: runner)

        service.search("foo")
        await waitForDebouncedSearch()

        XCTAssertNotNil(service.error)
        XCTAssertTrue(service.results.isEmpty)
    }

    // MARK: - search() environment

    func test_search_passesYnhHomeOverrideToEnvironment() async {
        let runner = StubYNHCommandRunner(outcome: .stdout("[]"))
        let service = HarnessSearchService(
            ynhDetector: MockYNHDetector(
                status: HarnessSearchServiceTests.readyStatus,
                ynhHomeOverride: "/tmp/custom-ynh-home"),
            commandRunner: runner
        )

        service.search("foo")
        await waitForDebouncedSearch()

        XCTAssertEqual(runner.capturedEnvironment?["YNH_HOME"], "/tmp/custom-ynh-home")
    }

    // MARK: - search() task cancellation

    func test_search_subsequentCallCancelsPrevious() async {
        let runner = StubYNHCommandRunner(outcome: .stdout("[]"))
        let service = makeService(runner: runner)

        service.search("first")
        // Issue the second call before debounce elapses for the first.
        try? await Task.sleep(for: .milliseconds(100))
        service.search("second")
        await waitForDebouncedSearch()

        // Only the second call's args should reach the runner — the first
        // is cancelled during its sleep.
        XCTAssertEqual(runner.capturedArguments.count, 1)
        XCTAssertEqual(runner.capturedArguments.last, ["search", "second", "--format", "json"])
    }
}
