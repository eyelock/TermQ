import Foundation

/// Typed view onto an agent loop driver trajectory event.
///
/// Decoded from a `TrajectoryEvent`'s `payloadJSON` using the `type` field
/// as the discriminator. Unknown event types decode as `.other` so future
/// loop-driver upgrades can introduce new variants without breaking TermQ.
///
/// The wire format is a contract between TermQ and the `ynh-agent` loop
/// driver binary (planned, not yet shipped). Field names use snake_case,
/// matching the YNH structured-output convention. Timestamps are ISO 8601
/// strings on the wire and are surfaced via `TrajectoryEvent.timestamp`,
/// not duplicated here.
public enum TrajectoryEventPayload: Sendable, Equatable {
    /// `session_start` — emitted once at the very beginning of a session.
    case sessionStart(sessionId: String, harness: String?)

    /// `plan` — agent has written a plan to disk; content is the markdown.
    case plan(content: String)

    /// `turn_start` — start of an agent turn within the act phase.
    case turnStart(turn: Int)

    /// `sensor_result` — one sensor's mechanical run completed.
    case sensorResult(name: String, exitCode: Int, durationMs: Int, summary: String?)

    /// `turn_approval_required` — loop driver is paused awaiting user review of
    /// synthesized feedback before injecting it as the next worker turn.
    /// The driver accepts `approve_turn` (proceed with existing feedback) and
    /// `replace_feedback` (replace content before proceeding) on stdin.
    case turnApprovalRequired(turn: Int, synthesizedFeedback: String)

    /// `stuck_detected` — watchdog fired (edit-loop, oscillation, etc.).
    case stuckDetected(reason: String)

    /// `budget_exceeded` — one of turns/tokens/wall-clock cap fired.
    case budgetExceeded(budget: BudgetKind)

    /// `converged` — sensors all green and convergence verifier (if any) passed.
    case converged

    /// `session_end` — terminal state with exit code and totals.
    case sessionEnd(exitCode: Int, totalTurns: Int?, totalTokens: Int?)

    /// Unrecognised event type or malformed typed payload. The original
    /// NDJSON line is preserved so consumers can salvage what they need.
    case other(type: String, json: String)

    public enum BudgetKind: String, Sendable, Equatable, Codable {
        case turns
        case tokens
        case wallClock = "wall_clock"
    }
}

// MARK: - TrajectoryEvent decoding

extension TrajectoryEvent {
    /// Decode `payloadJSON` into a typed `TrajectoryEventPayload`. Returns
    /// `.other(type:json:)` for unrecognised event types or for typed
    /// variants whose required fields are missing or malformed.
    public func decoded() -> TrajectoryEventPayload {
        guard let data = payloadJSON.data(using: .utf8) else {
            return .other(type: type, json: payloadJSON)
        }
        let decoder = JSONDecoder()
        switch type {
        case "session_start":
            if let p = try? decoder.decode(SessionStartWire.self, from: data) {
                return .sessionStart(sessionId: p.sessionId, harness: p.harness)
            }
        case "plan":
            if let p = try? decoder.decode(PlanWire.self, from: data) {
                return .plan(content: p.content)
            }
        case "turn_start":
            if let p = try? decoder.decode(TurnStartWire.self, from: data) {
                return .turnStart(turn: p.turn)
            }
        case "sensor_result":
            if let p = try? decoder.decode(SensorResultWire.self, from: data) {
                return .sensorResult(
                    name: p.name,
                    exitCode: p.exitCode,
                    durationMs: p.durationMs,
                    summary: p.summary
                )
            }
        case "turn_approval_required":
            if let p = try? decoder.decode(TurnApprovalRequiredWire.self, from: data) {
                return .turnApprovalRequired(turn: p.turn, synthesizedFeedback: p.synthesizedFeedback)
            }
        case "stuck_detected":
            if let p = try? decoder.decode(StuckDetectedWire.self, from: data) {
                return .stuckDetected(reason: p.reason)
            }
        case "budget_exceeded":
            if let p = try? decoder.decode(BudgetExceededWire.self, from: data) {
                return .budgetExceeded(budget: p.budget)
            }
        case "converged":
            return .converged
        case "session_end":
            if let p = try? decoder.decode(SessionEndWire.self, from: data) {
                return .sessionEnd(
                    exitCode: p.exitCode,
                    totalTurns: p.totalTurns,
                    totalTokens: p.totalTokens
                )
            }
        default:
            break
        }
        return .other(type: type, json: payloadJSON)
    }
}

// MARK: - Wire structs (private)

private struct SessionStartWire: Decodable {
    let sessionId: String
    let harness: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case harness
    }
}

private struct PlanWire: Decodable {
    let content: String
}

private struct TurnStartWire: Decodable {
    let turn: Int
}

private struct SensorResultWire: Decodable {
    let name: String
    let exitCode: Int
    let durationMs: Int
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case name, summary
        case exitCode = "exit_code"
        case durationMs = "duration_ms"
    }
}

private struct TurnApprovalRequiredWire: Decodable {
    let turn: Int
    let synthesizedFeedback: String

    enum CodingKeys: String, CodingKey {
        case turn
        case synthesizedFeedback = "synthesized_feedback"
    }
}

private struct StuckDetectedWire: Decodable {
    let reason: String
}

private struct BudgetExceededWire: Decodable {
    let budget: TrajectoryEventPayload.BudgetKind
}

private struct SessionEndWire: Decodable {
    let exitCode: Int
    let totalTurns: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case exitCode = "exit_code"
        case totalTurns = "total_turns"
        case totalTokens = "total_tokens"
    }
}
