import Foundation
import XCTest

@testable import TermQShared

final class AgentConfigSummaryTests: XCTestCase {

    func testRoundTrip() throws {
        let original = AgentConfigSummary(
            sessionId: UUID(),
            harness: "x@y/z",
            backend: "claude-code",
            mode: "act",
            interactionMode: "tweak",
            status: "running",
            budget: AgentBudgetSummary(maxTurns: 10, maxTokens: 200_000, maxWallSeconds: 600),
            loopDriverCommand: "/path/to/ynh-agent --task t.md"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentConfigSummary.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    /// Wire format must accept legacy JSON without `loopDriverCommand`.
    func testLegacyJSONWithoutLoopDriverCommand_decodesWithEmptyString() throws {
        let json = """
            {
                "sessionId": "\(UUID().uuidString)",
                "harness": "x@y/z",
                "backend": "claude-code",
                "mode": "plan",
                "interactionMode": "confirm",
                "status": "idle",
                "budget": {"maxTurns": 25, "maxTokens": 500000, "maxWallSeconds": 3600}
            }
            """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AgentConfigSummary.self, from: json)
        XCTAssertEqual(decoded.loopDriverCommand, "")
    }

    func testCardWithAgentConfig_decodesIntoSummary() throws {
        let cardJSON = """
            {
                "id": "\(UUID().uuidString)",
                "title": "agent",
                "description": "",
                "tags": [],
                "columnId": "\(UUID().uuidString)",
                "orderIndex": 0,
                "workingDirectory": "/tmp",
                "isFavourite": false,
                "badge": "",
                "llmPrompt": "",
                "llmNextAction": "",
                "allowAutorun": false,
                "needsTmuxSession": false,
                "agentConfig": {
                    "sessionId": "\(UUID().uuidString)",
                    "harness": "x@y/z",
                    "backend": "codex",
                    "mode": "act",
                    "interactionMode": "auto",
                    "status": "converged",
                    "budget": {"maxTurns": 10, "maxTokens": 100000, "maxWallSeconds": 600},
                    "loopDriverCommand": ""
                }
            }
            """.data(using: .utf8)!

        let card = try JSONDecoder().decode(Card.self, from: cardJSON)
        XCTAssertNotNil(card.agentConfig)
        XCTAssertEqual(card.agentConfig?.harness, "x@y/z")
        XCTAssertEqual(card.agentConfig?.status, "converged")
    }

    func testCardWithoutAgentConfig_decodesNil() throws {
        let cardJSON = """
            {
                "id": "\(UUID().uuidString)",
                "title": "regular",
                "description": "",
                "tags": [],
                "columnId": "\(UUID().uuidString)",
                "orderIndex": 0,
                "workingDirectory": "/tmp",
                "isFavourite": false,
                "badge": "",
                "llmPrompt": "",
                "llmNextAction": "",
                "allowAutorun": false,
                "needsTmuxSession": false
            }
            """.data(using: .utf8)!

        let card = try JSONDecoder().decode(Card.self, from: cardJSON)
        XCTAssertNil(card.agentConfig)
    }

    func testAgentSessionOutput_returnsNilForCardWithoutAgent() {
        let card = Card(
            title: "regular",
            columnId: UUID()
        )
        XCTAssertNil(AgentSessionOutput(from: card, columnName: "Col"))
    }

    func testAgentSessionOutput_populatesFromAgentCard() {
        let summary = AgentConfigSummary(
            sessionId: UUID(),
            harness: "x@y/z",
            backend: "claude-code",
            mode: "plan",
            interactionMode: "confirm",
            status: "idle",
            budget: AgentBudgetSummary(maxTurns: 25, maxTokens: 500_000, maxWallSeconds: 3600)
        )
        let card = Card(
            title: "agent",
            columnId: UUID(),
            workingDirectory: "/tmp/work",
            agentConfig: summary
        )

        let output = AgentSessionOutput(from: card, columnName: "Col")
        XCTAssertNotNil(output)
        XCTAssertEqual(output?.name, "agent")
        XCTAssertEqual(output?.column, "Col")
        XCTAssertEqual(output?.path, "/tmp/work")
        XCTAssertEqual(output?.agent, summary)
    }
}
