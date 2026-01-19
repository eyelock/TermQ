import Foundation
import MCP
import TermQShared
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
            MCPColumn(id: UUID(), name: "To Do", description: "Tasks to start", orderIndex: 0, color: "#FF0000"),
            MCPColumn(id: UUID(), name: "In Progress", description: "Active work", orderIndex: 1, color: "#00FF00"),
            MCPColumn(id: UUID(), name: "Done", description: "", orderIndex: 2, color: "#0000FF"),
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
        // Column description should default to empty string for old format
        XCTAssertEqual(board.columns[0].description, "")  // Default value
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

    func testTermqListToolColumnsIncludesDescription() async throws {
        let args: [String: Value] = ["columnsOnly": .bool(true)]
        let result = try await server.handleList(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = json.data(using: .utf8)!
        let columns = try JSONDecoder().decode([ColumnOutput].self, from: data)

        // First column has a description
        XCTAssertEqual(columns[0].description, "Tasks to start")
        // Second column has a description
        XCTAssertEqual(columns[1].description, "Active work")
        // Third column has empty description
        XCTAssertEqual(columns[2].description, "")
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

    // MARK: - Write Tools (Require GUI - Skipped in Unit Tests)
    //
    // These tests are skipped because mutation operations (create, set, move, delete)
    // now use URL schemes to communicate with the TermQ GUI app. Without a running
    // GUI instance, these operations cannot complete. The URL building logic is
    // tested separately in URLOpenerTests.

    func testTermqCreateToolRequiresGUI() async throws {
        // Skip: Create now uses termq://open URL scheme which requires GUI
        throw XCTSkip("Create tool requires running TermQ GUI - test URL building in URLOpenerTests")
    }

    func testTermqSetToolRequiresGUI() async throws {
        // Skip: Set now uses termq://update URL scheme which requires GUI
        throw XCTSkip("Set tool requires running TermQ GUI - test URL building in URLOpenerTests")
    }

    func testTermqMoveToolRequiresGUI() async throws {
        // Skip: Move now uses termq://move URL scheme which requires GUI
        throw XCTSkip("Move tool requires running TermQ GUI - test URL building in URLOpenerTests")
    }

    func testTermqDeleteToolRequiresGUI() async throws {
        // Skip: Delete uses termq://delete URL scheme which requires GUI
        throw XCTSkip("Delete tool requires running TermQ GUI - test URL building in URLOpenerTests")
    }

    // MARK: - Schema Definition Tests

    func testAvailableToolsSchema() {
        let tools = TermQMCPServer.availableTools

        XCTAssertEqual(tools.count, 10)

        let toolNames = Set(tools.map { $0.name })
        XCTAssertTrue(toolNames.contains("termq_pending"))
        XCTAssertTrue(toolNames.contains("termq_context"))
        XCTAssertTrue(toolNames.contains("termq_list"))
        XCTAssertTrue(toolNames.contains("termq_find"))
        XCTAssertTrue(toolNames.contains("termq_open"))
        XCTAssertTrue(toolNames.contains("termq_create"))
        XCTAssertTrue(toolNames.contains("termq_set"))
        XCTAssertTrue(toolNames.contains("termq_move"))
        XCTAssertTrue(toolNames.contains("termq_get"))
        XCTAssertTrue(toolNames.contains("termq_delete"))
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

    // MARK: - Resource Handler Tests

    func testResourceTerminals() async throws {
        let params = ReadResource.Parameters(uri: "termq://terminals")
        let result = try await server.dispatchResourceRead(params)

        XCTAssertEqual(result.contents.count, 1)
        let json = extractResourceText(from: result)
        let data = Data(json.utf8)
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: data)
        XCTAssertEqual(terminals.count, 4)
    }

    func testResourceColumns() async throws {
        let params = ReadResource.Parameters(uri: "termq://columns")
        let result = try await server.dispatchResourceRead(params)

        XCTAssertEqual(result.contents.count, 1)
        let json = extractResourceText(from: result)
        let data = Data(json.utf8)
        let columns = try JSONDecoder().decode([ColumnOutput].self, from: data)
        XCTAssertEqual(columns.count, 3)
        XCTAssertEqual(columns[0].name, "To Do")
    }

    func testResourcePending() async throws {
        let params = ReadResource.Parameters(uri: "termq://pending")
        let result = try await server.dispatchResourceRead(params)

        XCTAssertEqual(result.contents.count, 1)
        let json = extractResourceText(from: result)
        let data = Data(json.utf8)
        let output = try JSONDecoder().decode(PendingOutput.self, from: data)
        XCTAssertEqual(output.summary.total, 4)
    }

    func testResourceContext() async throws {
        let params = ReadResource.Parameters(uri: "termq://context")
        let result = try await server.dispatchResourceRead(params)

        XCTAssertEqual(result.contents.count, 1)
        let content = extractResourceText(from: result)
        XCTAssertTrue(content.contains("TermQ MCP Server"))
        XCTAssertTrue(content.contains("SESSION START CHECKLIST"))
    }

    func testResourceUnknownUri() async throws {
        let params = ReadResource.Parameters(uri: "termq://unknown")

        do {
            _ = try await server.dispatchResourceRead(params)
            XCTFail("Should have thrown for unknown resource")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Unknown resource"))
        }
    }

    // Helper to extract text from resource contents
    private func extractResourceText(from result: ReadResource.Result) -> String {
        guard let firstContent = result.contents.first else { return "" }
        return firstContent.text ?? ""
    }

    // MARK: - Prompt Handler Tests

    func testPromptSessionStart() async throws {
        let params = GetPrompt.Parameters(name: "session_start", arguments: nil)
        let result = try await server.dispatchPromptGet(params)

        XCTAssertEqual(result.description, "TermQ Session Start")
        XCTAssertEqual(result.messages.count, 1)

        // Extract and verify content
        let text = extractPromptText(from: result.messages[0])
        XCTAssertTrue(text.contains("TermQ Session Start"))
        XCTAssertTrue(text.contains("Board Overview"))
    }

    func testPromptWorkflowGuide() async throws {
        let params = GetPrompt.Parameters(name: "workflow_guide", arguments: nil)
        let result = try await server.dispatchPromptGet(params)

        XCTAssertEqual(result.description, "TermQ Workflow Guide")
        XCTAssertEqual(result.messages.count, 1)

        let text = extractPromptText(from: result.messages[0])
        XCTAssertTrue(text.contains("SESSION START CHECKLIST"))
    }

    func testPromptTerminalSummary() async throws {
        let params = GetPrompt.Parameters(
            name: "terminal_summary",
            arguments: ["terminal": .string("Test Terminal 1")]
        )
        let result = try await server.dispatchPromptGet(params)

        XCTAssertTrue(result.description?.contains("Terminal Summary") ?? false)

        let text = extractPromptText(from: result.messages[0])
        XCTAssertTrue(text.contains("Terminal Summary"))
    }

    func testPromptTerminalSummaryNotFound() async throws {
        let params = GetPrompt.Parameters(
            name: "terminal_summary",
            arguments: ["terminal": .string("NonExistent")]
        )
        let result = try await server.dispatchPromptGet(params)

        let text = extractPromptText(from: result.messages[0])
        XCTAssertTrue(text.contains("Terminal not found"))
    }

    func testPromptUnknown() async throws {
        let params = GetPrompt.Parameters(name: "unknown_prompt", arguments: nil)

        do {
            _ = try await server.dispatchPromptGet(params)
            XCTFail("Should have thrown for unknown prompt")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Unknown prompt"))
        }
    }

    // Helper to extract text from prompt messages
    private func extractPromptText(from message: Prompt.Message) -> String {
        if case .text(let text) = message.content {
            return text
        }
        return ""
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
