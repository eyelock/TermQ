import XCTest

@testable import TermQ

@MainActor
final class CommandSheetStateTests: XCTestCase {
    func testInitialPhase_isIdle() {
        let state = CommandSheetState()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertTrue(state.outputLines.isEmpty)
        XCTAssertNil(state.exitCode)
    }

    func testBegin_transitionsToRunningAndClearsOutput() {
        let state = CommandSheetState()
        state.append(line: "stale line")
        state.begin()
        XCTAssertEqual(state.phase, .running)
        XCTAssertTrue(state.outputLines.isEmpty)
        XCTAssertNil(state.exitCode)
    }

    func testAppend_accumulatesLinesInOrder() {
        let state = CommandSheetState()
        state.begin()
        state.append(line: "line 1")
        state.append(line: "line 2")
        state.append(line: "line 3")
        XCTAssertEqual(state.outputLines, ["line 1", "line 2", "line 3"])
    }

    func testFinish_success_transitionsToSucceeded() {
        let state = CommandSheetState()
        state.begin()
        state.append(line: "ok")
        state.finish(result: CommandRunner.Result(exitCode: 0, stdout: "ok", stderr: "", duration: 0))
        XCTAssertEqual(state.phase, .succeeded)
        XCTAssertEqual(state.exitCode, 0)
    }

    func testFinish_failure_transitionsToFailed() {
        let state = CommandSheetState()
        state.begin()
        state.append(line: "error")
        state.finish(result: CommandRunner.Result(exitCode: 1, stdout: "", stderr: "error", duration: 0))
        XCTAssertEqual(state.phase, .failed)
        XCTAssertEqual(state.exitCode, 1)
    }

    func testBegin_afterFailure_resetsToRunning() {
        let state = CommandSheetState()
        state.begin()
        state.finish(result: CommandRunner.Result(exitCode: 1, stdout: "", stderr: "", duration: 0))
        XCTAssertEqual(state.phase, .failed)

        state.begin()
        XCTAssertEqual(state.phase, .running)
        XCTAssertTrue(state.outputLines.isEmpty)
        XCTAssertNil(state.exitCode)
    }
}
