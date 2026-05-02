import Foundation
import XCTest

@testable import TermQ

/// Tests `CommandRunner` against `/bin/sh` — present on every macOS system.
final class CommandRunnerTests: XCTestCase {
    func testCapturesStdoutAndExitZero() async throws {
        let result = try await CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'hello\\nworld\\n'"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.didSucceed)
        XCTAssertEqual(result.stdout, "hello\nworld\n")
        XCTAssertEqual(result.stderr, "")
    }

    func testCapturesStderrSeparately() async throws {
        let result = try await CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'oops\\n' >&2"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "oops\n")
    }

    func testNonZeroExitReturnedNotThrown() async throws {
        let result = try await CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "exit 7"]
        )
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertFalse(result.didSucceed)
    }

    func testStreamsStdoutLinesInOrder() async throws {
        let collected = LineCollector()
        let result = try await CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'one\\ntwo\\nthree\\n'"],
            onStdoutLine: { line in collected.append(line) }
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(collected.snapshot(), ["one", "two", "three"])
    }

    func testStreamsStderrLinesIndependently() async throws {
        let stderrLines = LineCollector()
        let result = try await CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'err1\\nerr2\\n' >&2"],
            onStderrLine: { line in stderrLines.append(line) }
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(stderrLines.snapshot(), ["err1", "err2"])
    }

    func testFlushesTrailingPartialLineWithoutNewline() async throws {
        let collected = LineCollector()
        let result = try await CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'no-newline'"],
            onStdoutLine: { line in collected.append(line) }
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(collected.snapshot(), ["no-newline"])
    }

    func testLaunchFailureThrows() async {
        do {
            _ = try await CommandRunner.run(
                executable: "/usr/bin/this-binary-does-not-exist-\(UUID().uuidString)",
                arguments: []
            )
            XCTFail("expected launch failure")
        } catch CommandRunner.RunError.launchFailed {
            // expected
        } catch {
            XCTFail("expected launchFailed, got \(error)")
        }
    }

    func testEnvironmentIsApplied() async throws {
        let result = try await CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf '%s' \"$TERMQ_TEST_VAR\""],
            environment: ["TERMQ_TEST_VAR": "marker-42"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "marker-42")
    }

    func testCurrentDirectoryIsApplied() async throws {
        let result = try await CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "pwd"],
            currentDirectory: "/tmp"
        )
        XCTAssertEqual(result.exitCode, 0)
        // /tmp resolves to /private/tmp on macOS via the firmlinks layer; both are valid.
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(
            trimmed == "/tmp" || trimmed == "/private/tmp",
            "unexpected pwd: \(trimmed)"
        )
    }

    func testDurationIsRecorded() async throws {
        let result = try await CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 0.1"]
        )
        XCTAssertGreaterThanOrEqual(result.duration, 0.1)
    }
}

// MARK: - Helpers

/// Thread-safe collector for line callbacks fired from a background queue.
private final class LineCollector: @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}
