import Foundation
import XCTest

@testable import TermQShared

final class SharedModelsTests: XCTestCase {

    // MARK: - Tag Tests

    func testTagInitialization() {
        let tag = Tag(key: "project", value: "termq")

        XCTAssertEqual(tag.key, "project")
        XCTAssertEqual(tag.value, "termq")
    }

    func testTagCodableRoundTrip() throws {
        let original = Tag(key: "env", value: "production")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Tag.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.key, original.key)
        XCTAssertEqual(decoded.value, original.value)
    }

    // MARK: - Column Tests

    func testColumnInitialization() {
        let column = Column(name: "To Do", orderIndex: 0)

        XCTAssertEqual(column.name, "To Do")
        XCTAssertEqual(column.orderIndex, 0)
        XCTAssertEqual(column.description, "")
        XCTAssertEqual(column.color, "#6B7280")
    }

    func testColumnCustomValues() {
        let column = Column(
            name: "In Progress",
            description: "Active work",
            orderIndex: 1,
            color: "#3B82F6"
        )

        XCTAssertEqual(column.name, "In Progress")
        XCTAssertEqual(column.description, "Active work")
        XCTAssertEqual(column.orderIndex, 1)
        XCTAssertEqual(column.color, "#3B82F6")
    }

    func testColumnBackwardsCompatibility() throws {
        // Minimal JSON without optional fields
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "name": "Test Column"
            }
            """

        let decoded = try JSONDecoder().decode(Column.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(decoded.name, "Test Column")
        XCTAssertEqual(decoded.description, "")
        XCTAssertEqual(decoded.orderIndex, 0)
        XCTAssertEqual(decoded.color, "#6B7280")
    }

    // MARK: - Card Tests

    func testCardBackwardsCompatibility() throws {
        // Minimal JSON without optional fields
        let columnId = UUID()
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Test Card",
                "columnId": "\(columnId.uuidString)"
            }
            """

        let decoded = try JSONDecoder().decode(Card.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(decoded.title, "Test Card")
        XCTAssertEqual(decoded.columnId, columnId)
        XCTAssertEqual(decoded.description, "")
        XCTAssertTrue(decoded.tags.isEmpty)
        XCTAssertEqual(decoded.orderIndex, 0)
        XCTAssertEqual(decoded.workingDirectory, "")
        XCTAssertFalse(decoded.isFavourite)
        XCTAssertEqual(decoded.badge, "")
        XCTAssertEqual(decoded.llmPrompt, "")
        XCTAssertEqual(decoded.llmNextAction, "")
        XCTAssertFalse(decoded.allowAutorun)
        XCTAssertNil(decoded.deletedAt)
    }

    func testCardBadgesParsing() throws {
        let columnId = UUID()
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Test",
                "columnId": "\(columnId.uuidString)",
                "badge": "urgent, important, high-priority"
            }
            """

        let decoded = try JSONDecoder().decode(Card.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(decoded.badges.count, 3)
        XCTAssertTrue(decoded.badges.contains("urgent"))
        XCTAssertTrue(decoded.badges.contains("important"))
        XCTAssertTrue(decoded.badges.contains("high-priority"))
    }

    func testCardTagsDictionary() throws {
        let columnId = UUID()
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Test",
                "columnId": "\(columnId.uuidString)",
                "tags": [
                    {"id": "\(UUID().uuidString)", "key": "project", "value": "termq"},
                    {"id": "\(UUID().uuidString)", "key": "env", "value": "dev"}
                ]
            }
            """

        let decoded = try JSONDecoder().decode(Card.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(decoded.tagsDictionary["project"], "termq")
        XCTAssertEqual(decoded.tagsDictionary["env"], "dev")
    }

    func testCardStalenessFromTags() throws {
        let columnId = UUID()
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Test",
                "columnId": "\(columnId.uuidString)",
                "tags": [
                    {"id": "\(UUID().uuidString)", "key": "staleness", "value": "stale"}
                ]
            }
            """

        let decoded = try JSONDecoder().decode(Card.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(decoded.staleness, "stale")
        XCTAssertEqual(decoded.stalenessRank, 3)
    }

    func testCardIsDeleted() throws {
        let columnId = UUID()
        let deletedJson = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Deleted Card",
                "columnId": "\(columnId.uuidString)",
                "deletedAt": "2025-01-01T00:00:00Z"
            }
            """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let deleted = try decoder.decode(Card.self, from: deletedJson.data(using: .utf8)!)

        XCTAssertTrue(deleted.isDeleted)
    }

    // MARK: - Board Tests

    func testBoardActiveCards() throws {
        let columnId = UUID()
        let json = """
            {
                "columns": [
                    {"id": "\(columnId.uuidString)", "name": "Test", "orderIndex": 0}
                ],
                "cards": [
                    {"id": "\(UUID().uuidString)", "title": "Active", "columnId": "\(columnId.uuidString)"},
                    {"id": "\(UUID().uuidString)", "title": "Deleted", "columnId": "\(columnId.uuidString)", "deletedAt": "2025-01-01T00:00:00Z"}
                ]
            }
            """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let board = try decoder.decode(Board.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(board.cards.count, 2)
        XCTAssertEqual(board.activeCards.count, 1)
        XCTAssertEqual(board.activeCards[0].title, "Active")
    }

    func testBoardFindTerminalByUUID() throws {
        let columnId = UUID()
        let cardId = UUID()
        let json = """
            {
                "columns": [
                    {"id": "\(columnId.uuidString)", "name": "Test", "orderIndex": 0}
                ],
                "cards": [
                    {"id": "\(cardId.uuidString)", "title": "Find Me", "columnId": "\(columnId.uuidString)"}
                ]
            }
            """

        let board = try JSONDecoder().decode(Board.self, from: json.data(using: .utf8)!)

        let found = board.findTerminal(identifier: cardId.uuidString)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.title, "Find Me")
    }

    func testBoardFindTerminalByName() throws {
        let columnId = UUID()
        let json = """
            {
                "columns": [
                    {"id": "\(columnId.uuidString)", "name": "Test", "orderIndex": 0}
                ],
                "cards": [
                    {"id": "\(UUID().uuidString)", "title": "My Terminal", "columnId": "\(columnId.uuidString)"}
                ]
            }
            """

        let board = try JSONDecoder().decode(Board.self, from: json.data(using: .utf8)!)

        // Exact match (case-insensitive)
        XCTAssertNotNil(board.findTerminal(identifier: "my terminal"))

        // Partial match
        XCTAssertNotNil(board.findTerminal(identifier: "Terminal"))
    }

    func testBoardColumnName() throws {
        let columnId = UUID()
        let json = """
            {
                "columns": [
                    {"id": "\(columnId.uuidString)", "name": "In Progress", "orderIndex": 0}
                ],
                "cards": []
            }
            """

        let board = try JSONDecoder().decode(Board.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(board.columnName(for: columnId), "In Progress")
        XCTAssertEqual(board.columnName(for: UUID()), "Unknown")
    }

    // MARK: - Output Types Tests

    func testTerminalOutputFromCard() throws {
        let columnId = UUID()
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Test Terminal",
                "description": "A test terminal",
                "columnId": "\(columnId.uuidString)",
                "workingDirectory": "/Users/test",
                "badge": "prod,main",
                "isFavourite": true,
                "llmPrompt": "Node.js project",
                "llmNextAction": "Fix bug",
                "tags": [
                    {"id": "\(UUID().uuidString)", "key": "project", "value": "test"}
                ]
            }
            """

        let card = try JSONDecoder().decode(Card.self, from: json.data(using: .utf8)!)
        let output = TerminalOutput(from: card, columnName: "In Progress")

        XCTAssertEqual(output.name, "Test Terminal")
        XCTAssertEqual(output.description, "A test terminal")
        XCTAssertEqual(output.column, "In Progress")
        XCTAssertEqual(output.path, "/Users/test")
        XCTAssertEqual(Set(output.badges), Set(["prod", "main"]))
        XCTAssertTrue(output.isFavourite)
        XCTAssertEqual(output.llmPrompt, "Node.js project")
        XCTAssertEqual(output.llmNextAction, "Fix bug")
        XCTAssertEqual(output.tags["project"], "test")
    }

    func testJSONHelperEncode() throws {
        let output = ErrorOutput(error: "Test error", code: 1)
        let json = try JSONHelper.encode(output)

        XCTAssertTrue(json.contains("Test error"))
        XCTAssertTrue(json.contains("1"))
    }

    // MARK: - TermQError Tests

    func testTermQErrorBoardNotFound() {
        let error = TermQError.boardNotFound(path: "/Users/test/.termq/board.json")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("/Users/test/.termq/board.json"))
        XCTAssertTrue(error.errorDescription!.contains("Board file not found"))
    }

    func testTermQErrorColumnNotFound() {
        let error = TermQError.columnNotFound(name: "Done")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Done"))
        XCTAssertTrue(error.errorDescription!.contains("Column not found"))
    }

    func testTermQErrorTerminalNotFound() {
        let error = TermQError.terminalNotFound(identifier: "my-terminal")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("my-terminal"))
        XCTAssertTrue(error.errorDescription!.contains("Terminal not found"))
    }

    // MARK: - ColumnOutput Tests

    func testColumnOutputFromColumn() {
        let column = Column(name: "In Progress", description: "Active work", orderIndex: 1, color: "#3B82F6")
        let output = ColumnOutput(from: column, terminalCount: 5)

        XCTAssertEqual(output.name, "In Progress")
        XCTAssertEqual(output.description, "Active work")
        XCTAssertEqual(output.color, "#3B82F6")
        XCTAssertEqual(output.terminalCount, 5)
    }

    // MARK: - PendingOutput Tests

    func testPendingOutputEncoding() throws {
        // Create a card for testing
        let columnId = UUID()
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Test Terminal",
                "columnId": "\(columnId.uuidString)",
                "workingDirectory": "/test",
                "llmNextAction": "Fix bug",
                "llmPrompt": "Node.js project",
                "tags": [
                    {"id": "\(UUID().uuidString)", "key": "project", "value": "test"}
                ]
            }
            """
        let card = try JSONDecoder().decode(Card.self, from: json.data(using: .utf8)!)
        let terminal = PendingTerminalOutput(from: card, columnName: "In Progress", staleness: "fresh")

        let summary = PendingSummary(total: 1, withNextAction: 1, stale: 0, fresh: 1)
        let output = PendingOutput(terminals: [terminal], summary: summary)

        let encodedJson = try JSONHelper.encode(output)
        XCTAssertTrue(encodedJson.contains("Test Terminal"))
        XCTAssertTrue(encodedJson.contains("Fix bug"))
    }

    // MARK: - PendingSummary Tests

    func testPendingSummaryInitialization() {
        let summary = PendingSummary(total: 10, withNextAction: 3, stale: 2, fresh: 5)

        XCTAssertEqual(summary.total, 10)
        XCTAssertEqual(summary.withNextAction, 3)
        XCTAssertEqual(summary.stale, 2)
        XCTAssertEqual(summary.fresh, 5)
    }

    // MARK: - SetResponse Tests

    func testSetResponseInitialization() {
        let response = SetResponse(success: true, id: "test-id")

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.id, "test-id")
    }

    func testSetResponseEncoding() throws {
        let response = SetResponse(success: true, id: "abc-123")
        let json = try JSONHelper.encode(response)

        XCTAssertTrue(json.contains("true"))
        XCTAssertTrue(json.contains("abc-123"))
    }

    // MARK: - MoveResponse Tests

    func testMoveResponseInitialization() {
        let response = MoveResponse(success: true, id: "test-id", column: "Done")

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.id, "test-id")
        XCTAssertEqual(response.column, "Done")
    }

    func testMoveResponseEncoding() throws {
        let response = MoveResponse(success: false, id: "xyz-789", column: "In Progress")
        let json = try JSONHelper.encode(response)

        XCTAssertTrue(json.contains("false"))
        XCTAssertTrue(json.contains("xyz-789"))
        XCTAssertTrue(json.contains("In Progress"))
    }
}
