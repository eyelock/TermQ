import Foundation
import MCP
import XCTest

@testable import MCPServerLib

/// Integration tests for the MCP Server
///
/// These tests verify the MCP server works correctly with realistic test data.
/// They can be run locally to verify MCP functionality without affecting production config.
///
/// To run only these tests:
/// ```
/// swift test --filter MCPIntegrationTests
/// ```
///
/// To skip in CI, use environment variable:
/// ```
/// SKIP_MCP_INTEGRATION_TESTS=1 swift test
/// ```
final class MCPIntegrationTests: XCTestCase {
    var tempDirectory: URL!
    var server: TermQMCPServer!

    override func setUpWithError() throws {
        // Skip if environment variable is set (for CI)
        if ProcessInfo.processInfo.environment["SKIP_MCP_INTEGRATION_TESTS"] == "1" {
            throw XCTSkip("MCP integration tests disabled via environment variable")
        }

        // Create temporary directory for test data
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-MCPTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir

        // Write test board.json
        let boardData = try JSONEncoder().encode(createTestBoard())
        try boardData.write(to: tempDir.appendingPathComponent("board.json"))

        // Create server with test data directory
        server = TermQMCPServer(dataDirectory: tempDirectory)
    }

    override func tearDownWithError() throws {
        // Clean up temporary directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        server = nil
    }

    // MARK: - Test Data Creation

    private func createTestBoard() -> MCPBoard {
        let columns = [
            MCPColumn(id: UUID(), name: "To Do", orderIndex: 0, color: "#FF0000"),
            MCPColumn(id: UUID(), name: "In Progress", orderIndex: 1, color: "#00FF00"),
            MCPColumn(id: UUID(), name: "Done", orderIndex: 2, color: "#0000FF"),
        ]

        let cards = [
            createTestCard(
                title: "Test Terminal 1",
                columnId: columns[0].id,
                workingDirectory: "/Users/test/project1",
                llmNextAction: "Continue implementing feature X",
                tags: [
                    MCPTag(id: UUID(), key: "staleness", value: "fresh"),
                    MCPTag(id: UUID(), key: "project", value: "test/project1"),
                ]
            ),
            createTestCard(
                title: "Test Terminal 2",
                columnId: columns[1].id,
                workingDirectory: "/Users/test/project2",
                llmPrompt: "This is a Python project",
                tags: [
                    MCPTag(id: UUID(), key: "staleness", value: "stale")
                ]
            ),
            createTestCard(
                title: "Favourite Terminal",
                columnId: columns[0].id,
                workingDirectory: "/Users/test/favourite",
                isFavourite: true,
                badge: "urgent,important"
            ),
            createTestCard(
                title: "mcp-toolkit: migrate workflows/hooks",
                columnId: columns[1].id,
                workingDirectory: "/Users/test/mcp-toolkit",
                description: "MCP server migration and session handling"
            ),
        ]

        return MCPBoard(columns: columns, cards: cards)
    }

    private func createTestCard(
        title: String,
        columnId: UUID,
        workingDirectory: String = "",
        isFavourite: Bool = false,
        badge: String = "",
        llmPrompt: String = "",
        llmNextAction: String = "",
        tags: [MCPTag] = [],
        description: String? = nil
    ) -> MCPCard {
        // Create JSON and decode to get proper MCPCard with custom decoder
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "title": title,
            "description": description ?? "Test description for \(title)",
            "columnId": columnId.uuidString,
            "orderIndex": 0,
            "workingDirectory": workingDirectory,
            "isFavourite": isFavourite,
            "badge": badge,
            "llmPrompt": llmPrompt,
            "llmNextAction": llmNextAction,
            "tags": tags.map { ["id": $0.id.uuidString, "key": $0.key, "value": $0.value] },
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MCPCard.self, from: data)
    }

    // MARK: - BoardLoader Tests

    func testBoardLoaderLoadsTestData() throws {
        let board = try server.loadBoard()

        XCTAssertEqual(board.columns.count, 3)
        XCTAssertEqual(board.activeCards.count, 4)
    }

    func testBoardLoaderBackwardsCompatibility() throws {
        // Create a minimal board.json without newer fields (simulating old format)
        let minimalJSON = """
            {
                "columns": [
                    {"id": "\(UUID().uuidString)", "name": "Test", "orderIndex": 0, "color": "#000000"}
                ],
                "cards": [
                    {
                        "id": "\(UUID().uuidString)",
                        "title": "Minimal Card",
                        "columnId": "\(UUID().uuidString)"
                    }
                ]
            }
            """

        let minimalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-MinimalTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: minimalDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: minimalDir) }

        try minimalJSON.write(
            to: minimalDir.appendingPathComponent("board.json"),
            atomically: true,
            encoding: .utf8
        )

        // Should not crash - backwards compatibility
        let board = try BoardLoader.loadBoard(dataDirectory: minimalDir)
        XCTAssertEqual(board.cards.count, 1)
        XCTAssertEqual(board.cards[0].title, "Minimal Card")
        XCTAssertEqual(board.cards[0].llmNextAction, "")  // Default value
        XCTAssertEqual(board.cards[0].llmPrompt, "")  // Default value
    }

    // MARK: - Tool Handler Tests

    func testTermqPendingTool() async throws {
        let result = try await server.handlePending(nil)

        XCTAssertFalse(result.isError ?? false)
        XCTAssertEqual(result.content.count, 1)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        // Parse and verify JSON structure
        let data = json.data(using: .utf8)!
        let output = try JSONDecoder().decode(PendingOutput.self, from: data)

        XCTAssertEqual(output.summary.total, 4)
        XCTAssertEqual(output.summary.withNextAction, 1)  // Only Test Terminal 1 has llmNextAction
        XCTAssertEqual(output.summary.stale, 1)  // Only Test Terminal 2 is stale
        XCTAssertEqual(output.summary.fresh, 1)  // Only Test Terminal 1 is fresh
    }

    func testTermqPendingToolActionsOnly() async throws {
        let args: [String: Value] = ["actionsOnly": .bool(true)]
        let result = try await server.handlePending(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let output = try JSONDecoder().decode(PendingOutput.self, from: data)

        XCTAssertEqual(output.summary.total, 1)  // Only terminals with llmNextAction
        XCTAssertEqual(output.terminals[0].name, "Test Terminal 1")
    }

    func testTermqContextTool() async throws {
        let result = try await server.handleContext()

        XCTAssertFalse(result.isError ?? false)
        XCTAssertEqual(result.content.count, 1)

        guard case .text(let content) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        XCTAssertTrue(content.contains("TermQ MCP Server"))
        XCTAssertTrue(content.contains("SESSION START CHECKLIST"))
    }

    func testTermqListTool() async throws {
        let result = try await server.handleList(nil)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: data)

        XCTAssertEqual(terminals.count, 4)
    }

    func testTermqListToolWithColumnFilter() async throws {
        let args: [String: Value] = ["column": .string("To Do")]
        let result = try await server.handleList(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: data)

        XCTAssertEqual(terminals.count, 2)  // Test Terminal 1 and Favourite Terminal
    }

    func testTermqListToolColumnsOnly() async throws {
        let args: [String: Value] = ["columnsOnly": .bool(true)]
        let result = try await server.handleList(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let columns = try JSONDecoder().decode([ColumnOutput].self, from: data)

        XCTAssertEqual(columns.count, 3)
        XCTAssertEqual(columns[0].name, "To Do")
        XCTAssertEqual(columns[0].terminalCount, 2)
    }

    func testTermqFindToolByName() async throws {
        let args: [String: Value] = ["name": .string("Favourite")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: data)

        XCTAssertEqual(terminals.count, 1)
        XCTAssertEqual(terminals[0].name, "Favourite Terminal")
    }

    func testTermqFindToolByTag() async throws {
        let args: [String: Value] = ["tag": .string("staleness=fresh")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: data)

        XCTAssertEqual(terminals.count, 1)
        XCTAssertEqual(terminals[0].name, "Test Terminal 1")
    }

    func testTermqFindToolByFavourites() async throws {
        let args: [String: Value] = ["favourites": .bool(true)]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: data)

        XCTAssertEqual(terminals.count, 1)
        XCTAssertEqual(terminals[0].name, "Favourite Terminal")
    }

    func testTermqFindToolByBadge() async throws {
        let args: [String: Value] = ["badge": .string("urgent")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: data)

        XCTAssertEqual(terminals.count, 1)
        XCTAssertEqual(terminals[0].name, "Favourite Terminal")
        XCTAssertTrue(terminals[0].badges.contains("urgent"))
    }

    // MARK: - Smart Query Tests

    func testTermqFindToolSmartQueryMatchesNormalizedWords() async throws {
        // Test the user's exact use case: searching for "MCP Toolkit Migrate"
        // should find "mcp-toolkit: migrate workflows/hooks"
        let args: [String: Value] = ["query": .string("MCP Toolkit Migrate")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: data)

        // Should find the mcp-toolkit terminal
        XCTAssertTrue(terminals.contains { $0.name.contains("mcp-toolkit") })
    }

    func testTermqFindToolSmartQueryMatchesDescription() async throws {
        // Search for words that appear in description but not title
        let args: [String: Value] = ["query": .string("server migration session")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: data)

        // Should find the mcp-toolkit terminal by its description
        XCTAssertTrue(terminals.contains { $0.name.contains("mcp-toolkit") })
    }

    func testTermqFindToolSmartQueryReturnsNoResultsForUnmatchedQuery() async throws {
        let args: [String: Value] = ["query": .string("completely unrelated query that matches nothing")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: data)

        XCTAssertEqual(terminals.count, 0)
    }

    func testTermqFindToolSmartQueryWithOtherFilters() async throws {
        // Smart query combined with column filter
        let args: [String: Value] = [
            "query": .string("toolkit"),
            "column": .string("In Progress"),
        ]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: data)

        // Should find mcp-toolkit (matches query and is in "In Progress")
        XCTAssertEqual(terminals.count, 1)
        XCTAssertTrue(terminals[0].name.contains("mcp-toolkit"))
    }

    func testTermqOpenToolByName() async throws {
        let args: [String: Value] = ["identifier": .string("Test Terminal 1")]
        let result = try await server.handleOpen(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let terminal = try JSONDecoder().decode(TerminalOutput.self, from: data)

        XCTAssertEqual(terminal.name, "Test Terminal 1")
        XCTAssertEqual(terminal.path, "/Users/test/project1")
    }

    func testTermqOpenToolNotFound() async throws {
        let args: [String: Value] = ["identifier": .string("NonExistent")]
        let result = try await server.handleOpen(args)

        XCTAssertTrue(result.isError ?? false)

        guard case .text(let message) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        XCTAssertTrue(message.contains("Terminal not found"))
    }

    // MARK: - Write Tools (Return CLI Commands)

    func testTermqCreateToolReturnsCliCommand() async throws {
        let args: [String: Value] = [
            "name": .string("New Terminal"),
            "column": .string("To Do"),
            "path": .string("/Users/test/new"),
        ]
        let result = try await server.handleCreate(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let message) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        // Create should now actually create a terminal and return its details
        XCTAssertTrue(message.contains("New Terminal"), "Should contain the terminal name")
        XCTAssertTrue(message.contains("/Users/test/new") || message.contains("path"), "Should contain the path")
    }

    func testTermqSetToolReturnsCliCommand() async throws {
        let args: [String: Value] = [
            "identifier": .string("Test Terminal 1"),
            "llmNextAction": .string("New action"),
        ]
        let result = try await server.handleSet(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let message) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        // Set should now actually update the terminal and return its details
        XCTAssertTrue(message.contains("Test Terminal 1"), "Should contain the terminal name")
        XCTAssertTrue(
            message.contains("New action") || message.contains("llmNextAction"), "Should contain the updated action")
    }

    func testTermqMoveToolActuallyMovesCard() async throws {
        let args: [String: Value] = [
            "identifier": .string("Test Terminal 1"),
            "column": .string("Done"),
        ]
        let result = try await server.handleMove(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let message) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        // Move should now actually move the terminal and return its details
        XCTAssertTrue(message.contains("Test Terminal 1"), "Should contain the terminal name")
        XCTAssertTrue(message.contains("Done"), "Should contain the new column name")
    }

    // MARK: - Schema Definition Tests

    func testAvailableToolsSchema() {
        let tools = TermQMCPServer.availableTools

        XCTAssertEqual(tools.count, 8)

        let toolNames = Set(tools.map { $0.name })
        XCTAssertTrue(toolNames.contains("termq_pending"))
        XCTAssertTrue(toolNames.contains("termq_context"))
        XCTAssertTrue(toolNames.contains("termq_list"))
        XCTAssertTrue(toolNames.contains("termq_find"))
        XCTAssertTrue(toolNames.contains("termq_open"))
        XCTAssertTrue(toolNames.contains("termq_create"))
        XCTAssertTrue(toolNames.contains("termq_set"))
        XCTAssertTrue(toolNames.contains("termq_move"))
    }

    func testAvailableResourcesSchema() {
        let resources = TermQMCPServer.availableResources

        XCTAssertEqual(resources.count, 4)

        let resourceURIs = Set(resources.map { $0.uri })
        XCTAssertTrue(resourceURIs.contains("termq://terminals"))
        XCTAssertTrue(resourceURIs.contains("termq://columns"))
        XCTAssertTrue(resourceURIs.contains("termq://pending"))
        XCTAssertTrue(resourceURIs.contains("termq://context"))
    }

    func testAvailablePromptsSchema() {
        let prompts = TermQMCPServer.availablePrompts

        XCTAssertEqual(prompts.count, 3)

        let promptNames = Set(prompts.map { $0.name })
        XCTAssertTrue(promptNames.contains("session_start"))
        XCTAssertTrue(promptNames.contains("workflow_guide"))
        XCTAssertTrue(promptNames.contains("terminal_summary"))
    }

    // MARK: - Error Handling Tests

    func testBoardNotFoundError() throws {
        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-EmptyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        do {
            _ = try BoardLoader.loadBoard(dataDirectory: emptyDir)
            XCTFail("Should have thrown boardNotFound error")
        } catch BoardLoader.LoadError.boardNotFound {
            // Expected
        }
    }

    func testInvalidJSONError() throws {
        let invalidDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-InvalidTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: invalidDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: invalidDir) }

        try "invalid json".write(
            to: invalidDir.appendingPathComponent("board.json"),
            atomically: true,
            encoding: .utf8
        )

        do {
            _ = try BoardLoader.loadBoard(dataDirectory: invalidDir)
            XCTFail("Should have thrown decodingFailed error")
        } catch BoardLoader.LoadError.decodingFailed {
            // Expected
        }
    }
}
