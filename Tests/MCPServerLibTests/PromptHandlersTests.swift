import Foundation
import MCP
import XCTest

@testable import MCPServerLib

/// Tests for prompt handler implementations
final class PromptHandlersTests: XCTestCase {
    var tempDirectory: URL!
    var server: TermQMCPServer!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-PromptTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        server = nil
    }

    // MARK: - Helper

    private func createTestBoard(
        columns: [(UUID, String, Int)] = [], cards: [(String, UUID, String, String)] = []
    )
        throws
    {
        var columnJSON: [[String: Any]] = []
        for (id, name, order) in columns {
            columnJSON.append([
                "id": id.uuidString,
                "name": name,
                "orderIndex": order,
                "color": "#6B7280",
            ])
        }

        var cardJSON: [[String: Any]] = []
        for (title, columnId, llmPrompt, llmNextAction) in cards {
            cardJSON.append([
                "id": UUID().uuidString,
                "title": title,
                "description": "",
                "columnId": columnId.uuidString,
                "orderIndex": 0,
                "workingDirectory": "/tmp",
                "llmPrompt": llmPrompt,
                "llmNextAction": llmNextAction,
                "tags": [] as [[String: Any]],
            ])
        }

        let boardDict: [String: Any] = ["columns": columnJSON, "cards": cardJSON]
        let data = try JSONSerialization.data(withJSONObject: boardDict)
        try data.write(to: tempDirectory.appendingPathComponent("board.json"))

        server = TermQMCPServer(dataDirectory: tempDirectory)
    }

    // MARK: - Session Start Prompt Tests

    func testSessionStartPromptWithValidBoard() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [(columnId, "To Do", 0)],
            cards: [("Test Card", columnId, "", "")]
        )

        let params = GetPrompt.Parameters(name: "session_start", arguments: nil)
        let result = try await server.dispatchPromptGet(params)

        XCTAssertEqual(result.description, "TermQ Session Start")
        XCTAssertEqual(result.messages.count, 1)

        let text = extractText(from: result.messages[0])
        XCTAssertTrue(text.contains("TermQ Session Start"))
        XCTAssertTrue(text.contains("Board Overview"))
    }

    func testSessionStartPromptWithPendingActions() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [(columnId, "To Do", 0)],
            cards: [
                ("Card 1", columnId, "", "Fix the bug"),
                ("Card 2", columnId, "", "Review PR"),
            ]
        )

        let params = GetPrompt.Parameters(name: "session_start", arguments: nil)
        let result = try await server.dispatchPromptGet(params)

        let text = extractText(from: result.messages[0])
        XCTAssertTrue(text.contains("Pending Actions"))
        XCTAssertTrue(text.contains("Fix the bug"))
        XCTAssertTrue(text.contains("Review PR"))
    }

    func testSessionStartPromptNoPendingActions() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [(columnId, "To Do", 0)],
            cards: [("Card 1", columnId, "", "")]  // No llmNextAction
        )

        let params = GetPrompt.Parameters(name: "session_start", arguments: nil)
        let result = try await server.dispatchPromptGet(params)

        let text = extractText(from: result.messages[0])
        XCTAssertTrue(text.contains("No pending actions"))
    }

    func testSessionStartPromptWithLoadError() async throws {
        // Server with no board.json
        server = TermQMCPServer(dataDirectory: tempDirectory)

        let params = GetPrompt.Parameters(name: "session_start", arguments: nil)
        let result = try await server.dispatchPromptGet(params)

        let text = extractText(from: result.messages[0])
        // Should contain error message but not crash
        XCTAssertTrue(text.contains("Error loading board"))
        XCTAssertTrue(text.contains("TermQ has been run at least once"))
    }

    func testSessionStartPromptShowsBoardOverview() async throws {
        let col1 = UUID()
        let col2 = UUID()
        try createTestBoard(
            columns: [(col1, "To Do", 0), (col2, "Done", 1)],
            cards: [
                ("Card 1", col1, "", ""),
                ("Card 2", col1, "", ""),
                ("Card 3", col2, "", ""),
            ]
        )

        let params = GetPrompt.Parameters(name: "session_start", arguments: nil)
        let result = try await server.dispatchPromptGet(params)

        let text = extractText(from: result.messages[0])
        XCTAssertTrue(text.contains("To Do: 2 terminals"))
        XCTAssertTrue(text.contains("Done: 1 terminals"))
    }

    // MARK: - Workflow Guide Prompt Tests

    func testWorkflowGuidePrompt() async throws {
        try createTestBoard(columns: [], cards: [])

        let params = GetPrompt.Parameters(name: "workflow_guide", arguments: nil)
        let result = try await server.dispatchPromptGet(params)

        XCTAssertEqual(result.description, "TermQ Workflow Guide")
        XCTAssertEqual(result.messages.count, 1)

        let text = extractText(from: result.messages[0])
        XCTAssertTrue(text.contains("SESSION START CHECKLIST"))
        XCTAssertTrue(text.contains("SESSION END CHECKLIST"))
        XCTAssertTrue(text.contains("TAG SCHEMA"))
    }

    // MARK: - Terminal Summary Prompt Tests

    func testTerminalSummaryPromptSuccess() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [(columnId, "To Do", 0)],
            cards: [("My Terminal", columnId, "Python project", "Fix bug #123")]
        )

        let params = GetPrompt.Parameters(
            name: "terminal_summary",
            arguments: ["terminal": .string("My Terminal")]
        )
        let result = try await server.dispatchPromptGet(params)

        XCTAssertTrue(result.description?.contains("Terminal Summary") ?? false)

        let text = extractText(from: result.messages[0])
        XCTAssertTrue(text.contains("Terminal Summary"))
        XCTAssertTrue(text.contains("My Terminal"))
        XCTAssertTrue(text.contains("Python project"))
        XCTAssertTrue(text.contains("Fix bug #123"))
    }

    func testTerminalSummaryPromptNotFound() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [(columnId, "To Do", 0)],
            cards: []
        )

        let params = GetPrompt.Parameters(
            name: "terminal_summary",
            arguments: ["terminal": .string("NonExistent")]
        )
        let result = try await server.dispatchPromptGet(params)

        let text = extractText(from: result.messages[0])
        XCTAssertTrue(text.contains("Terminal not found"))
    }

    func testTerminalSummaryPromptWithDescription() async throws {
        let columnId = UUID()

        // Create board with a card that has a description
        let cardJSON: [String: Any] = [
            "id": UUID().uuidString,
            "title": "Described Card",
            "description": "This is a detailed description of the card",
            "columnId": columnId.uuidString,
            "orderIndex": 0,
            "workingDirectory": "/tmp",
            "llmPrompt": "",
            "llmNextAction": "",
            "tags": [] as [[String: Any]],
        ]

        let columnJSON: [[String: Any]] = [
            [
                "id": columnId.uuidString,
                "name": "To Do",
                "orderIndex": 0,
                "color": "#6B7280",
            ]
        ]

        let boardDict: [String: Any] = ["columns": columnJSON, "cards": [cardJSON]]
        let data = try JSONSerialization.data(withJSONObject: boardDict)
        try data.write(to: tempDirectory.appendingPathComponent("board.json"))

        server = TermQMCPServer(dataDirectory: tempDirectory)

        let params = GetPrompt.Parameters(
            name: "terminal_summary",
            arguments: ["terminal": .string("Described Card")]
        )
        let result = try await server.dispatchPromptGet(params)

        let text = extractText(from: result.messages[0])
        XCTAssertTrue(text.contains("Description"))
        XCTAssertTrue(text.contains("detailed description"))
    }

    func testTerminalSummaryPromptWithTags() async throws {
        let columnId = UUID()

        let cardJSON: [String: Any] = [
            "id": UUID().uuidString,
            "title": "Tagged Card",
            "description": "",
            "columnId": columnId.uuidString,
            "orderIndex": 0,
            "workingDirectory": "/tmp",
            "llmPrompt": "",
            "llmNextAction": "",
            "tags": [
                ["id": UUID().uuidString, "key": "env", "value": "production"],
                ["id": UUID().uuidString, "key": "type", "value": "feature"],
            ],
        ]

        let columnJSON: [[String: Any]] = [
            [
                "id": columnId.uuidString,
                "name": "To Do",
                "orderIndex": 0,
                "color": "#6B7280",
            ]
        ]

        let boardDict: [String: Any] = ["columns": columnJSON, "cards": [cardJSON]]
        let data = try JSONSerialization.data(withJSONObject: boardDict)
        try data.write(to: tempDirectory.appendingPathComponent("board.json"))

        server = TermQMCPServer(dataDirectory: tempDirectory)

        let params = GetPrompt.Parameters(
            name: "terminal_summary",
            arguments: ["terminal": .string("Tagged Card")]
        )
        let result = try await server.dispatchPromptGet(params)

        let text = extractText(from: result.messages[0])
        XCTAssertTrue(text.contains("Tags"))
        XCTAssertTrue(text.contains("env: production"))
        XCTAssertTrue(text.contains("type: feature"))
    }

    func testTerminalSummaryPromptWithLoadError() async throws {
        server = TermQMCPServer(dataDirectory: tempDirectory)

        let params = GetPrompt.Parameters(
            name: "terminal_summary",
            arguments: ["terminal": .string("Test")]
        )
        let result = try await server.dispatchPromptGet(params)

        let text = extractText(from: result.messages[0])
        XCTAssertTrue(text.contains("Error loading board"))
    }

    func testTerminalSummaryPromptWithDefaultIdentifier() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [(columnId, "To Do", 0)],
            cards: []
        )

        // No terminal argument provided
        let params = GetPrompt.Parameters(name: "terminal_summary", arguments: nil)
        let result = try await server.dispatchPromptGet(params)

        let text = extractText(from: result.messages[0])
        // Should handle missing argument gracefully
        XCTAssertTrue(text.contains("Terminal not found") || text.contains("unknown"))
    }

    // MARK: - Unknown Prompt Tests

    func testUnknownPromptThrows() async throws {
        try createTestBoard(columns: [], cards: [])

        let params = GetPrompt.Parameters(name: "unknown_prompt_name", arguments: nil)

        do {
            _ = try await server.dispatchPromptGet(params)
            XCTFail("Should have thrown for unknown prompt")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Unknown prompt"))
        }
    }

    // MARK: - Helper

    private func extractText(from message: Prompt.Message) -> String {
        if case .text(let text) = message.content {
            return text
        }
        return ""
    }
}
