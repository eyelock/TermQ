import Foundation

/// Sendable parallel to `TermQCore.AgentConfig`, used by `Card` and the
/// MCP/CLI output layers.
///
/// Wire format matches `TermQCore.AgentConfig` so a single board.json
/// agent block decodes cleanly into either type. All enum fields are
/// stored as raw strings rather than typed enums — TermQCore's enums
/// aren't visible here, and the MCP surface wants stable string values
/// for downstream consumers anyway.
public struct AgentConfigSummary: Codable, Sendable, Equatable {
    public let sessionId: UUID
    public let harness: String
    public let backend: String
    public let mode: String
    public let interactionMode: String
    public let status: String
    public let budget: AgentBudgetSummary
    public let loopDriverCommand: String

    enum CodingKeys: String, CodingKey {
        case sessionId, harness, backend, mode, interactionMode, budget, status, loopDriverCommand
    }

    public init(
        sessionId: UUID,
        harness: String,
        backend: String,
        mode: String,
        interactionMode: String,
        status: String,
        budget: AgentBudgetSummary,
        loopDriverCommand: String = ""
    ) {
        self.sessionId = sessionId
        self.harness = harness
        self.backend = backend
        self.mode = mode
        self.interactionMode = interactionMode
        self.status = status
        self.budget = budget
        self.loopDriverCommand = loopDriverCommand
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        harness = try container.decode(String.self, forKey: .harness)
        backend = try container.decode(String.self, forKey: .backend)
        mode = try container.decode(String.self, forKey: .mode)
        interactionMode = try container.decode(String.self, forKey: .interactionMode)
        status = try container.decode(String.self, forKey: .status)
        budget = try container.decode(AgentBudgetSummary.self, forKey: .budget)
        loopDriverCommand =
            try container.decodeIfPresent(String.self, forKey: .loopDriverCommand) ?? ""
    }
}

public struct AgentBudgetSummary: Codable, Sendable, Equatable {
    public let maxTurns: Int
    public let maxTokens: Int
    public let maxWallSeconds: Int

    public init(maxTurns: Int, maxTokens: Int, maxWallSeconds: Int) {
        self.maxTurns = maxTurns
        self.maxTokens = maxTokens
        self.maxWallSeconds = maxWallSeconds
    }
}
