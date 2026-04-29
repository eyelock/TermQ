import Foundation

/// Vendor agent runtime that runs as the worker process.
public enum AgentBackend: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case codex
}

/// Lifecycle phase of an agent session.
///
/// `plan` — drafting and awaiting approval; read-only.
/// `act` — approved plan, making changes per the interaction mode.
public enum AgentMode: String, Codable, Sendable, CaseIterable {
    case plan
    case act
}

/// How feedback is handled per turn during `act`.
///
/// `auto` — feedback auto-injects, no per-turn pause.
/// `confirm` — pause to review and edit synthesized feedback before send.
/// `tweak` — pause and allow sensor-declaration overlays before next turn.
public enum AgentInteractionMode: String, Codable, Sendable, CaseIterable {
    case auto
    case confirm
    case tweak
}

/// Runtime state of an agent session.
public enum AgentStatus: String, Codable, Sendable, CaseIterable {
    case idle
    case planning
    case awaitingPlanApproval = "awaiting_plan_approval"
    case running
    case awaitingTurnApproval = "awaiting_turn_approval"
    case paused
    case converged
    case stuck
    case errored
}

/// Hard caps enforced by the loop driver. Any-fires-stops.
public struct AgentBudget: Codable, Sendable, Equatable {
    public var maxTurns: Int
    public var maxTokens: Int
    public var maxWallSeconds: Int

    public static let `default` = AgentBudget(
        maxTurns: 25,
        maxTokens: 500_000,
        maxWallSeconds: 3600
    )

    public init(maxTurns: Int, maxTokens: Int, maxWallSeconds: Int) {
        self.maxTurns = maxTurns
        self.maxTokens = maxTokens
        self.maxWallSeconds = maxWallSeconds
    }
}

/// One trajectory event emitted by an agent loop driver subprocess.
///
/// One event per NDJSON line on the subprocess's stdout. `type` is parsed
/// from the line's top-level `"type"` field for routing; the original JSON
/// string is preserved in `payloadJSON` so downstream consumers can decode
/// the specific event variant they care about without re-parsing.
public struct TrajectoryEvent: Sendable, Equatable {
    public let type: String
    public let timestamp: Date
    public let payloadJSON: String

    public init(type: String, timestamp: Date, payloadJSON: String) {
        self.type = type
        self.timestamp = timestamp
        self.payloadJSON = payloadJSON
    }
}

/// Per-card agent session configuration and state.
///
/// Attached to a `TerminalCard` when the card is acting as an agent session.
/// Non-agent cards have `agentConfig == nil`.
public struct AgentConfig: Codable, Sendable, Equatable {
    /// Stable session identifier; also the directory name under
    /// `~/Library/Application Support/TermQ/agent-sessions/<id>/`.
    public var sessionId: UUID

    /// Qualified YNH harness name (e.g. `coding-agent@eyelock/harnesses`).
    public var harness: String

    public var backend: AgentBackend
    public var mode: AgentMode
    public var interactionMode: AgentInteractionMode
    public var budget: AgentBudget
    public var status: AgentStatus

    /// Per-card override for the loop driver command. Empty string means
    /// "inherit the global `agent.loopDriverCommand` UserDefault".
    public var loopDriverCommand: String

    enum CodingKeys: String, CodingKey {
        case sessionId, harness, backend, mode, interactionMode, budget, status, loopDriverCommand
    }

    public init(
        sessionId: UUID = UUID(),
        harness: String,
        backend: AgentBackend = .claudeCode,
        mode: AgentMode = .plan,
        interactionMode: AgentInteractionMode = .confirm,
        budget: AgentBudget = .default,
        status: AgentStatus = .idle,
        loopDriverCommand: String = ""
    ) {
        self.sessionId = sessionId
        self.harness = harness
        self.backend = backend
        self.mode = mode
        self.interactionMode = interactionMode
        self.budget = budget
        self.status = status
        self.loopDriverCommand = loopDriverCommand
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        harness = try container.decode(String.self, forKey: .harness)
        backend = try container.decode(AgentBackend.self, forKey: .backend)
        mode = try container.decode(AgentMode.self, forKey: .mode)
        interactionMode = try container.decode(AgentInteractionMode.self, forKey: .interactionMode)
        budget = try container.decode(AgentBudget.self, forKey: .budget)
        status = try container.decode(AgentStatus.self, forKey: .status)
        // Backward compat: pre-slice-20 saved cards have no loopDriverCommand.
        loopDriverCommand =
            try container.decodeIfPresent(String.self, forKey: .loopDriverCommand) ?? ""
    }
}
