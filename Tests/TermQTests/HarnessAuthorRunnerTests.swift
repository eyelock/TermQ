import Foundation
import XCTest

@testable import TermQ

/// Exercises the six ynh-subprocess runners (`HarnessAuthor`,
/// `MarketplaceAddRunner`, `IncludeMutator`, `DelegateMutator`,
/// `YNHMarketplaceService`, `IncludeApplier`) via the injected
/// `YNHCommandRunner` seam — no real `ynh`/`ynd` process is spawned.
@MainActor
final class HarnessAuthorRunnerTests: XCTestCase {

    // MARK: - HarnessAuthor

    func test_harnessAuthor_create_succeeds_setsSucceededAndCapturesOutput() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .stdout("created harness foo")

        let author = HarnessAuthor(commandRunner: runner)
        await author.run(
            HarnessCreationOptions(
                name: "foo", description: "desc", vendorID: "claude",
                destination: "/tmp/harnesses", install: false
            ),
            binaries: YNHBinaries(yndPath: "/bin/ynd", ynhPath: "/bin/ynh"),
            environment: [:]
        )

        XCTAssertTrue(author.succeeded)
        XCTAssertEqual(author.createdHarnessName, "foo")
        XCTAssertEqual(author.steps.count, 1)
        await pollUntil { author.outputLines.contains("created harness foo") }
    }

    func test_harnessAuthor_createFails_doesNotInstall_andDoesNotSucceed() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .failure(stderr: "no vendor", exitCode: 2)

        let author = HarnessAuthor(commandRunner: runner)
        await author.run(
            HarnessCreationOptions(
                name: "foo", description: "", vendorID: "",
                destination: "/tmp", install: true  // install=true but create should fail first
            ),
            binaries: YNHBinaries(yndPath: "/bin/ynd", ynhPath: "/bin/ynh"),
            environment: [:]
        )

        XCTAssertFalse(author.succeeded)
        XCTAssertNil(author.createdHarnessName)
        // Only the create call should have been attempted
        XCTAssertEqual(runner.capturedInvocations.count, 1)
        XCTAssertEqual(runner.capturedInvocations[0].executable, "/bin/ynd")
    }

    func test_harnessAuthor_create_passesDescriptionAndVendorArgs() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .stdout("ok")

        let author = HarnessAuthor(commandRunner: runner)
        await author.run(
            HarnessCreationOptions(
                name: "foo", description: "my desc", vendorID: "claude",
                destination: "/tmp", install: false
            ),
            binaries: YNHBinaries(yndPath: "/bin/ynd", ynhPath: "/bin/ynh"),
            environment: ["FOO": "bar"]
        )

        let invocation = runner.capturedInvocations.first
        XCTAssertEqual(
            invocation?.arguments,
            ["create", "harness", "foo", "--description", "my desc", "--vendor", "claude"]
        )
        XCTAssertEqual(invocation?.environment?["FOO"], "bar")
    }

    // MARK: - MarketplaceAddRunner

    func test_marketplaceAddRunner_succeeds_setsSucceeded() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .stdout("registry added")

        let mp = MarketplaceAddRunner(commandRunner: runner)
        await mp.run(ynhPath: "/bin/ynh", url: "https://example.com/m", environment: [:])

        XCTAssertTrue(mp.succeeded)
        XCTAssertNil(mp.errorMessage)
        XCTAssertEqual(runner.capturedInvocations.first?.arguments, ["registry", "add", "https://example.com/m"])
    }

    func test_marketplaceAddRunner_fails_setsErrorMessage() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .failure(stderr: "bad url", exitCode: 1)

        let mp = MarketplaceAddRunner(commandRunner: runner)
        await mp.run(ynhPath: "/bin/ynh", url: "bogus", environment: [:])

        XCTAssertFalse(mp.succeeded)
        XCTAssertNotNil(mp.errorMessage)
    }

    // MARK: - IncludeMutator

    func test_includeMutator_buildIncludeRemoveArgs_omitsPathWhenEmpty() {
        let args = IncludeMutator.buildIncludeRemoveArgs(
            IncludeRemoveOptions(harness: "h", sourceURL: "u", path: nil))
        XCTAssertEqual(args, ["include", "remove", "h", "u"])
    }

    func test_includeMutator_buildIncludeRemoveArgs_includesPathWhenSet() {
        let args = IncludeMutator.buildIncludeRemoveArgs(
            IncludeRemoveOptions(harness: "h", sourceURL: "u", path: "sub"))
        XCTAssertEqual(args, ["include", "remove", "h", "u", "--path", "sub"])
    }

    func test_includeMutator_buildIncludeUpdateArgs_assemblesAllOptionalFlags() {
        let args = IncludeMutator.buildIncludeUpdateArgs(
            IncludeUpdateOptions(
                harness: "h", sourceURL: "u",
                fromPath: "old", path: "new",
                pick: ["skills/foo", "agents/bar.md"], ref: "main"
            )
        )
        XCTAssertEqual(
            args,
            [
                "include", "update", "h", "u",
                "--from-path", "old",
                "--path", "new",
                "--pick", "skills/foo,agents/bar.md",
                "--ref", "main",
            ]
        )
    }

    func test_includeMutator_remove_succeeds() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .stdout("removed")

        let mut = IncludeMutator(commandRunner: runner)
        await mut.remove(
            IncludeRemoveOptions(harness: "h", sourceURL: "u", path: nil),
            ynhPath: "/bin/ynh", environment: [:]
        )

        XCTAssertTrue(mut.succeeded)
    }

    func test_includeMutator_update_failure_setsErrorMessage() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .failure(stderr: "conflict", exitCode: 3)

        let mut = IncludeMutator(commandRunner: runner)
        await mut.update(
            IncludeUpdateOptions(harness: "h", sourceURL: "u", fromPath: nil, path: nil, pick: [], ref: nil),
            ynhPath: "/bin/ynh", environment: [:]
        )

        XCTAssertFalse(mut.succeeded)
        XCTAssertNotNil(mut.errorMessage)
    }

    // MARK: - DelegateMutator

    func test_delegateMutator_buildDelegateAddArgs_includesRefAndPath() {
        let args = DelegateMutator.buildDelegateAddArgs(
            DelegateAddOptions(harness: "h", sourceURL: "u", ref: "v1", path: "p")
        )
        XCTAssertEqual(args, ["delegate", "add", "h", "u", "--ref", "v1", "--path", "p"])
    }

    func test_delegateMutator_buildDelegateUpdateArgs_assemblesAllFlags() {
        let args = DelegateMutator.buildDelegateUpdateArgs(
            DelegateUpdateOptions(harness: "h", sourceURL: "u", fromPath: "f", path: "p", ref: "r")
        )
        XCTAssertEqual(
            args,
            ["delegate", "update", "h", "u", "--from-path", "f", "--path", "p", "--ref", "r"]
        )
    }

    func test_delegateMutator_add_succeeds() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .stdout("ok")

        let mut = DelegateMutator(commandRunner: runner)
        await mut.add(
            DelegateAddOptions(harness: "h", sourceURL: "u", ref: nil, path: nil),
            ynhPath: "/bin/ynh", environment: [:]
        )

        XCTAssertTrue(mut.succeeded)
        XCTAssertEqual(runner.capturedInvocations.first?.arguments, ["delegate", "add", "h", "u"])
    }

    // MARK: - YNHMarketplaceService

    func test_marketplaceService_refresh_decodesJSON() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .stdout(
            #"[{"url":"https://example.com/m","name":"Example","description":"d","ref":null}]"#)

        let service = YNHMarketplaceService(commandRunner: runner)
        await service.refresh(ynhPath: "/bin/ynh", environment: [:])

        XCTAssertEqual(service.marketplaces.count, 1)
        XCTAssertEqual(service.marketplaces.first?.url, "https://example.com/m")
        XCTAssertEqual(runner.capturedInvocations.first?.arguments, ["registry", "list", "--format", "json"])
    }

    func test_marketplaceService_refresh_nonZeroExit_leavesEmpty() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .failure(stderr: "no", exitCode: 1)

        let service = YNHMarketplaceService(commandRunner: runner)
        await service.refresh(ynhPath: "/bin/ynh", environment: [:])

        XCTAssertTrue(service.marketplaces.isEmpty)
    }

    func test_marketplaceService_remove_invokesRemoveAndRefresh() async {
        let runner = StubCommandRunner()
        runner.outcomes["registry"] = .stdout("[]")  // refresh after remove
        runner.defaultOutcome = .stdout("[]")

        let service = YNHMarketplaceService(commandRunner: runner)
        await service.remove(url: "https://example.com/m", ynhPath: "/bin/ynh", environment: [:])

        // Two invocations: remove, then refresh
        XCTAssertGreaterThanOrEqual(runner.capturedInvocations.count, 2)
        XCTAssertEqual(
            runner.capturedInvocations[0].arguments,
            ["registry", "remove", "https://example.com/m"]
        )
        XCTAssertEqual(
            runner.capturedInvocations[1].arguments,
            ["registry", "list", "--format", "json"]
        )
    }

    // MARK: - IncludeApplier

    func test_includeApplier_buildIncludeAddArgs_omitsEmptyPickAndPath() {
        let args = IncludeApplier.buildIncludeAddArgs(
            IncludeApplicationOptions(harness: "h", sourceURL: "u", path: nil, pick: [])
        )
        XCTAssertEqual(args, ["include", "add", "h", "u"])
    }

    func test_includeApplier_buildIncludeAddArgs_includesPickJoinedWithComma() {
        let args = IncludeApplier.buildIncludeAddArgs(
            IncludeApplicationOptions(
                harness: "h", sourceURL: "u", path: "p",
                pick: ["skills/foo", "agents/bar.md"]
            )
        )
        XCTAssertEqual(
            args,
            ["include", "add", "h", "u", "--path", "p", "--pick", "skills/foo,agents/bar.md"]
        )
    }

    func test_includeApplier_apply_succeeds() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .stdout("included")

        let applier = IncludeApplier(commandRunner: runner)
        await applier.apply(
            IncludeApplicationOptions(harness: "h", sourceURL: "u", path: nil, pick: []),
            ynhPath: "/bin/ynh", environment: [:]
        )

        XCTAssertTrue(applier.succeeded)
    }

    func test_includeApplier_apply_failure_setsErrorMessage() async {
        let runner = StubCommandRunner()
        runner.defaultOutcome = .failure(stderr: "bad", exitCode: 1)

        let applier = IncludeApplier(commandRunner: runner)
        await applier.apply(
            IncludeApplicationOptions(harness: "h", sourceURL: "u", path: nil, pick: []),
            ynhPath: "/bin/ynh", environment: [:]
        )

        XCTAssertFalse(applier.succeeded)
        XCTAssertNotNil(applier.errorMessage)
    }

    // MARK: - Helper

    /// Output lines arrive via `Task { @MainActor }` hops from the runner's
    /// background callback, so polling on the main actor is needed to observe
    /// them deterministically.
    private func pollUntil(
        timeout: Duration = .seconds(2),
        _ predicate: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
