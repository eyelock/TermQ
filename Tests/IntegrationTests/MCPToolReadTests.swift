import Foundation
import MCP
import TermQShared
import XCTest

@testable import MCPServerLib

/// Integration tests for MCP Server read-only tools.
///
/// These tests verify the MCP server tools work correctly using isolated test environments.
/// Tests are designed with TDD approach - some should fail initially to verify bugs.
///
/// Run with: `swift test --filter MCPToolReadTests`
final class MCPToolReadTests: XCTestCase {
    var env: TestEnvironment!
    var server: TermQMCPServer!

    override func setUpWithError() throws {
        // Create isolated test environment with comprehensive data
        env = try TestEnvironment.comprehensive()
        server = TermQMCPServer(dataDirectory: env.dataDirectory)
    }

    override func tearDownWithError() throws {
        env?.cleanup()
        env = nil
        server = nil
    }

    // MARK: - list Tests

    func testListReturnsAllTerminals() async throws {
        let result = try await server.handleList(nil)
        let terminals = try extractTerminalArray(from: result)
        // Comprehensive builder creates 5 active terminals + 1 deleted
        XCTAssertEqual(terminals.count, 5, "Should return 5 active terminals (excluding deleted)")
    }

    func testListExcludesDeletedTerminals() async throws {
        let result = try await server.handleList(nil)
        let terminals = try extractTerminalArray(from: result)

        // Verify deleted terminal is not in the list
        let names = terminals.compactMap { $0["name"] as? String }
        XCTAssertFalse(names.contains("Deleted Terminal"), "Deleted terminals should be excluded")
    }

    func testListWithColumnFilter() async throws {
        let args: [String: Value] = ["column": .string("In Progress")]
        let result = try await server.handleList(args)

        let terminals = try extractTerminalArray(from: result)
        // Comprehensive builder has 2 terminals in "In Progress"
        XCTAssertEqual(terminals.count, 2, "Should return 2 terminals in 'In Progress' column")
    }

    func testListWithInvalidColumn() async throws {
        let args: [String: Value] = ["column": .string("NonExistent Column")]
        let result = try await server.handleList(args)

        let terminals = try extractTerminalArray(from: result)
        XCTAssertEqual(terminals.count, 0, "Should return empty array for nonexistent column")
    }

    func testListColumnsOnly() async throws {
        let args: [String: Value] = ["columnsOnly": .bool(true)]
        let result = try await server.handleList(args)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json, _, _) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        // Should return columns, not terminals
        let data = Data(json.utf8)
        let columns = try JSONDecoder().decode(ColumnListEnvelope.self, from: data).items

        XCTAssertEqual(columns.count, 3, "Should return 3 default columns")
        XCTAssertEqual(columns[0].name, "To Do")
        XCTAssertEqual(columns[1].name, "In Progress")
        XCTAssertEqual(columns[2].name, "Done")
    }

    func testListColumnsIncludeDescriptions() async throws {
        let args: [String: Value] = ["columnsOnly": .bool(true)]
        let result = try await server.handleList(args)

        guard case .text(let json, _, _) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = Data(json.utf8)
        let columns = try JSONDecoder().decode(ColumnListEnvelope.self, from: data).items

        XCTAssertEqual(columns[0].description, "Tasks to start")
        XCTAssertEqual(columns[1].description, "Active work")
    }

    func testListColumnsIncludeTerminalCount() async throws {
        let args: [String: Value] = ["columnsOnly": .bool(true)]
        let result = try await server.handleList(args)

        guard case .text(let json, _, _) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = Data(json.utf8)
        let columns = try JSONDecoder().decode(ColumnListEnvelope.self, from: data).items

        // Verify terminal counts match what we set up
        // TestBoardBuilder.comprehensive: To Do=2, In Progress=2, Done=1
        XCTAssertEqual(columns[0].terminalCount, 2, "To Do should have 2 terminals")
        XCTAssertEqual(columns[1].terminalCount, 2, "In Progress should have 2 terminals")
        XCTAssertEqual(columns[2].terminalCount, 1, "Done should have 1 terminal")
    }

    // MARK: - find Tests

    func testFindBySmartQuery() async throws {
        let args: [String: Value] = ["query": .string("Fresh Active Project")]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        XCTAssertGreaterThan(terminals.count, 0, "Should find terminal by query")

        let names = terminals.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("Fresh Active Project"))
    }

    func testFindBySmartQueryMultiWord() async throws {
        // User's exact use case: searching normalized words
        let args: [String: Value] = ["query": .string("fresh active")]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        XCTAssertGreaterThan(terminals.count, 0, "Should find terminal by multi-word query")
    }

    func testFindBySmartQueryMatchesDescription() async throws {
        // Search for words in description, not title
        let args: [String: Value] = ["query": .string("Currently being worked")]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        XCTAssertGreaterThan(terminals.count, 0, "Should find terminal by description match")
    }

    func testFindBySmartQueryMatchesPath() async throws {
        let args: [String: Value] = ["query": .string("projects/active")]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        XCTAssertGreaterThan(terminals.count, 0, "Should find terminal by path match")
    }

    func testFindBySmartQueryMatchesTags() async throws {
        let args: [String: Value] = ["query": .string("test/repo")]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        // Should find terminal with project=test/repo tag
        XCTAssertGreaterThan(terminals.count, 0, "Should find terminal by tag value match")
    }

    func testFindByName() async throws {
        let args: [String: Value] = ["name": .string("Favourite Terminal")]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        XCTAssertEqual(terminals.count, 1)

        let name = terminals[0]["name"] as? String
        XCTAssertEqual(name, "Favourite Terminal")
    }

    func testFindByTag() async throws {
        let args: [String: Value] = ["tag": .string("staleness=fresh")]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        XCTAssertGreaterThan(terminals.count, 0, "Should find terminal with staleness=fresh tag")
    }

    func testFindByTagKeyOnly() async throws {
        // Find terminals that have the staleness tag with any value
        let args: [String: Value] = ["tag": .string("staleness")]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        // Should find terminals with staleness=fresh, staleness=stale, staleness=ageing
        XCTAssertGreaterThan(terminals.count, 1, "Should find multiple terminals with staleness tag")
    }

    func testFindByFavourites() async throws {
        let args: [String: Value] = ["favourites": .bool(true)]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        XCTAssertEqual(terminals.count, 1, "Should find exactly one favourite")

        let isFavourite = terminals[0]["isFavourite"] as? Bool
        XCTAssertTrue(isFavourite == true)
    }

    func testFindByBadge() async throws {
        let args: [String: Value] = ["badge": .string("important")]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        XCTAssertEqual(terminals.count, 1, "Should find terminal with 'important' badge")
    }

    func testFindWithCombinedFilters() async throws {
        let args: [String: Value] = [
            "column": .string("In Progress"),
            "tag": .string("staleness=fresh"),
        ]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        // "Fresh Active Project" is in "In Progress" with staleness=fresh
        XCTAssertEqual(terminals.count, 1)
    }

    func testFindNoResults() async throws {
        // Use a completely unique string that won't match anything
        let args: [String: Value] = ["query": .string("zzz-totally-nonexistent-99999")]
        let result = try await server.handleFind(args)

        let terminals = try extractTerminalArray(from: result)
        XCTAssertEqual(terminals.count, 0, "Should return empty array for no matches")
    }

    // MARK: - open Tests

    func testOpenByExactName() async throws {
        let args: [String: Value] = ["identifier": .string("Fresh Active Project")]
        let result = try await server.handleOpen(args)

        XCTAssertFalse(result.isError ?? false)

        let terminal = try extractTerminal(from: result)
        XCTAssertEqual(terminal["name"] as? String, "Fresh Active Project")
        XCTAssertEqual(terminal["path"] as? String, "/Users/test/projects/active")
    }

    func testOpenByUUID() async throws {
        // First create a terminal with a known ID
        let testId = UUID()
        env.cleanup()
        env = try TestEnvironment()
        try env.writeBoard(
            from: TestBoardBuilder()
                .addTerminal(id: testId, name: "UUID Test Terminal")
        )
        server = TermQMCPServer(dataDirectory: env.dataDirectory)

        let args: [String: Value] = ["identifier": .string(testId.uuidString)]
        let result = try await server.handleOpen(args)

        XCTAssertFalse(result.isError ?? false)

        let terminal = try extractTerminal(from: result)
        XCTAssertEqual(terminal["name"] as? String, "UUID Test Terminal")
    }

    func testOpenByPath() async throws {
        let args: [String: Value] = ["identifier": .string("/Users/test/projects/active")]
        let result = try await server.handleOpen(args)

        XCTAssertFalse(result.isError ?? false)

        let terminal = try extractTerminal(from: result)
        XCTAssertEqual(terminal["name"] as? String, "Fresh Active Project")
    }

    func testOpenByPartialMatch() async throws {
        let args: [String: Value] = ["identifier": .string("favourite")]
        let result = try await server.handleOpen(args)

        XCTAssertFalse(result.isError ?? false)

        let terminal = try extractTerminal(from: result)
        XCTAssertEqual(terminal["name"] as? String, "Favourite Terminal")
    }

    func testOpenNotFound() async throws {
        let args: [String: Value] = ["identifier": .string("nonexistent-terminal-xyz")]
        let result = try await server.handleOpen(args)

        XCTAssertTrue(result.isError ?? false)

        guard case .text(let message, _, _) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }
        XCTAssertTrue(message.contains("Terminal not found"))
    }

    func testOpenMissingIdentifier() async throws {
        let result = try await server.handleOpen(nil)

        XCTAssertTrue(result.isError ?? false)
    }

    // MARK: - pending Tests

    func testPendingReturnsAllWithSummary() async throws {
        let result = try await server.handlePending(nil)

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let json, _, _) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = Data(json.utf8)
        let output = try JSONDecoder().decode(PendingOutput.self, from: data)

        // Comprehensive builder creates 5 active terminals
        XCTAssertEqual(output.summary.total, 5)
        // 2 have llmNextAction
        XCTAssertEqual(output.summary.withNextAction, 2)
    }

    func testPendingActionsOnlyFilter() async throws {
        let args: [String: Value] = ["actionsOnly": .bool(true)]
        let result = try await server.handlePending(args)

        guard case .text(let json, _, _) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = Data(json.utf8)
        let output = try JSONDecoder().decode(PendingOutput.self, from: data)

        // Only terminals with llmNextAction
        XCTAssertEqual(output.summary.total, 2)
        // Verify all have next actions
        for terminal in output.terminals {
            XCTAssertFalse(terminal.llmNextAction.isEmpty, "All terminals should have llmNextAction")
        }
    }

    func testPendingSortOrder() async throws {
        let result = try await server.handlePending(nil)

        guard case .text(let json, _, _) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = Data(json.utf8)
        let output = try JSONDecoder().decode(PendingOutput.self, from: data)

        // First terminal should have llmNextAction (pending actions first)
        if !output.terminals.isEmpty {
            let first = output.terminals[0]
            XCTAssertFalse(first.llmNextAction.isEmpty, "First terminal should have pending action")
        }
    }

    func testPendingSummaryAccuracy() async throws {
        let result = try await server.handlePending(nil)

        guard case .text(let json, _, _) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = Data(json.utf8)
        let output = try JSONDecoder().decode(PendingOutput.self, from: data)

        // Verify summary counts match terminal data
        XCTAssertEqual(output.summary.total, output.terminals.count)
    }

    func testPendingStalenessValues() async throws {
        let result = try await server.handlePending(nil)

        guard case .text(let json, _, _) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let data = Data(json.utf8)
        let output = try JSONDecoder().decode(PendingOutput.self, from: data)

        // Should have at least one of each staleness type
        XCTAssertGreaterThan(output.summary.fresh, 0, "Should have fresh terminals")
        XCTAssertGreaterThan(output.summary.stale, 0, "Should have stale terminals")
    }

    // MARK: - context Tests

    func testContextReturnsGuide() async throws {
        let result = try await server.handleContext()

        XCTAssertFalse(result.isError ?? false)

        guard case .text(let content, _, _) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        XCTAssertTrue(content.contains("TermQ MCP Server"))
        XCTAssertTrue(content.contains("SESSION START CHECKLIST"))
    }

    func testContextContainsTagSchema() async throws {
        let result = try await server.handleContext()

        guard case .text(let content, _, _) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        // Context should document the tag schema
        XCTAssertTrue(content.contains("staleness"), "Should document staleness tag")
    }

    // MARK: - get Tests

    func testGetByUUID() async throws {
        // Create environment with known UUID
        let testId = UUID()
        env.cleanup()
        env = try TestEnvironment()
        try env.writeBoard(
            from: TestBoardBuilder()
                .addTerminal(
                    id: testId,
                    name: "Get Test Terminal",
                    llmPrompt: "Test prompt content"
                )
        )
        server = TermQMCPServer(dataDirectory: env.dataDirectory)

        let args: [String: Value] = ["id": .string(testId.uuidString)]
        let result = try await server.handleGet(args)

        XCTAssertFalse(result.isError ?? false)

        let terminal = try extractTerminal(from: result)
        XCTAssertEqual(terminal["name"] as? String, "Get Test Terminal")
        XCTAssertEqual(terminal["llmPrompt"] as? String, "Test prompt content")
    }

    func testGetReturnsFullTerminalDetails() async throws {
        // Create terminal with all fields populated
        let testId = UUID()
        env.cleanup()
        env = try TestEnvironment()
        try env.writeBoard(
            from: TestBoardBuilder()
                .addTerminal(
                    id: testId,
                    name: "Full Details Terminal",
                    description: "Test description",
                    path: "/test/path",
                    tags: ["key1": "value1", "key2": "value2"],
                    isFavourite: true,
                    badge: "urgent",
                    llmPrompt: "Prompt text",
                    llmNextAction: "Next action text"
                )
        )
        server = TermQMCPServer(dataDirectory: env.dataDirectory)

        let args: [String: Value] = ["id": .string(testId.uuidString)]
        let result = try await server.handleGet(args)

        let terminal = try extractTerminal(from: result)

        // Verify all fields are present
        XCTAssertEqual(terminal["name"] as? String, "Full Details Terminal")
        XCTAssertEqual(terminal["description"] as? String, "Test description")
        XCTAssertEqual(terminal["path"] as? String, "/test/path")
        XCTAssertEqual(terminal["isFavourite"] as? Bool, true)
        XCTAssertEqual(terminal["llmPrompt"] as? String, "Prompt text")
        XCTAssertEqual(terminal["llmNextAction"] as? String, "Next action text")
    }

    func testGetNotFound() async throws {
        let args: [String: Value] = ["id": .string(UUID().uuidString)]
        let result = try await server.handleGet(args)

        XCTAssertTrue(result.isError ?? false)
    }

    func testGetMissingId() async throws {
        let result = try await server.handleGet(nil)

        XCTAssertTrue(result.isError ?? false)
    }

    func testGetInvalidUUID() async throws {
        let args: [String: Value] = ["id": .string("not-a-uuid")]
        let result = try await server.handleGet(args)

        XCTAssertTrue(result.isError ?? false)
    }

    // MARK: - Edge Case Tests

    func testHandlerWithEmptyBoard() async throws {
        // Create empty board
        env.cleanup()
        env = try TestEnvironment.empty()
        server = TermQMCPServer(dataDirectory: env.dataDirectory)

        let result = try await server.handleList(nil)
        let terminals = try extractTerminalArray(from: result)

        XCTAssertEqual(terminals.count, 0, "Empty board should return no terminals")
    }

    func testHandlerWithNoBoardFile() async throws {
        // Create environment without board file
        env.cleanup()
        env = try TestEnvironment.noBoard()
        server = TermQMCPServer(dataDirectory: env.dataDirectory)

        // MCP handlers return error results rather than throwing
        let result = try await server.handleList(nil)
        XCTAssertTrue(result.isError ?? false, "Should return error for missing board")
    }
}

// MARK: - Helper Functions

/// Extract terminal array from tool result.
///
/// `list` and `find` now emit an envelope `{ items: [...], nextCursor?: string }`
/// per MCP's requirement that `structuredContent` be a JSON object — so this
/// helper unwraps `items` rather than expecting a bare top-level array.
func extractTerminalArray(from result: CallTool.Result) throws -> [[String: Any]] {
    guard case .text(let json, _, _) = result.content[0] else {
        throw TestHelperError.noTextContent
    }

    guard let data = json.data(using: .utf8),
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let items = obj["items"] as? [[String: Any]]
    else {
        throw TestHelperError.invalidJSON
    }

    return items
}

/// Extract single terminal from tool result
func extractTerminal(from result: CallTool.Result) throws -> [String: Any] {
    guard case .text(let json, _, _) = result.content[0] else {
        throw TestHelperError.noTextContent
    }

    guard let data = json.data(using: .utf8),
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        throw TestHelperError.invalidJSON
    }

    return obj
}

enum TestHelperError: Error {
    case noTextContent
    case invalidJSON
}

/// Local mirror of the columns-only envelope emitted by `list { columnsOnly: true }`.
struct ColumnListEnvelope: Codable {
    let items: [ColumnOutput]
}
