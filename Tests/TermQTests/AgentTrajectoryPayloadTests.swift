import Foundation
import XCTest

@testable import TermQCore

final class AgentTrajectoryPayloadTests: XCTestCase {

    private func event(type: String, json: String) -> TrajectoryEvent {
        TrajectoryEvent(type: type, timestamp: Date(), payloadJSON: json)
    }

    // MARK: - Typed variants

    func testSessionStart_decodes() {
        let json =
            #"{"type":"session_start","session_id":"abc-123","harness":"eyelock/x/coding-agent"}"#
        let payload = event(type: "session_start", json: json).decoded()
        XCTAssertEqual(payload, .sessionStart(sessionId: "abc-123", harness: "eyelock/x/coding-agent"))
    }

    func testSessionStart_harnessOptional() {
        let json = #"{"type":"session_start","session_id":"abc-123"}"#
        let payload = event(type: "session_start", json: json).decoded()
        XCTAssertEqual(payload, .sessionStart(sessionId: "abc-123", harness: nil))
    }

    func testPlan_decodes() {
        let json = ##"{"type":"plan","content":"# Plan\n- step 1\n- step 2"}"##
        let payload = event(type: "plan", json: json).decoded()
        XCTAssertEqual(payload, .plan(content: "# Plan\n- step 1\n- step 2"))
    }

    func testTurnStart_decodes() {
        let json = #"{"type":"turn_start","turn":7}"#
        let payload = event(type: "turn_start", json: json).decoded()
        XCTAssertEqual(payload, .turnStart(turn: 7))
    }

    func testSensorResult_decodesAllFields() {
        let json =
            #"{"type":"sensor_result","name":"build","exit_code":0,"duration_ms":812,"summary":"ok"}"#
        let payload = event(type: "sensor_result", json: json).decoded()
        XCTAssertEqual(
            payload,
            .sensorResult(name: "build", exitCode: 0, durationMs: 812, summary: "ok"))
    }

    func testSensorResult_summaryOptional() {
        let json = #"{"type":"sensor_result","name":"lint","exit_code":1,"duration_ms":42}"#
        let payload = event(type: "sensor_result", json: json).decoded()
        XCTAssertEqual(
            payload,
            .sensorResult(name: "lint", exitCode: 1, durationMs: 42, summary: nil))
    }

    func testStuckDetected_decodes() {
        let json = #"{"type":"stuck_detected","reason":"edit-loop"}"#
        let payload = event(type: "stuck_detected", json: json).decoded()
        XCTAssertEqual(payload, .stuckDetected(reason: "edit-loop"))
    }

    func testBudgetExceeded_turns() {
        let json = #"{"type":"budget_exceeded","budget":"turns"}"#
        let payload = event(type: "budget_exceeded", json: json).decoded()
        XCTAssertEqual(payload, .budgetExceeded(budget: .turns))
    }

    func testBudgetExceeded_wallClock() {
        let json = #"{"type":"budget_exceeded","budget":"wall_clock"}"#
        let payload = event(type: "budget_exceeded", json: json).decoded()
        XCTAssertEqual(payload, .budgetExceeded(budget: .wallClock))
    }

    func testConverged_decodes() {
        let json = #"{"type":"converged"}"#
        let payload = event(type: "converged", json: json).decoded()
        XCTAssertEqual(payload, .converged)
    }

    func testSessionEnd_decodesAllFields() {
        let json =
            #"{"type":"session_end","exit_code":0,"total_turns":7,"total_tokens":234567}"#
        let payload = event(type: "session_end", json: json).decoded()
        XCTAssertEqual(
            payload,
            .sessionEnd(exitCode: 0, totalTurns: 7, totalTokens: 234_567))
    }

    func testSessionEnd_optionalsAbsent() {
        let json = #"{"type":"session_end","exit_code":13}"#
        let payload = event(type: "session_end", json: json).decoded()
        XCTAssertEqual(payload, .sessionEnd(exitCode: 13, totalTurns: nil, totalTokens: nil))
    }

    // MARK: - Forward-compatibility

    func testUnknownType_fallsToOther() {
        let json = #"{"type":"future_event","data":42}"#
        let payload = event(type: "future_event", json: json).decoded()
        XCTAssertEqual(payload, .other(type: "future_event", json: json))
    }

    func testKnownTypeWithMalformedFields_fallsToOther() {
        // turn_start expects an int turn; strings don't decode.
        let json = #"{"type":"turn_start","turn":"seven"}"#
        let payload = event(type: "turn_start", json: json).decoded()
        XCTAssertEqual(payload, .other(type: "turn_start", json: json))
    }

    func testKnownTypeMissingRequiredField_fallsToOther() {
        // sensor_result requires name + exit_code + duration_ms.
        let json = #"{"type":"sensor_result","name":"build"}"#
        let payload = event(type: "sensor_result", json: json).decoded()
        XCTAssertEqual(payload, .other(type: "sensor_result", json: json))
    }
}
