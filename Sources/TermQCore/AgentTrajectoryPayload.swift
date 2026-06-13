import Foundation

/// Typed view onto an agent loop driver trajectory event.
///
/// Decoded from a `TrajectoryEvent`'s `payloadJSON` using the `type` field
/// as the discriminator. Unknown event types decode as `.other` so future
/// loop-driver upgrades can introduce new variants without breaking TermQ.
///
/// ## Wire format
///
/// ynh's trajectory NDJSON puts `timestamp` and `type` at the top level on
/// every event, and is *not* consistent about where the rest of the
/// payload lives. Three observed shapes:
///
/// 1. **Nested object** under `data`:
///    `{"type":"session_start","data":{"session_id":"...","harness":"..."}}`
/// 2. **Top-level scalar fields** alongside `type`:
///    `{"type":"turn_start","turn":1}`
/// 3. **`data` is a string** (assistant text):
///    `{"type":"assistant_message","turn":1,"data":"hello"}`
///
/// Each `case` below documents which shape it expects.
public enum TrajectoryEventPayload: Sendable, Equatable {
    /// `session_start` — emitted once at the very beginning of a session.
    /// Wire: nested `data` object with `session_id`/`harness`.
    case sessionStart(sessionId: String, harness: String?)

    /// `plan` — agent entered plan mode (bare marker today). Wire: no `data`
    /// in current ynh; the plan content arrives via subsequent
    /// `assistant_message` events. The `content` accessor is kept on the
    /// case for the day ynh learns to include inline plan text — for now
    /// it's empty string.
    case plan(content: String)

    /// `plan_approval_required` (ynh 0.5+) — plan-phase approval gate. The
    /// `plan` field carries the full plan text directly (no scanning
    /// assistant messages); `iteration` is the 1-based iteration number,
    /// matching any preceding `plan_revised` event's `iteration` field.
    /// Wire: nested `data` with `plan`/`iteration`; top-level `turn` ignored.
    case planApprovalRequired(plan: String, iteration: Int)

    /// `plan_revised` (ynh 0.5+) — emitted at the start of plan iterations
    /// 2+, before the new plan content arrives. `iteration` is the
    /// iteration we're about to produce; `notes` is the user's refinement
    /// payload that triggered the revision. Initial iteration is *not*
    /// preceded by this event — it's bounded by `KindPlan` instead.
    /// Wire: nested `data` with `iteration`/`notes`.
    case planRevised(iteration: Int, notes: String)

    /// `turn_start` — start of an agent turn within the act phase.
    /// Wire: top-level `turn`.
    case turnStart(turn: Int)

    /// `assistant_message` — natural-language output from the agent. This
    /// carries the bulk of what the user actually wants to read (plan
    /// drafts, status, questions, etc.). Wire: optional top-level `turn`,
    /// top-level `data` field whose value is a plain string.
    case assistantMessage(turn: Int?, content: String)

    /// `sensor_result` — one sensor's mechanical run completed.
    /// Wire: nested `data` object.
    case sensorResult(name: String, exitCode: Int, durationMs: Int, summary: String?)

    /// `turn_approval_required` — loop driver is paused awaiting user review of
    /// synthesized feedback before injecting it as the next worker turn.
    /// Wire: nested `data` object.
    case turnApprovalRequired(turn: Int, synthesizedFeedback: String)

    /// `stuck_detected` — watchdog fired. Wire: nested `data.reason`.
    case stuckDetected(reason: String)

    /// `budget_exceeded` — one of turns/tokens/wall-clock cap fired.
    /// Wire: nested `data.budget`.
    case budgetExceeded(budget: BudgetKind)

    /// `converged` — sensors all green and convergence verifier (if any) passed.
    /// Wire: marker; ynh attaches an optional top-level `turn` which we ignore.
    case converged

    /// `session_end` — terminal state with exit code and totals.
    /// Wire: nested `data` with `exit_code`/`total_turns`/`total_tokens`;
    /// optional top-level `turn` ignored.
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
        guard let bytes = payloadJSON.data(using: .utf8) else {
            return .other(type: type, json: payloadJSON)
        }
        let decoder = JSONDecoder()
        if let payload = decodeSessionFamily(decoder: decoder, bytes: bytes) {
            return payload
        }
        if let payload = decodeTurnFamily(decoder: decoder, bytes: bytes) {
            return payload
        }
        if let payload = decodePlanFamily(decoder: decoder, bytes: bytes) {
            return payload
        }
        if let payload = decodeSensorFamily(decoder: decoder, bytes: bytes) {
            return payload
        }
        return .other(type: type, json: payloadJSON)
    }

    /// Decodes `session_start`, `session_end`, and `converged` markers.
    /// Returns `nil` if `type` is not one of these.
    private func decodeSessionFamily(decoder: JSONDecoder, bytes: Data) -> TrajectoryEventPayload? {
        switch type {
        case "session_start":
            if let wire = try? decoder.decode(SessionStartWire.self, from: bytes) {
                return .sessionStart(sessionId: wire.data.sessionId, harness: wire.data.harness)
            }
        case "converged":
            return .converged
        case "session_end":
            if let wire = try? decoder.decode(SessionEndWire.self, from: bytes) {
                return .sessionEnd(
                    exitCode: wire.data.exitCode,
                    totalTurns: wire.data.totalTurns,
                    totalTokens: wire.data.totalTokens
                )
            }
        default:
            return nil
        }
        return nil
    }

    /// Decodes turn-scoped events: `turn_start`, `assistant_message`, and
    /// `turn_approval_required`. Returns `nil` if `type` is not one of these.
    private func decodeTurnFamily(decoder: JSONDecoder, bytes: Data) -> TrajectoryEventPayload? {
        switch type {
        case "turn_start":
            if let wire = try? decoder.decode(TurnStartWire.self, from: bytes) {
                return .turnStart(turn: wire.turn)
            }
        case "assistant_message":
            if let wire = try? decoder.decode(AssistantMessageWire.self, from: bytes) {
                return .assistantMessage(turn: wire.turn, content: wire.data ?? "")
            }
        case "turn_approval_required":
            if let wire = try? decoder.decode(TurnApprovalRequiredWire.self, from: bytes) {
                return .turnApprovalRequired(
                    turn: wire.turn, synthesizedFeedback: wire.data.synthesizedFeedback)
            }
        default:
            return nil
        }
        return nil
    }

    /// Decodes plan-phase events: `plan`, `plan_approval_required`, and
    /// `plan_revised`. Returns `nil` if `type` is not one of these.
    private func decodePlanFamily(decoder: JSONDecoder, bytes: Data) -> TrajectoryEventPayload? {
        switch type {
        case "plan":
            // Tolerate (a) no `data` key, (b) `data` as object without
            // `content`, (c) `data` as object with `content`. ynh today
            // emits (a); leaving room for (c).
            let content = (try? decoder.decode(PlanWire.self, from: bytes))?.data?.content
            return .plan(content: content ?? "")
        case "plan_approval_required":
            if let wire = try? decoder.decode(PlanApprovalRequiredWire.self, from: bytes) {
                return .planApprovalRequired(plan: wire.data.plan, iteration: wire.data.iteration)
            }
        case "plan_revised":
            if let wire = try? decoder.decode(PlanRevisedWire.self, from: bytes) {
                return .planRevised(iteration: wire.data.iteration, notes: wire.data.notes)
            }
        default:
            return nil
        }
        return nil
    }

    /// Decodes sensor and watchdog events: `sensor_result`, `stuck_detected`,
    /// and `budget_exceeded`. Returns `nil` if `type` is not one of these.
    private func decodeSensorFamily(decoder: JSONDecoder, bytes: Data) -> TrajectoryEventPayload? {
        switch type {
        case "sensor_result":
            if let wire = try? decoder.decode(SensorResultWire.self, from: bytes) {
                return .sensorResult(
                    name: wire.data.name,
                    exitCode: wire.data.exitCode,
                    durationMs: wire.data.durationMs,
                    summary: wire.data.summary
                )
            }
        case "stuck_detected":
            if let wire = try? decoder.decode(StuckDetectedWire.self, from: bytes) {
                return .stuckDetected(reason: wire.data.reason)
            }
        case "budget_exceeded":
            if let wire = try? decoder.decode(BudgetExceededWire.self, from: bytes) {
                return .budgetExceeded(budget: wire.data.budget)
            }
        default:
            return nil
        }
        return nil
    }
}

// MARK: - Wire structs (private)

// Events with a nested `data` object —

private struct SessionStartWire: Decodable {
    let data: SessionStartData
    struct SessionStartData: Decodable {
        let sessionId: String
        let harness: String?
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case harness
        }
    }
}

private struct PlanWire: Decodable {
    let data: PlanData?
    struct PlanData: Decodable {
        let content: String?
    }
}

private struct SensorResultWire: Decodable {
    let data: SensorResultData
    struct SensorResultData: Decodable {
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
}

/// ynh 0.5+: dedicated plan-phase approval event. `plan` carries the
/// full plan text; `iteration` is 1-based.
private struct PlanApprovalRequiredWire: Decodable {
    let data: PlanApprovalRequiredData
    struct PlanApprovalRequiredData: Decodable {
        let plan: String
        let iteration: Int
    }
}

/// ynh 0.5+: plan iteration boundary. `iteration` is the iteration about
/// to be produced; `notes` is the user's refinement input.
private struct PlanRevisedWire: Decodable {
    let data: PlanRevisedData
    struct PlanRevisedData: Decodable {
        let iteration: Int
        let notes: String
    }
}

/// ynh emits `turn` at the top level (matching the Event envelope) and
/// nests only `synthesized_feedback` inside `data`. Plan-phase approval
/// gates arrive with `turn: 0`; act-phase turn gates with `turn: 1..N`.
private struct TurnApprovalRequiredWire: Decodable {
    let turn: Int
    let data: TurnApprovalRequiredData
    struct TurnApprovalRequiredData: Decodable {
        let synthesizedFeedback: String
        enum CodingKeys: String, CodingKey {
            case synthesizedFeedback = "synthesized_feedback"
        }
    }
}

private struct StuckDetectedWire: Decodable {
    let data: StuckDetectedData
    struct StuckDetectedData: Decodable {
        let reason: String
    }
}

private struct BudgetExceededWire: Decodable {
    let data: BudgetExceededData
    struct BudgetExceededData: Decodable {
        let budget: TrajectoryEventPayload.BudgetKind
    }
}

private struct SessionEndWire: Decodable {
    let data: SessionEndData
    struct SessionEndData: Decodable {
        let exitCode: Int
        let totalTurns: Int?
        let totalTokens: Int?
        enum CodingKeys: String, CodingKey {
            case exitCode = "exit_code"
            case totalTurns = "total_turns"
            case totalTokens = "total_tokens"
        }
    }
}

// Events with top-level scalar fields (no `data` object) —

private struct TurnStartWire: Decodable {
    let turn: Int
}

// Events whose `data` value is a plain string —

private struct AssistantMessageWire: Decodable {
    let turn: Int?
    let data: String?
}
