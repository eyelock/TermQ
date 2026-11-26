import Foundation
import XCTest

@testable import TermQShared

/// How often TermQ reads a Wheelhouse's work graph, which waits on the same
/// `bd` lock as every seat.
final class WheelhousePollTests: XCTestCase {

    func testAPromptRoundKeepsOrRestoresTheBaseInterval() {
        let base = WheelhousePoll.baseInterval
        XCTAssertEqual(WheelhousePoll.nextInterval(after: base, roundTook: 1, failed: false), base)
        XCTAssertEqual(WheelhousePoll.nextInterval(after: 480, roundTook: 1, failed: false), base)
    }

    func testAFailedOrSlowRoundDoublesTheWait() {
        let base = WheelhousePoll.baseInterval
        XCTAssertEqual(WheelhousePoll.nextInterval(after: base, roundTook: 1, failed: true), base * 2)
        XCTAssertEqual(
            WheelhousePoll.nextInterval(after: base * 2, roundTook: WheelhousePoll.slowRound + 1, failed: false),
            base * 4)
    }

    func testTheWaitNeverPassesTheMaximum() {
        var interval = WheelhousePoll.baseInterval
        for _ in 0..<10 { interval = WheelhousePoll.nextInterval(after: interval, roundTook: 30, failed: true) }
        XCTAssertEqual(interval, WheelhousePoll.maxInterval)
    }

    func testStaleness() {
        let now = Date()
        XCTAssertTrue(WheelhousePoll.isStale(lastRead: nil, now: now))
        XCTAssertFalse(WheelhousePoll.isStale(lastRead: now.addingTimeInterval(-5), now: now))
        XCTAssertTrue(
            WheelhousePoll.isStale(lastRead: now.addingTimeInterval(-WheelhousePoll.baseInterval), now: now))
    }

    func testReadsAreReadOnly() {
        XCTAssertEqual(
            WheelhousePoll.readArguments(["list", "--json"]), ["--readonly", "list", "--json"])
    }
}

/// `StackProcessRunner` ends its process on a timeout or a cancel, instead of
/// leaving it running after the caller has gone.
final class StackProcessRunnerTests: XCTestCase {

    func testRunsAndCollectsOutput() async throws {
        let result = try await StackProcessRunner.run("/bin/echo", ["hello"], cwd: nil, timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hello\n")
    }

    func testATimeoutEndsTheProcess() async {
        let started = Date()
        do {
            _ = try await StackProcessRunner.run("/bin/sleep", ["30"], cwd: nil, timeout: 0.3)
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? StackProcessError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testCancellingTheCallerEndsTheProcess() async {
        let started = Date()
        let task = Task {
            try await StackProcessRunner.run("/bin/sleep", ["30"], cwd: nil, terminateOnCancel: true)
        }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected a cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testWithoutTheOptInACancelledCallerLetsTheProcessFinish() async throws {
        let task = Task {
            try await StackProcessRunner.run(
                "/usr/bin/perl", ["-e", "select(undef,undef,undef,0.5); print 'done'"], cwd: nil)
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = try await task.value
        XCTAssertEqual(result.stdout, "done")
    }

    func testAProcessThatIgnoresSIGTERMIsKilled() async {
        let started = Date()
        do {
            // One process: a shell's `sleep` child would keep the pipe open.
            _ = try await StackProcessRunner.run(
                "/usr/bin/perl", ["-e", "$SIG{TERM} = 'IGNORE'; sleep 30"], cwd: nil, timeout: 0.3)
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? StackProcessError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), StackProcessRunner.killGrace + 8)
    }
}
