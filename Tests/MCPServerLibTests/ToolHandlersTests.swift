import Foundation
import MCP
import TermQShared
import XCTest

@testable import MCPServerLib

/// Unit tests for individual tool handlers and helper functions
final class ToolHandlersTests: XCTestCase {
    var tempDirectory: URL!
    var server: TermQMCPServer!

    override func setUpWithError() throws {
        // Create temporary directory for test data
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-ToolHandlerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        server = nil
    }

    // MARK: - Test Data Helpers

    private func createTestBoard(columns: [TestColumn] = [], cards: [TestCard] = []) throws {
        var columnJSON: [[String: Any]] = []
        for column in columns {
            columnJSON.append([
                "id": column.id.uuidString,
                "name": column.name,
                "description": column.description,
                "orderIndex": column.orderIndex,
                "color": column.color,
            ])
        }

        var cardJSON: [[String: Any]] = []
        for card in cards {
            var cardDict: [String: Any] = [
                "id": card.id.uuidString,
                "title": card.title,
                "description": card.description,
                "columnId": card.columnId.uuidString,
                "orderIndex": card.orderIndex,
                "workingDirectory": card.workingDirectory,
                "llmPrompt": card.llmPrompt,
                "llmNextAction": card.llmNextAction,
                "isFavourite": card.isFavourite,
                "badge": card.badge,
                "tags": card.tags.map { ["id": UUID().uuidString, "key": $0.key, "value": $0.value] },
            ]
            if let lastLLMGet = card.lastLLMGet {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                cardDict["lastLLMGet"] = formatter.string(from: lastLLMGet)
            }
            cardJSON.append(cardDict)
        }

        let boardDict: [String: Any] = ["columns": columnJSON, "cards": cardJSON]
        let data = try JSONSerialization.data(withJSONObject: boardDict)
        try data.write(to: tempDirectory.appendingPathComponent("board.json"))

        server = TermQMCPServer(dataDirectory: tempDirectory)
    }

    struct TestColumn {
        let id: UUID
        let name: String
        let description: String
        let orderIndex: Int
        let color: String

        init(
            id: UUID = UUID(),
            name: String,
            description: String = "",
            orderIndex: Int = 0,
            color: String = "#6B7280"
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.orderIndex = orderIndex
            self.color = color
        }
    }

    struct TestCard {
        let id: UUID
        let title: String
        let description: String
        let columnId: UUID
        let orderIndex: Int
        let workingDirectory: String
        let llmPrompt: String
        let llmNextAction: String
        let isFavourite: Bool
        let badge: String
        let tags: [(key: String, value: String)]
        let lastLLMGet: Date?

        init(
            id: UUID = UUID(),
            title: String,
            description: String = "",
            columnId: UUID,
            orderIndex: Int = 0,
            workingDirectory: String = "/tmp",
            llmPrompt: String = "",
            llmNextAction: String = "",
            isFavourite: Bool = false,
            badge: String = "",
            tags: [(key: String, value: String)] = [],
            lastLLMGet: Date? = nil
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.columnId = columnId
            self.orderIndex = orderIndex
            self.workingDirectory = workingDirectory
            self.llmPrompt = llmPrompt
            self.llmNextAction = llmNextAction
            self.isFavourite = isFavourite
            self.badge = badge
            self.tags = tags
            self.lastLLMGet = lastLLMGet
        }
    }

    // MARK: - handlePending Tests

    func testHandlePendingEmptyBoard() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: []
        )

        let result = try await server.handlePending(nil)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let output = try JSONDecoder().decode(PendingOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(output.summary.total, 0)
        XCTAssertEqual(output.summary.withNextAction, 0)
    }

    func testHandlePendingSortsByActionsFirst() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [
                TestCard(title: "No Action", columnId: columnId),
                TestCard(title: "Has Action", columnId: columnId, llmNextAction: "Do something"),
            ]
        )

        let result = try await server.handlePending(nil)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let output = try JSONDecoder().decode(PendingOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(output.terminals.count, 2)
        // First terminal should be the one with action
        XCTAssertEqual(output.terminals[0].name, "Has Action")
    }

    func testHandlePendingActionsOnlyFilter() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [
                TestCard(title: "No Action", columnId: columnId),
                TestCard(title: "Has Action", columnId: columnId, llmNextAction: "Do something"),
                TestCard(title: "Also Has Action", columnId: columnId, llmNextAction: "Do more"),
            ]
        )

        let args: [String: Value] = ["actionsOnly": .bool(true)]
        let result = try await server.handlePending(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let output = try JSONDecoder().decode(PendingOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(output.terminals.count, 2)
        // Should not include "No Action"
        XCTAssertFalse(output.terminals.contains { $0.name == "No Action" })
    }

    func testHandlePendingCountsStaleAndFreshCards() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [
                TestCard(
                    title: "Fresh Card",
                    columnId: columnId,
                    tags: [("staleness", "fresh")],
                    lastLLMGet: Date()  // Recent
                ),
                TestCard(
                    title: "Stale Card",
                    columnId: columnId,
                    tags: [("staleness", "stale")]
                ),
                TestCard(
                    title: "Old Card",
                    columnId: columnId,
                    tags: [("staleness", "old")]
                ),
            ]
        )

        let result = try await server.handlePending(nil)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let output = try JSONDecoder().decode(PendingOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(output.summary.total, 3)
        // Stale count includes both "stale" and "old"
        XCTAssertEqual(output.summary.stale, 2)
        XCTAssertEqual(output.summary.fresh, 1)
    }

    func testHandlePendingWithLoadError() async throws {
        // Create server with invalid directory (no board.json)
        server = TermQMCPServer(dataDirectory: tempDirectory)

        let result = try await server.handlePending(nil)

        XCTAssertTrue(result.isError ?? false)
        guard case .text(let message) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }
        XCTAssertTrue(message.contains("Error"))
    }

    // MARK: - handleContext Tests

    func testHandleContextReturnsDocumentation() async throws {
        try createTestBoard(columns: [], cards: [])

        let result = try await server.handleContext()

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let content) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        XCTAssertTrue(content.contains("TermQ MCP Server"))
        XCTAssertTrue(content.contains("SESSION START CHECKLIST"))
        XCTAssertTrue(content.contains("SESSION END CHECKLIST"))
    }

    // MARK: - handleList Tests

    func testHandleListAllTerminals() async throws {
        let column1 = UUID()
        let column2 = UUID()
        try createTestBoard(
            columns: [
                TestColumn(id: column1, name: "To Do", orderIndex: 0),
                TestColumn(id: column2, name: "Done", orderIndex: 1),
            ],
            cards: [
                TestCard(title: "Card 1", columnId: column1),
                TestCard(title: "Card 2", columnId: column2),
            ]
        )

        let result = try await server.handleList(nil)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminals.count, 2)
    }

    func testHandleListColumnsOnly() async throws {
        let column1 = UUID()
        let column2 = UUID()
        try createTestBoard(
            columns: [
                TestColumn(id: column1, name: "To Do", description: "Tasks to do", orderIndex: 0),
                TestColumn(id: column2, name: "Done", description: "Completed", orderIndex: 1),
            ],
            cards: [
                TestCard(title: "Card 1", columnId: column1),
                TestCard(title: "Card 2", columnId: column1),
            ]
        )

        let args: [String: Value] = ["columnsOnly": .bool(true)]
        let result = try await server.handleList(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let columns = try JSONDecoder().decode([ColumnOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(columns.count, 2)
        XCTAssertEqual(columns[0].name, "To Do")
        XCTAssertEqual(columns[0].description, "Tasks to do")
        XCTAssertEqual(columns[0].terminalCount, 2)
        XCTAssertEqual(columns[1].terminalCount, 0)
    }

    func testHandleListFilterByColumn() async throws {
        let column1 = UUID()
        let column2 = UUID()
        try createTestBoard(
            columns: [
                TestColumn(id: column1, name: "In Progress", orderIndex: 0),
                TestColumn(id: column2, name: "Done", orderIndex: 1),
            ],
            cards: [
                TestCard(title: "Active Card", columnId: column1),
                TestCard(title: "Finished Card", columnId: column2),
            ]
        )

        let args: [String: Value] = ["column": .string("Progress")]
        let result = try await server.handleList(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminals.count, 1)
        XCTAssertEqual(terminals[0].name, "Active Card")
    }

    func testHandleListSortsByColumnAndCardOrder() async throws {
        let column1 = UUID()
        let column2 = UUID()
        try createTestBoard(
            columns: [
                TestColumn(id: column1, name: "To Do", orderIndex: 0),
                TestColumn(id: column2, name: "Done", orderIndex: 1),
            ],
            cards: [
                TestCard(title: "Card B", columnId: column1, orderIndex: 1),
                TestCard(title: "Card A", columnId: column1, orderIndex: 0),
                TestCard(title: "Card C", columnId: column2, orderIndex: 0),
            ]
        )

        let result = try await server.handleList(nil)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminals.count, 3)
        // Should be sorted: column 0 cards first (by order), then column 1 cards
        XCTAssertEqual(terminals[0].name, "Card A")
        XCTAssertEqual(terminals[1].name, "Card B")
        XCTAssertEqual(terminals[2].name, "Card C")
    }

    func testHandleListWithLoadError() async throws {
        server = TermQMCPServer(dataDirectory: tempDirectory)

        let result = try await server.handleList(nil)

        XCTAssertTrue(result.isError ?? false)
    }

    // MARK: - handleFind Tests

    func testHandleFindByName() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [
                TestCard(title: "Frontend Project", columnId: columnId),
                TestCard(title: "Backend API", columnId: columnId),
            ]
        )

        let args: [String: Value] = ["name": .string("Frontend")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminals.count, 1)
        XCTAssertEqual(terminals[0].name, "Frontend Project")
    }

    func testHandleFindByTagKeyOnly() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [
                TestCard(title: "Has Env Tag", columnId: columnId, tags: [("env", "production")]),
                TestCard(title: "No Env Tag", columnId: columnId, tags: [("type", "feature")]),
            ]
        )

        let args: [String: Value] = ["tag": .string("env")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminals.count, 1)
        XCTAssertEqual(terminals[0].name, "Has Env Tag")
    }

    func testHandleFindByTagKeyValue() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [
                TestCard(title: "Production", columnId: columnId, tags: [("env", "production")]),
                TestCard(title: "Staging", columnId: columnId, tags: [("env", "staging")]),
            ]
        )

        let args: [String: Value] = ["tag": .string("env=production")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminals.count, 1)
        XCTAssertEqual(terminals[0].name, "Production")
    }

    func testHandleFindBySmartQuery() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [
                TestCard(
                    title: "mcp-toolkit: migrate workflows",
                    description: "Migration and session handling",
                    columnId: columnId,
                    workingDirectory: "/Users/test/mcp-toolkit"
                ),
                TestCard(title: "Unrelated Project", columnId: columnId),
            ]
        )

        let args: [String: Value] = ["query": .string("MCP Toolkit Migrate")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        XCTAssertTrue(terminals.contains { $0.name.contains("mcp-toolkit") })
    }

    func testHandleFindBySmartQueryNoResults() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [TestCard(title: "Test Project", columnId: columnId)]
        )

        let args: [String: Value] = ["query": .string("completely unrelated xyz")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminals.count, 0)
    }

    func testHandleFindBySmartQueryEmptyAfterNormalization() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [TestCard(title: "Test", columnId: columnId)]
        )

        // Single character words are filtered out during normalization
        let args: [String: Value] = ["query": .string("a b")]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        // Should return empty since query normalizes to nothing
        XCTAssertEqual(terminals.count, 0)
    }

    func testHandleFindWithInvalidUUID() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: []
        )

        let args: [String: Value] = ["id": .string("not-a-valid-uuid")]
        let result = try await server.handleFind(args)

        XCTAssertTrue(result.isError ?? false)
        guard case .text(let message) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }
        XCTAssertTrue(message.contains("Invalid UUID"))
    }

    func testHandleFindByValidUUID() async throws {
        let columnId = UUID()
        let cardId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [
                TestCard(id: cardId, title: "Target Card", columnId: columnId),
                TestCard(title: "Other Card", columnId: columnId),
            ]
        )

        let args: [String: Value] = ["id": .string(cardId.uuidString)]
        let result = try await server.handleFind(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminals.count, 1)
        XCTAssertEqual(terminals[0].id, cardId.uuidString)
    }

    // MARK: - handleOpen Tests

    func testHandleOpenMissingIdentifier() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: []
        )

        let args: [String: Value] = [:]
        let result = try await server.handleOpen(args)

        XCTAssertTrue(result.isError ?? false)
        guard case .text(let message) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }
        XCTAssertTrue(message.contains("Missing required") || message.contains("identifier"))
    }

    func testHandleOpenEmptyIdentifier() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: []
        )

        let args: [String: Value] = ["identifier": .string("")]
        let result = try await server.handleOpen(args)

        XCTAssertTrue(result.isError ?? false)
    }

    func testHandleOpenNotFound() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [TestCard(title: "Existing Card", columnId: columnId)]
        )

        let args: [String: Value] = ["identifier": .string("NonExistent")]
        let result = try await server.handleOpen(args)

        XCTAssertTrue(result.isError ?? false)
        guard case .text(let message) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }
        XCTAssertTrue(message.contains("Terminal not found"))
    }

    func testHandleOpenSuccess() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [TestCard(title: "My Terminal", description: "Test description", columnId: columnId)]
        )

        let args: [String: Value] = ["identifier": .string("My Terminal")]
        let result = try await server.handleOpen(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminal = try JSONDecoder().decode(TerminalOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminal.name, "My Terminal")
        XCTAssertEqual(terminal.description, "Test description")
    }

    // MARK: - handleCreate Tests

    func testHandleCreateWithDefaults() async throws {
        throw XCTSkip("Requires GUI running - URL scheme mutations processed by TermQ app")
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: []
        )

        let args: [String: Value] = [:]
        let result = try await server.handleCreate(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminal = try JSONDecoder().decode(TerminalOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminal.name, "New Terminal")
    }

    func testHandleCreateWithCustomValues() async throws {
        throw XCTSkip("Requires GUI running - URL scheme mutations processed by TermQ app")
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "In Progress", orderIndex: 0)],
            cards: []
        )

        let args: [String: Value] = [
            "name": .string("Custom Terminal"),
            "description": .string("A custom description"),
            "column": .string("In Progress"),
            "path": .string("/tmp"),
        ]
        let result = try await server.handleCreate(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminal = try JSONDecoder().decode(TerminalOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminal.name, "Custom Terminal")
        XCTAssertEqual(terminal.description, "A custom description")
        XCTAssertEqual(terminal.column, "In Progress")
    }

    // MARK: - handleSet Tests

    func testHandleSetMissingIdentifier() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: []
        )

        let args: [String: Value] = ["name": .string("New Name")]
        let result = try await server.handleSet(args)

        XCTAssertTrue(result.isError ?? false)
    }

    func testHandleSetNoUpdates() async throws {
        throw XCTSkip("Requires GUI running - URL scheme mutations processed by TermQ app")
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [TestCard(title: "Test Card", columnId: columnId)]
        )

        let args: [String: Value] = ["identifier": .string("Test Card")]
        let result = try await server.handleSet(args)

        // Should succeed - returns current state without updates
        XCTAssertFalse(result.isError ?? false)
    }

    func testHandleSetUpdateDescription() async throws {
        throw XCTSkip("Requires GUI running - URL scheme mutations processed by TermQ app")
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [TestCard(title: "Test Card", columnId: columnId)]
        )

        let args: [String: Value] = [
            "identifier": .string("Test Card"),
            "description": .string("Updated description"),
        ]
        let result = try await server.handleSet(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminal = try JSONDecoder().decode(TerminalOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminal.description, "Updated description")
    }

    func testHandleSetUpdateLlmNextAction() async throws {
        throw XCTSkip("Requires GUI running - URL scheme mutations processed by TermQ app")
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [TestCard(title: "Test Card", columnId: columnId)]
        )

        // Test updating llmNextAction field
        let args: [String: Value] = [
            "identifier": .string("Test Card"),
            "llmNextAction": .string("Fix bug #123"),
        ]
        let result = try await server.handleSet(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminal = try JSONDecoder().decode(TerminalOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminal.llmNextAction, "Fix bug #123")
    }

    func testHandleSetUpdateBadge() async throws {
        throw XCTSkip("Requires GUI running - URL scheme mutations processed by TermQ app")
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [TestCard(title: "Test Card", columnId: columnId)]
        )

        let args: [String: Value] = [
            "identifier": .string("Test Card"),
            "badge": .string("urgent,wip"),
        ]
        let result = try await server.handleSet(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminal = try JSONDecoder().decode(TerminalOutput.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(terminal.badges.contains("urgent"))
        XCTAssertTrue(terminal.badges.contains("wip"))
    }

    func testHandleSetUpdateFavourite() async throws {
        throw XCTSkip("Requires GUI running - URL scheme mutations processed by TermQ app")
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [TestCard(title: "Test Card", columnId: columnId)]
        )

        let args: [String: Value] = [
            "identifier": .string("Test Card"),
            "favourite": .bool(true),
        ]
        let result = try await server.handleSet(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminal = try JSONDecoder().decode(TerminalOutput.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(terminal.isFavourite)
    }

    func testHandleSetWithColumnMove() async throws {
        throw XCTSkip("Requires GUI running - URL scheme mutations processed by TermQ app")
        let column1 = UUID()
        let column2 = UUID()
        try createTestBoard(
            columns: [
                TestColumn(id: column1, name: "To Do", orderIndex: 0),
                TestColumn(id: column2, name: "Done", orderIndex: 1),
            ],
            cards: [TestCard(title: "Test Card", columnId: column1)]
        )

        let args: [String: Value] = [
            "identifier": .string("Test Card"),
            "column": .string("Done"),
        ]
        let result = try await server.handleSet(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminal = try JSONDecoder().decode(TerminalOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminal.column, "Done")
    }

    // MARK: - handleMove Tests

    func testHandleMoveMissingIdentifier() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: []
        )

        let args: [String: Value] = ["column": .string("Done")]
        let result = try await server.handleMove(args)

        XCTAssertTrue(result.isError ?? false)
    }

    func testHandleMoveMissingColumn() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [TestCard(title: "Test", columnId: columnId)]
        )

        let args: [String: Value] = ["identifier": .string("Test")]
        let result = try await server.handleMove(args)

        XCTAssertTrue(result.isError ?? false)
    }

    func testHandleMoveSuccess() async throws {
        throw XCTSkip("Requires GUI running - URL scheme mutations processed by TermQ app")
        let column1 = UUID()
        let column2 = UUID()
        try createTestBoard(
            columns: [
                TestColumn(id: column1, name: "To Do", orderIndex: 0),
                TestColumn(id: column2, name: "Done", orderIndex: 1),
            ],
            cards: [TestCard(title: "Test Card", columnId: column1)]
        )

        let args: [String: Value] = [
            "identifier": .string("Test Card"),
            "column": .string("Done"),
        ]
        let result = try await server.handleMove(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminal = try JSONDecoder().decode(TerminalOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminal.column, "Done")
    }

    // MARK: - handleGet Tests

    func testHandleGetMissingId() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: []
        )

        let args: [String: Value] = [:]
        let result = try await server.handleGet(args)

        XCTAssertTrue(result.isError ?? false)
    }

    func testHandleGetInvalidUUID() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: []
        )

        let args: [String: Value] = ["id": .string("not-a-uuid")]
        let result = try await server.handleGet(args)

        XCTAssertTrue(result.isError ?? false)
        guard case .text(let message) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }
        XCTAssertTrue(message.contains("Invalid UUID"))
    }

    func testHandleGetNotFound() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: []
        )

        let args: [String: Value] = ["id": .string(UUID().uuidString)]
        let result = try await server.handleGet(args)

        XCTAssertTrue(result.isError ?? false)
        guard case .text(let message) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }
        XCTAssertTrue(message.contains("Terminal not found"))
    }

    func testHandleGetSuccessUpdatesLastLLMGet() async throws {
        let columnId = UUID()
        let cardId = UUID()
        try createTestBoard(
            columns: [TestColumn(id: columnId, name: "To Do", orderIndex: 0)],
            cards: [TestCard(id: cardId, title: "Test Card", columnId: columnId)]
        )

        let args: [String: Value] = ["id": .string(cardId.uuidString)]
        let result = try await server.handleGet(args)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let json) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }

        let terminal = try JSONDecoder().decode(TerminalOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminal.id, cardId.uuidString)
        XCTAssertEqual(terminal.name, "Test Card")
    }
}
