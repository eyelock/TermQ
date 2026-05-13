import Foundation
import XCTest

@testable import TermQ

// MARK: - Shared stub

/// Minimal `YNHCommandRunner` stub for mutator tests.
/// Records arguments and returns a canned result — no subprocess is spawned.
private final class MutatorStubRunner: YNHCommandRunner, @unchecked Sendable {
    enum Outcome {
        case success(stdout: String = "")
        case failure(stderr: String, exitCode: Int32 = 1)
        case throwing(Error)
    }

    var outcome: Outcome = .success()
    private(set) var capturedArgs: [[String]] = []

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        currentDirectory: String?,
        onStdoutLine: (@Sendable (String) -> Void)?,
        onStderrLine: (@Sendable (String) -> Void)?
    ) async throws -> CommandRunner.Result {
        capturedArgs.append(arguments)
        switch outcome {
        case .success(let stdout):
            for line in stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
                onStdoutLine?(line)
            }
            return CommandRunner.Result(exitCode: 0, stdout: stdout, stderr: "", duration: 0)
        case .failure(let stderr, let code):
            onStderrLine?(stderr)
            return CommandRunner.Result(exitCode: code, stdout: "", stderr: stderr, duration: 0)
        case .throwing(let error):
            throw error
        }
    }
}

private struct TestError: Error {}

// MARK: - FocusMutator — arg builder tests

final class FocusMutatorArgTests: XCTestCase {

    func test_buildAddArgs_basic() {
        let args = FocusMutator.buildAddArgs(
            FocusAddOptions(harness: "local/h", name: "my-focus", prompt: "the prompt", profile: nil)
        )
        XCTAssertEqual(args, ["focus", "add", "local/h", "my-focus", "the prompt"])
    }

    func test_buildAddArgs_withProfile() {
        let args = FocusMutator.buildAddArgs(
            FocusAddOptions(harness: "local/h", name: "f", prompt: "p", profile: "dev")
        )
        XCTAssertEqual(args, ["focus", "add", "local/h", "f", "p", "--profile", "dev"])
    }

    func test_buildAddArgs_emptyProfileOmitted() {
        let args = FocusMutator.buildAddArgs(
            FocusAddOptions(harness: "local/h", name: "f", prompt: "p", profile: "")
        )
        XCTAssertFalse(args.contains("--profile"))
    }

    func test_buildRemoveArgs() {
        let args = FocusMutator.buildRemoveArgs(
            FocusRemoveOptions(harness: "local/h", name: "my-focus")
        )
        XCTAssertEqual(args, ["focus", "remove", "local/h", "my-focus"])
    }

    func test_buildUpdateArgs_noChanges() {
        let args = FocusMutator.buildUpdateArgs(
            FocusUpdateOptions(harness: "local/h", name: "f", prompt: nil, profile: nil, clearProfile: false)
        )
        XCTAssertEqual(args, ["focus", "update", "local/h", "f"])
    }

    func test_buildUpdateArgs_withPrompt() {
        let args = FocusMutator.buildUpdateArgs(
            FocusUpdateOptions(harness: "local/h", name: "f", prompt: "new prompt", profile: nil, clearProfile: false)
        )
        XCTAssertEqual(args, ["focus", "update", "local/h", "f", "--prompt", "new prompt"])
    }

    func test_buildUpdateArgs_emptyProfileWithoutClear_omitted() {
        let args = FocusMutator.buildUpdateArgs(
            FocusUpdateOptions(harness: "local/h", name: "f", prompt: nil, profile: "", clearProfile: false)
        )
        XCTAssertFalse(args.contains("--profile"))
        XCTAssertFalse(args.contains("--clear-profile"))
    }

    func test_buildUpdateArgs_emptyPromptOmitted() {
        let args = FocusMutator.buildUpdateArgs(
            FocusUpdateOptions(harness: "local/h", name: "f", prompt: "", profile: nil, clearProfile: false)
        )
        XCTAssertFalse(args.contains("--prompt"))
    }

    func test_buildUpdateArgs_withProfile() {
        let args = FocusMutator.buildUpdateArgs(
            FocusUpdateOptions(harness: "local/h", name: "f", prompt: nil, profile: "dev", clearProfile: false)
        )
        XCTAssertEqual(args, ["focus", "update", "local/h", "f", "--profile", "dev"])
    }

    func test_buildUpdateArgs_clearProfile() {
        let args = FocusMutator.buildUpdateArgs(
            FocusUpdateOptions(harness: "local/h", name: "f", prompt: nil, profile: "dev", clearProfile: true)
        )
        XCTAssertTrue(args.contains("--clear-profile"))
        XCTAssertFalse(args.contains("--profile"))
    }
}

// MARK: - FocusMutator — run state tests

@MainActor
final class FocusMutatorStateTests: XCTestCase {

    func test_add_success_setsSuceeded() async {
        let stub = MutatorStubRunner()
        stub.outcome = .success(stdout: "Added focus")
        let mutator = FocusMutator(commandRunner: stub)
        await mutator.add(
            FocusAddOptions(harness: "local/h", name: "f", prompt: "p", profile: nil),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertTrue(mutator.succeeded)
        XCTAssertNil(mutator.errorMessage)
        XCTAssertFalse(mutator.isRunning)
    }

    func test_add_failure_setsErrorMessage() async {
        let stub = MutatorStubRunner()
        stub.outcome = .failure(stderr: "Error: focus already exists")
        let mutator = FocusMutator(commandRunner: stub)
        await mutator.add(
            FocusAddOptions(harness: "local/h", name: "f", prompt: "p", profile: nil),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertFalse(mutator.succeeded)
        XCTAssertEqual(mutator.errorMessage, "Error: focus already exists")
    }

    func test_remove_success_setsSuceeded() async {
        let stub = MutatorStubRunner()
        let mutator = FocusMutator(commandRunner: stub)
        await mutator.remove(
            FocusRemoveOptions(harness: "local/h", name: "f"),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertTrue(mutator.succeeded)
    }

    func test_update_success_setsSuceeded() async {
        let stub = MutatorStubRunner()
        let mutator = FocusMutator(commandRunner: stub)
        await mutator.update(
            FocusUpdateOptions(harness: "local/h", name: "f", prompt: "new", profile: nil, clearProfile: false),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertTrue(mutator.succeeded)
    }

    func test_throwing_runner_setsErrorMessage() async {
        let stub = MutatorStubRunner()
        stub.outcome = .throwing(TestError())
        let mutator = FocusMutator(commandRunner: stub)
        await mutator.add(
            FocusAddOptions(harness: "local/h", name: "f", prompt: "p", profile: nil),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertFalse(mutator.succeeded)
        XCTAssertNotNil(mutator.errorMessage)
    }

    func test_secondRun_clearsPriorState() async {
        let stub = MutatorStubRunner()
        stub.outcome = .failure(stderr: "Error: old error")
        let mutator = FocusMutator(commandRunner: stub)
        await mutator.add(
            FocusAddOptions(harness: "local/h", name: "f", prompt: "p", profile: nil),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertNotNil(mutator.errorMessage)

        stub.outcome = .success()
        await mutator.add(
            FocusAddOptions(harness: "local/h", name: "f2", prompt: "p", profile: nil),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertNil(mutator.errorMessage)
        XCTAssertTrue(mutator.succeeded)
    }
}

// MARK: - HarnessHookMutator — arg builder tests

final class HarnessHookMutatorArgTests: XCTestCase {

    func test_buildMCPAddArgs_commandOnly() {
        let args = HarnessHookMutator.buildMCPAddArgs(
            HarnessMCPAddOptions(
                harness: "local/h", serverName: "github",
                command: "gh", args: [], env: [:], url: nil, headers: [:]
            )
        )
        XCTAssertEqual(args, ["mcp", "add", "local/h", "github", "--command", "gh"])
    }

    func test_buildMCPAddArgs_withArgs() {
        let args = HarnessHookMutator.buildMCPAddArgs(
            HarnessMCPAddOptions(
                harness: "local/h", serverName: "s",
                command: "npx", args: ["--port", "8080"], env: [:], url: nil, headers: [:]
            )
        )
        XCTAssertEqual(
            args,
            ["mcp", "add", "local/h", "s", "--command", "npx", "--arg", "--port", "--arg", "8080"]
        )
    }

    func test_buildMCPAddArgs_envSortedByKey() {
        let args = HarnessHookMutator.buildMCPAddArgs(
            HarnessMCPAddOptions(
                harness: "local/h", serverName: "s",
                command: "cmd", args: [], env: ["Z": "1", "A": "2"], url: nil, headers: [:]
            )
        )
        let envIdx = args.firstIndex(of: "--env")!
        XCTAssertEqual(args[envIdx + 1], "A=2")
    }

    func test_buildMCPAddArgs_url() {
        let args = HarnessHookMutator.buildMCPAddArgs(
            HarnessMCPAddOptions(
                harness: "local/h", serverName: "s",
                command: nil, args: [], env: [:], url: "https://example.com/sse", headers: [:]
            )
        )
        XCTAssertEqual(args, ["mcp", "add", "local/h", "s", "--url", "https://example.com/sse"])
    }

    func test_buildMCPAddArgs_withHeaders() {
        let args = HarnessHookMutator.buildMCPAddArgs(
            HarnessMCPAddOptions(
                harness: "local/h", serverName: "s",
                command: nil, args: [], env: [:], url: "https://x", headers: ["Authorization": "Bearer token"]
            )
        )
        XCTAssertTrue(args.contains("--header"))
        XCTAssertTrue(args.contains("Authorization=Bearer token"))
    }

    func test_buildMCPAddArgs_emptyCommandOmitted() {
        let args = HarnessHookMutator.buildMCPAddArgs(
            HarnessMCPAddOptions(
                harness: "local/h", serverName: "s",
                command: "", args: [], env: [:], url: nil, headers: [:]
            )
        )
        XCTAssertFalse(args.contains("--command"))
    }
}

// MARK: - HarnessHookMutator — run state tests

@MainActor
final class HarnessHookMutatorStateTests: XCTestCase {

    func test_addHook_basic_passesCorrectArgs() async {
        let stub = MutatorStubRunner()
        let mutator = HarnessHookMutator(commandRunner: stub)
        await mutator.addHook(
            HarnessHookAddOptions(harness: "local/h", event: "before_tool", command: "echo hi", matcher: nil),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertEqual(stub.capturedArgs.last, ["hook", "add", "local/h", "before_tool", "echo hi"])
    }

    func test_addHook_withMatcher_appendsMatcherFlag() async {
        let stub = MutatorStubRunner()
        let mutator = HarnessHookMutator(commandRunner: stub)
        await mutator.addHook(
            HarnessHookAddOptions(harness: "local/h", event: "before_tool", command: "echo hi", matcher: "Write"),
            ynhPath: "/ynh", environment: [:]
        )
        let last = stub.capturedArgs.last!
        XCTAssertEqual(last, ["hook", "add", "local/h", "before_tool", "echo hi", "--matcher", "Write"])
    }

    func test_addHook_emptyMatcher_notAppended() async {
        let stub = MutatorStubRunner()
        let mutator = HarnessHookMutator(commandRunner: stub)
        await mutator.addHook(
            HarnessHookAddOptions(harness: "local/h", event: "before_tool", command: "echo hi", matcher: ""),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertFalse(stub.capturedArgs.last!.contains("--matcher"))
    }

    func test_removeHook_passesCorrectArgs() async {
        let stub = MutatorStubRunner()
        let mutator = HarnessHookMutator(commandRunner: stub)
        await mutator.removeHook(
            HarnessHookRemoveOptions(harness: "local/h", event: "before_tool", index: 2),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertEqual(stub.capturedArgs.last, ["hook", "remove", "local/h", "before_tool", "2"])
    }

    func test_removeMCP_passesCorrectArgs() async {
        let stub = MutatorStubRunner()
        let mutator = HarnessHookMutator(commandRunner: stub)
        await mutator.removeMCP(
            HarnessMCPRemoveOptions(harness: "local/h", serverName: "github"),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertEqual(stub.capturedArgs.last, ["mcp", "remove", "local/h", "github"])
    }

    func test_addHook_success_setsSuceeded() async {
        let stub = MutatorStubRunner()
        let mutator = HarnessHookMutator(commandRunner: stub)
        await mutator.addHook(
            HarnessHookAddOptions(harness: "local/h", event: "before_tool", command: "echo hi", matcher: nil),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertTrue(mutator.succeeded)
        XCTAssertNil(mutator.errorMessage)
    }

    func test_addHook_failure_setsErrorMessage() async {
        let stub = MutatorStubRunner()
        stub.outcome = .failure(stderr: "Error: unknown event")
        let mutator = HarnessHookMutator(commandRunner: stub)
        await mutator.addHook(
            HarnessHookAddOptions(harness: "local/h", event: "garbage", command: "echo hi", matcher: nil),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertFalse(mutator.succeeded)
        XCTAssertEqual(mutator.errorMessage, "Error: unknown event")
    }
}

// MARK: - ProfileMutator — arg builder tests

final class ProfileMutatorArgTests: XCTestCase {

    // MARK: Hook add

    func test_buildHookAddArgs_noMatcher() {
        let args = ProfileMutator.buildHookAddArgs(
            ProfileHookAddOptions(
                harness: "local/h", profileName: "dev",
                event: "before_tool", command: "echo run", matcher: nil
            )
        )
        XCTAssertEqual(args, ["profile", "hook", "add", "local/h", "dev", "before_tool", "echo run"])
    }

    func test_buildHookAddArgs_withMatcher() {
        let args = ProfileMutator.buildHookAddArgs(
            ProfileHookAddOptions(
                harness: "local/h", profileName: "dev",
                event: "before_tool", command: "echo run", matcher: "Write"
            )
        )
        XCTAssertEqual(
            args,
            ["profile", "hook", "add", "local/h", "dev", "before_tool", "echo run", "--matcher", "Write"]
        )
    }

    func test_buildHookAddArgs_emptyMatcherOmitted() {
        let args = ProfileMutator.buildHookAddArgs(
            ProfileHookAddOptions(
                harness: "local/h", profileName: "dev",
                event: "before_tool", command: "echo run", matcher: ""
            )
        )
        XCTAssertFalse(args.contains("--matcher"))
    }

    // MARK: MCP add

    func test_buildMCPAddArgs_nullFlag_shortCircuits() {
        let args = ProfileMutator.buildMCPAddArgs(
            ProfileMCPAddOptions(
                harness: "local/h", profileName: "dev", serverName: "s",
                command: "cmd", args: ["--flag"], env: [:], url: nil, headers: [:], null: true
            )
        )
        XCTAssertEqual(args, ["profile", "mcp", "add", "local/h", "dev", "s", "--null"])
    }

    func test_buildMCPAddArgs_command() {
        let args = ProfileMutator.buildMCPAddArgs(
            ProfileMCPAddOptions(
                harness: "local/h", profileName: "dev", serverName: "s",
                command: "npx", args: [], env: [:], url: nil, headers: [:], null: false
            )
        )
        XCTAssertEqual(args, ["profile", "mcp", "add", "local/h", "dev", "s", "--command", "npx"])
    }

    func test_buildMCPAddArgs_url() {
        let args = ProfileMutator.buildMCPAddArgs(
            ProfileMCPAddOptions(
                harness: "local/h", profileName: "dev", serverName: "s",
                command: nil, args: [], env: [:], url: "https://x/sse", headers: [:], null: false
            )
        )
        XCTAssertEqual(args, ["profile", "mcp", "add", "local/h", "dev", "s", "--url", "https://x/sse"])
    }

    func test_buildMCPAddArgs_argsAndEnv() {
        let args = ProfileMutator.buildMCPAddArgs(
            ProfileMCPAddOptions(
                harness: "local/h", profileName: "dev", serverName: "s",
                command: "cmd", args: ["--flag", "val"], env: ["TOKEN": "abc"], url: nil, headers: [:], null: false
            )
        )
        XCTAssertTrue(args.contains("--arg"))
        XCTAssertTrue(args.contains("--env"))
        XCTAssertTrue(args.contains("TOKEN=abc"))
    }

    // MARK: MCP update

    func test_buildMCPUpdateArgs_setArgsFalse_noArgsEmitted() {
        let args = ProfileMutator.buildMCPUpdateArgs(
            ProfileMCPUpdateOptions(
                harness: "local/h", profileName: "dev", serverName: "s",
                command: nil, args: ["--port", "9090"], setArgs: false,
                env: [:], setEnv: false,
                url: nil, headers: [:], setHeaders: false
            )
        )
        XCTAssertFalse(args.contains("--arg"))
        XCTAssertFalse(args.contains("--clear-args"))
    }

    func test_buildMCPUpdateArgs_setArgsTrue_emptyArgs_clearArgs() {
        let args = ProfileMutator.buildMCPUpdateArgs(
            ProfileMCPUpdateOptions(
                harness: "local/h", profileName: "dev", serverName: "s",
                command: nil, args: [], setArgs: true,
                env: [:], setEnv: false,
                url: nil, headers: [:], setHeaders: false
            )
        )
        XCTAssertTrue(args.contains("--clear-args"))
    }

    func test_buildMCPUpdateArgs_setArgsTrue_nonEmpty_emitsArgs() {
        let args = ProfileMutator.buildMCPUpdateArgs(
            ProfileMCPUpdateOptions(
                harness: "local/h", profileName: "dev", serverName: "s",
                command: nil, args: ["--port", "8080"], setArgs: true,
                env: [:], setEnv: false,
                url: nil, headers: [:], setHeaders: false
            )
        )
        XCTAssertTrue(args.contains("--arg"))
        XCTAssertFalse(args.contains("--clear-args"))
    }

    func test_buildMCPUpdateArgs_setEnvTrue_empty_clearEnv() {
        let args = ProfileMutator.buildMCPUpdateArgs(
            ProfileMCPUpdateOptions(
                harness: "local/h", profileName: "dev", serverName: "s",
                command: nil, args: [], setArgs: false,
                env: [:], setEnv: true,
                url: nil, headers: [:], setHeaders: false
            )
        )
        XCTAssertTrue(args.contains("--clear-env"))
    }

    func test_buildMCPUpdateArgs_emptyCommandOmitted() {
        let args = ProfileMutator.buildMCPUpdateArgs(
            ProfileMCPUpdateOptions(
                harness: "local/h", profileName: "dev", serverName: "s",
                command: "", args: [], setArgs: false,
                env: [:], setEnv: false,
                url: nil, headers: [:], setHeaders: false
            )
        )
        XCTAssertFalse(args.contains("--command"))
    }

    func test_buildMCPUpdateArgs_emptyURLOmitted() {
        let args = ProfileMutator.buildMCPUpdateArgs(
            ProfileMCPUpdateOptions(
                harness: "local/h", profileName: "dev", serverName: "s",
                command: nil, args: [], setArgs: false,
                env: [:], setEnv: false,
                url: "", headers: [:], setHeaders: false
            )
        )
        XCTAssertFalse(args.contains("--url"))
    }

    func test_buildMCPUpdateArgs_setHeadersTrue_empty_clearHeaders() {
        let args = ProfileMutator.buildMCPUpdateArgs(
            ProfileMCPUpdateOptions(
                harness: "local/h", profileName: "dev", serverName: "s",
                command: nil, args: [], setArgs: false,
                env: [:], setEnv: false,
                url: nil, headers: [:], setHeaders: true
            )
        )
        XCTAssertTrue(args.contains("--clear-headers"))
    }

    // MARK: Include add

    func test_buildIncludeAddArgs_basic() {
        let args = ProfileMutator.buildIncludeAddArgs(
            ProfileIncludeAddOptions(
                harness: "local/h", profileName: "dev",
                url: "https://github.com/o/r", path: nil, ref: nil, replace: false
            )
        )
        XCTAssertEqual(args, ["profile", "include", "add", "local/h", "dev", "https://github.com/o/r"])
    }

    func test_buildIncludeAddArgs_withPathRefReplace() {
        let args = ProfileMutator.buildIncludeAddArgs(
            ProfileIncludeAddOptions(
                harness: "local/h", profileName: "dev",
                url: "https://github.com/o/r", path: "plugins/foo", ref: "main", replace: true
            )
        )
        XCTAssertTrue(args.contains("--path"))
        XCTAssertTrue(args.contains("plugins/foo"))
        XCTAssertTrue(args.contains("--ref"))
        XCTAssertTrue(args.contains("main"))
        XCTAssertTrue(args.contains("--replace"))
    }

    func test_buildIncludeAddArgs_emptyPathOmitted() {
        let args = ProfileMutator.buildIncludeAddArgs(
            ProfileIncludeAddOptions(
                harness: "local/h", profileName: "dev",
                url: "https://github.com/o/r", path: "", ref: nil, replace: false
            )
        )
        XCTAssertFalse(args.contains("--path"))
    }

    // MARK: Include remove

    func test_buildIncludeRemoveArgs_withPath() {
        let args = ProfileMutator.buildIncludeRemoveArgs(
            ProfileIncludeRemoveOptions(
                harness: "local/h", profileName: "dev",
                url: "https://github.com/o/r", path: "plugins/foo"
            )
        )
        XCTAssertEqual(
            args,
            ["profile", "include", "remove", "local/h", "dev", "https://github.com/o/r", "--path", "plugins/foo"]
        )
    }

    func test_buildIncludeRemoveArgs_noPath() {
        let args = ProfileMutator.buildIncludeRemoveArgs(
            ProfileIncludeRemoveOptions(
                harness: "local/h", profileName: "dev",
                url: "https://github.com/o/r", path: nil
            )
        )
        XCTAssertFalse(args.contains("--path"))
    }

    // MARK: Include update

    func test_buildIncludeUpdateArgs_pathAndRef() {
        let args = ProfileMutator.buildIncludeUpdateArgs(
            ProfileIncludeUpdateOptions(
                harness: "local/h", profileName: "dev",
                url: "https://github.com/o/r",
                fromPath: "old/path", newPath: "new/path", ref: "develop"
            )
        )
        XCTAssertEqual(
            args,
            [
                "profile", "include", "update", "local/h", "dev", "https://github.com/o/r",
                "--from-path", "old/path", "--path", "new/path", "--ref", "develop",
            ]
        )
    }

    func test_buildIncludeUpdateArgs_emptyFromPathOmitted() {
        let args = ProfileMutator.buildIncludeUpdateArgs(
            ProfileIncludeUpdateOptions(
                harness: "local/h", profileName: "dev",
                url: "https://github.com/o/r",
                fromPath: "", newPath: "new/path", ref: nil
            )
        )
        XCTAssertFalse(args.contains("--from-path"))
    }
}

// MARK: - ProfileMutator — run state tests

@MainActor
final class ProfileMutatorStateTests: XCTestCase {

    func test_addProfile_success_setsSuceeded() async {
        let stub = MutatorStubRunner()
        let mutator = ProfileMutator(commandRunner: stub)
        await mutator.addProfile(
            ProfileAddOptions(harness: "local/h", name: "dev"),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertTrue(mutator.succeeded)
        XCTAssertNil(mutator.errorMessage)
        XCTAssertEqual(stub.capturedArgs.last, ["profile", "add", "local/h", "dev"])
    }

    func test_removeProfile_success_setsSuceeded() async {
        let stub = MutatorStubRunner()
        let mutator = ProfileMutator(commandRunner: stub)
        await mutator.removeProfile(
            ProfileRemoveOptions(harness: "local/h", name: "dev"),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertTrue(mutator.succeeded)
        XCTAssertEqual(stub.capturedArgs.last, ["profile", "remove", "local/h", "dev"])
    }

    func test_addHook_failure_setsErrorMessage() async {
        let stub = MutatorStubRunner()
        stub.outcome = .failure(stderr: "Error: profile not found")
        let mutator = ProfileMutator(commandRunner: stub)
        await mutator.addHook(
            ProfileHookAddOptions(
                harness: "local/h", profileName: "dev",
                event: "before_tool", command: "echo run", matcher: nil
            ),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertFalse(mutator.succeeded)
        XCTAssertEqual(mutator.errorMessage, "Error: profile not found")
    }

    func test_removeHook_passesIndexAsString() async {
        let stub = MutatorStubRunner()
        let mutator = ProfileMutator(commandRunner: stub)
        await mutator.removeHook(
            ProfileHookRemoveOptions(harness: "local/h", profileName: "dev", event: "before_tool", index: 3),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertEqual(
            stub.capturedArgs.last,
            ["profile", "hook", "remove", "local/h", "dev", "before_tool", "3"]
        )
    }

    func test_removeMCP_passesCorrectArgs() async {
        let stub = MutatorStubRunner()
        let mutator = ProfileMutator(commandRunner: stub)
        await mutator.removeMCP(
            ProfileMCPRemoveOptions(harness: "local/h", profileName: "dev", serverName: "github"),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertEqual(
            stub.capturedArgs.last,
            ["profile", "mcp", "remove", "local/h", "dev", "github"]
        )
    }

    func test_addInclude_success_setsSuceeded() async {
        let stub = MutatorStubRunner()
        let mutator = ProfileMutator(commandRunner: stub)
        await mutator.addInclude(
            ProfileIncludeAddOptions(
                harness: "local/h", profileName: "dev",
                url: "https://github.com/o/r", path: nil, ref: nil, replace: false
            ),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertTrue(mutator.succeeded)
    }

    func test_throwing_runner_setsErrorMessage() async {
        let stub = MutatorStubRunner()
        stub.outcome = .throwing(TestError())
        let mutator = ProfileMutator(commandRunner: stub)
        await mutator.addProfile(
            ProfileAddOptions(harness: "local/h", name: "dev"),
            ynhPath: "/ynh", environment: [:]
        )
        XCTAssertFalse(mutator.succeeded)
        XCTAssertNotNil(mutator.errorMessage)
    }
}
