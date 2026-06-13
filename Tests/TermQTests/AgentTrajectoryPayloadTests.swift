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
            #"{"type":"session_start","data":{"session_id":"abc-123","harness":"eyelock/x/coding-agent"}}"#
        let payload = event(type: "session_start", json: json).decoded()
        XCTAssertEqual(payload, .sessionStart(sessionId: "abc-123", harness: "eyelock/x/coding-agent"))
    }

    func testSessionStart_harnessOptional() {
        let json = #"{"type":"session_start","data":{"session_id":"abc-123"}}"#
        let payload = event(type: "session_start", json: json).decoded()
        XCTAssertEqual(payload, .sessionStart(sessionId: "abc-123", harness: nil))
    }

    func testPlan_decodes() {
        let json = ##"{"type":"plan","data":{"content":"# Plan\n- step 1\n- step 2"}}"##
        let payload = event(type: "plan", json: json).decoded()
        XCTAssertEqual(payload, .plan(content: "# Plan\n- step 1\n- step 2"))
    }

    /// ynh emits a bare `{"type":"plan"}` marker when the agent enters plan
    /// mode (before any plan content has been written). This must still
    /// decode as `.plan` so the UI flips into the approval-gated state.
    func testPlan_emptyMarker_decodesAsEmptyContent() {
        let json = #"{"type":"plan"}"#
        let payload = event(type: "plan", json: json).decoded()
        XCTAssertEqual(payload, .plan(content: ""))
    }

    func testPlan_dataWithoutContent_decodesAsEmptyContent() {
        let json = #"{"type":"plan","data":{}}"#
        let payload = event(type: "plan", json: json).decoded()
        XCTAssertEqual(payload, .plan(content: ""))
    }

    func testTurnStart_decodes() {
        // ynh emits `turn` at the top level (no nested data wrapper).
        let json = #"{"type":"turn_start","turn":7}"#
        let payload = event(type: "turn_start", json: json).decoded()
        XCTAssertEqual(payload, .turnStart(turn: 7))
    }

    func testAssistantMessage_withTurn_decodes() {
        // ynh: `data` is a plain string, optional top-level `turn`.
        let json = #"{"type":"assistant_message","turn":2,"data":"hello world"}"#
        let payload = event(type: "assistant_message", json: json).decoded()
        XCTAssertEqual(payload, .assistantMessage(turn: 2, content: "hello world"))
    }

    func testAssistantMessage_withoutTurn_decodes() {
        // Pre-turn assistant_message events (e.g. plan-mode thinking).
        let json = #"{"type":"assistant_message","data":"thinking out loud"}"#
        let payload = event(type: "assistant_message", json: json).decoded()
        XCTAssertEqual(payload, .assistantMessage(turn: nil, content: "thinking out loud"))
    }

    func testSensorResult_decodesAllFields() {
        let json =
            #"{"type":"sensor_result","data":{"name":"build","exit_code":0,"duration_ms":812,"summary":"ok"}}"#
        let payload = event(type: "sensor_result", json: json).decoded()
        XCTAssertEqual(
            payload,
            .sensorResult(name: "build", exitCode: 0, durationMs: 812, summary: "ok"))
    }

    func testSensorResult_summaryOptional() {
        let json = #"{"type":"sensor_result","data":{"name":"lint","exit_code":1,"duration_ms":42}}"#
        let payload = event(type: "sensor_result", json: json).decoded()
        XCTAssertEqual(
            payload,
            .sensorResult(name: "lint", exitCode: 1, durationMs: 42, summary: nil))
    }

    func testTurnApprovalRequired_planPhase_decodes() {
        // ynh wire shape: turn at the top level, synthesized_feedback
        // inside data. Plan-phase gate uses turn=0.
        let json =
            ##"{"type":"turn_approval_required","turn":0,"data":{"synthesized_feedback":"# Plan\n- step 1"}}"##
        let payload = event(type: "turn_approval_required", json: json).decoded()
        XCTAssertEqual(
            payload, .turnApprovalRequired(turn: 0, synthesizedFeedback: "# Plan\n- step 1"))
    }

    func testTurnApprovalRequired_actPhase_decodes() {
        // Act-phase gate: turn ≥ 1, feedback is the synthesized sensor block.
        let json =
            #"{"type":"turn_approval_required","turn":4,"data":{"synthesized_feedback":"<sensor-results>"}}"#
        let payload = event(type: "turn_approval_required", json: json).decoded()
        XCTAssertEqual(
            payload, .turnApprovalRequired(turn: 4, synthesizedFeedback: "<sensor-results>"))
    }

    func testPlanApprovalRequired_decodes() {
        // ynh 0.5+ dedicated plan-phase event. Plan + iteration in `data`.
        let json =
            ##"{"type":"plan_approval_required","turn":0,"data":{"plan":"# do x\n- step","iteration":1}}"##
        let payload = event(type: "plan_approval_required", json: json).decoded()
        XCTAssertEqual(payload, .planApprovalRequired(plan: "# do x\n- step", iteration: 1))
    }

    func testPlanApprovalRequired_iteration2_decodes() {
        let json =
            ##"{"type":"plan_approval_required","turn":0,"data":{"plan":"# revised","iteration":2}}"##
        let payload = event(type: "plan_approval_required", json: json).decoded()
        XCTAssertEqual(payload, .planApprovalRequired(plan: "# revised", iteration: 2))
    }

    func testPlanRevised_decodes() {
        // Marks the boundary between plan iterations. iteration = the one
        // we're about to produce; notes = the user's replace_feedback text.
        let json =
            ##"{"type":"plan_revised","turn":0,"data":{"iteration":2,"notes":"tighten step 3"}}"##
        let payload = event(type: "plan_revised", json: json).decoded()
        XCTAssertEqual(payload, .planRevised(iteration: 2, notes: "tighten step 3"))
    }

    func testStuckDetected_decodes() {
        let json = #"{"type":"stuck_detected","data":{"reason":"edit-loop"}}"#
        let payload = event(type: "stuck_detected", json: json).decoded()
        XCTAssertEqual(payload, .stuckDetected(reason: "edit-loop"))
    }

    func testBudgetExceeded_turns() {
        let json = #"{"type":"budget_exceeded","data":{"budget":"turns"}}"#
        let payload = event(type: "budget_exceeded", json: json).decoded()
        XCTAssertEqual(payload, .budgetExceeded(budget: .turns))
    }

    func testBudgetExceeded_wallClock() {
        let json = #"{"type":"budget_exceeded","data":{"budget":"wall_clock"}}"#
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
            #"{"type":"session_end","data":{"exit_code":0,"total_turns":7,"total_tokens":234567}}"#
        let payload = event(type: "session_end", json: json).decoded()
        XCTAssertEqual(
            payload,
            .sessionEnd(exitCode: 0, totalTurns: 7, totalTokens: 234_567))
    }

    func testSessionEnd_optionalsAbsent() {
        let json = #"{"type":"session_end","data":{"exit_code":13}}"#
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
        // turn_start expects an int turn at the top level; strings don't decode.
        let json = #"{"type":"turn_start","turn":"seven"}"#
        let payload = event(type: "turn_start", json: json).decoded()
        XCTAssertEqual(payload, .other(type: "turn_start", json: json))
    }

    func testKnownTypeMissingRequiredField_fallsToOther() {
        // sensor_result requires name + exit_code + duration_ms.
        let json = #"{"type":"sensor_result","data":{"name":"build"}}"#
        let payload = event(type: "sensor_result", json: json).decoded()
        XCTAssertEqual(payload, .other(type: "sensor_result", json: json))
    }
}
