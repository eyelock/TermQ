import Foundation
import XCTest

@testable import TermQCore

final class AgentSessionTests: XCTestCase {
    func testAgentBudgetDefaults() {
        let budget = AgentBudget.default
        XCTAssertEqual(budget.maxTurns, 25)
        XCTAssertEqual(budget.maxTokens, 500_000)
        XCTAssertEqual(budget.maxWallSeconds, 3600)
    }

    func testAgentConfigInitDefaults() {
        let config = AgentConfig(harness: "coding-agent@eyelock/harnesses")
        XCTAssertEqual(config.harness, "coding-agent@eyelock/harnesses")
        XCTAssertEqual(config.backend, .claudeCode)
        XCTAssertEqual(config.mode, .plan)
        XCTAssertEqual(config.interactionMode, .confirm)
        XCTAssertEqual(config.budget, .default)
        XCTAssertEqual(config.status, .idle)
        XCTAssertEqual(config.loopDriverCommand, "")
    }

    /// Backward compat — pre-slice-20 saved JSON has no `loopDriverCommand`
    /// field. Decoding must default it to "" rather than throw.
    func testAgentConfigLegacyJSONBackwardCompat() throws {
        let json = """
            {
                "sessionId": "\(UUID().uuidString)",
                "harness": "x@y/z",
                "backend": "claude-code",
                "mode": "plan",
                "interactionMode": "confirm",
                "budget": {
                    "maxTurns": 25,
                    "maxTokens": 500000,
                    "maxWallSeconds": 3600
                },
                "status": "idle"
            }
            """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AgentConfig.self, from: json)
        XCTAssertEqual(decoded.loopDriverCommand, "")
    }

    func testAgentConfigCodableRoundTrip() throws {
        let original = AgentConfig(
            sessionId: UUID(),
            harness: "x@y/z",
            backend: .codex,
            mode: .act,
            interactionMode: .tweak,
            budget: AgentBudget(maxTurns: 10, maxTokens: 100_000, maxWallSeconds: 600),
            status: .running
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentConfig.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testAgentBackendRawValues() {
        // Stable wire format — guard against accidental rename.
        XCTAssertEqual(AgentBackend.claudeCode.rawValue, "claude-code")
        XCTAssertEqual(AgentBackend.codex.rawValue, "codex")
    }

    func testAgentStatusRawValues() {
        // Stable wire format for snake_case multi-word cases.
        XCTAssertEqual(AgentStatus.awaitingPlanApproval.rawValue, "awaiting_plan_approval")
        XCTAssertEqual(AgentStatus.awaitingTurnApproval.rawValue, "awaiting_turn_approval")
    }

    func testTerminalCardWithAgentConfigRoundTrip() throws {
        let columnId = UUID()
        let config = AgentConfig(harness: "coding-agent@eyelock/harnesses", status: .running)
        let card = TerminalCard(columnId: columnId, agentConfig: config)

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(TerminalCard.self, from: data)

        XCTAssertEqual(decoded.agentConfig, config)
    }

    func testTerminalCardWithoutAgentConfigRoundTrip() throws {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId)

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(TerminalCard.self, from: data)

        XCTAssertNil(decoded.agentConfig)
    }

    /// Backward compatibility — pre-agent JSON (no `agentConfig` key) must decode
    /// without error and yield `agentConfig == nil`.
    func testTerminalCardLegacyJSONBackwardCompat() throws {
        let columnId = UUID()
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Legacy Card",
                "description": "",
                "tags": [],
                "columnId": "\(columnId.uuidString)",
                "orderIndex": 0,
                "shellPath": "/bin/zsh",
                "workingDirectory": "/tmp",
                "isFavourite": false,
                "initCommand": "",
                "llmPrompt": "",
                "llmNextAction": "",
                "badge": "",
                "fontName": "",
                "fontSize": 0,
                "safePasteEnabled": true,
                "themeId": "",
                "allowAutorun": false,
                "allowOscClipboard": true,
                "confirmExternalModifications": true,
                "backend": "direct",
                "needsTmuxSession": false,
                "environmentVariables": []
            }
            """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TerminalCard.self, from: json)
        XCTAssertNil(decoded.agentConfig)
        XCTAssertEqual(decoded.title, "Legacy Card")
    }
}
