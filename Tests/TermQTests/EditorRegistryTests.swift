import Foundation
import XCTest

@testable import TermQ

/// Records what `EditorRegistry` and `TerminalSessionManager` ask of the
/// command-runner seam, so tests can drive the success/failure paths
/// without spawning a real `/usr/bin/which` or `tmux` subprocess.
final class StubCommandRunner: YNHCommandRunner, @unchecked Sendable {
    enum Outcome {
        case stdout(String, exitCode: Int32 = 0)
        case failure(stderr: String, exitCode: Int32)
        case throwing(Error)
    }

    /// Per-binary outcomes (keyed by the *last* component of `executable` or
    /// the first argument when running `which`). Falls back to `.failure`.
    var outcomes: [String: Outcome] = [:]
    var defaultOutcome: Outcome = .failure(stderr: "", exitCode: 1)

    private(set) var capturedInvocations: [(executable: String, arguments: [String], environment: [String: String]?)] =
        []

    private let lock = NSRecursiveLock()

    private func withLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    // swiftlint:disable:next function_parameter_count
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        currentDirectory: String?,
        onStdoutLine: (@Sendable (String) -> Void)?,
        onStderrLine: (@Sendable (String) -> Void)?
    ) async throws -> CommandRunner.Result {
        let outcome = withLock { () -> Outcome in
            capturedInvocations.append(
                (executable: executable, arguments: arguments, environment: environment))
            let key = arguments.first ?? executable
            return outcomes[key] ?? defaultOutcome
        }

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

// MARK: - Stub WorkspaceProvider

@MainActor
private final class StubWorkspaceProvider: WorkspaceProvider {
    var bundleIDsToURL: [String: URL] = [:]
    func urlForApplication(withBundleIdentifier bundleID: String) -> URL? {
        bundleIDsToURL[bundleID]
    }
    func open(_ url: URL) -> Bool { true }
    func urlForApplication(toOpen url: URL) -> URL? { nil }
    func activateFileViewerSelecting(_ urls: [URL]) {}
    func openFile(
        _ url: URL,
        withApplicationAt appURL: URL,
        completion: @escaping @MainActor @Sendable (Error?) -> Void
    ) {
        Task { @MainActor in completion(nil) }
    }
}

@MainActor
final class EditorRegistryTests: XCTestCase {

    // MARK: - which() success path

    func test_start_resolvesEditorViaWhich_whenCliAvailable() async {
        let workspace = StubWorkspaceProvider()
        let runner = StubCommandRunner()
        // `code` resolves; everything else fails.
        runner.outcomes["code"] = .stdout("/usr/local/bin/code\n")

        let registry = EditorRegistry(workspace: workspace, commandRunner: runner)
        registry.start()

        await pollUntil { registry.available.contains { $0.kind == .vscode } }
        let vscode = registry.available.first { $0.kind == .vscode }
        XCTAssertEqual(vscode?.appURL.path, "/usr/local/bin/code")
    }

    func test_start_resolvesEditorViaBundleId_whenAppRegistered() async {
        let workspace = StubWorkspaceProvider()
        workspace.bundleIDsToURL["com.apple.dt.Xcode"] =
            URL(fileURLWithPath: "/Applications/Xcode.app")
        let runner = StubCommandRunner()

        let registry = EditorRegistry(workspace: workspace, commandRunner: runner)
        registry.start()

        await pollUntil { registry.available.contains { $0.kind == .xcode } }
        let xcode = registry.available.first { $0.kind == .xcode }
        XCTAssertEqual(xcode?.appURL.path, "/Applications/Xcode.app")
        // No `which` call should have been made for Xcode (bundle hit short-circuits).
        XCTAssertFalse(runner.capturedInvocations.contains { $0.arguments == ["xed"] })
    }

    // MARK: - which() failure path

    func test_start_omitsEditor_whenWhichFails() async {
        let workspace = StubWorkspaceProvider()
        let runner = StubCommandRunner()
        // All `which` calls fail (default).

        let registry = EditorRegistry(workspace: workspace, commandRunner: runner)
        registry.start()

        await pollUntil { runner.capturedInvocations.count >= 1 }
        // Wait one more tick to let detect() finish.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(registry.available.isEmpty)
    }

    func test_which_callsUsrBinWhich_withBinaryName() async {
        let workspace = StubWorkspaceProvider()
        let runner = StubCommandRunner()

        let registry = EditorRegistry(workspace: workspace, commandRunner: runner)
        registry.start()

        await pollUntil { runner.capturedInvocations.count >= 5 }
        // At least one invocation should be `/usr/bin/which code`.
        XCTAssertTrue(
            runner.capturedInvocations.contains {
                $0.executable == "/usr/bin/which" && $0.arguments == ["code"]
            }
        )
    }

    // MARK: - Empty stdout from `which`

    func test_start_omitsEditor_whenWhichReturnsEmptyStdout() async {
        let workspace = StubWorkspaceProvider()
        let runner = StubCommandRunner()
        runner.outcomes["code"] = .stdout("   \n")  // whitespace only

        let registry = EditorRegistry(workspace: workspace, commandRunner: runner)
        registry.start()

        await pollUntil { runner.capturedInvocations.count >= 5 }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(registry.available.first { $0.kind == .vscode })
    }

    // MARK: - Helper

    /// Poll on the main actor until `predicate` is true or 1s elapses.
    private func pollUntil(_ predicate: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
