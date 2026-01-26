import Foundation
import TermQShared
import XCTest

@testable import MCPServerLib

/// Tests for HeadlessWriter operations (headless mode when GUI not running)
final class HeadlessWriterTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        // Create temporary directory for test data
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-HeadlessTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir
    }

    override func tearDownWithError() throws {
        // Clean up temporary directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Helper Methods

    private func createTestBoard() -> Board {
        let columns = [
            Column(id: UUID(), name: "To Do", orderIndex: 0),
            Column(id: UUID(), name: "In Progress", orderIndex: 1),
            Column(id: UUID(), name: "Done", orderIndex: 2),
        ]

        let cards = [
            Card(
                id: UUID(),
                title: "Test Card 1",
                columnId: columns[0].id,
                workingDirectory: "/Users/test/project1"
            ),
            Card(
                id: UUID(),
                title: "Test Card 2",
                columnId: columns[1].id,
                workingDirectory: "/Users/test/project2"
            ),
        ]

        return Board(columns: columns, cards: cards)
    }

    private func writeTestBoard(_ board: Board) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(board)
        try data.write(to: tempDirectory.appendingPathComponent("board.json"))
    }

    private func loadRawBoardJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: tempDirectory.appendingPathComponent("board.json"))
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    // MARK: - HeadlessWriter.createCard Tests

    func testCreateCardSetsNeedsTmuxSessionFlag() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        let created = try HeadlessWriter.createCard(
            name: "Headless Card",
            columnName: "To Do",
            workingDirectory: "/tmp",
            description: "Test",
            llmPrompt: nil,
            llmNextAction: nil,
            tags: nil,
            dataDirectory: tempDirectory
        )

        // Verify needsTmuxSession is set
        XCTAssertTrue(created.needsTmuxSession, "Headless-created cards should have needsTmuxSession=true")

        // Verify in raw JSON
        let rawBoard = try loadRawBoardJSON()
        let cards = rawBoard["cards"] as! [[String: Any]]
        let createdCard = cards.first { ($0["id"] as? String) == created.id.uuidString }
        XCTAssertNotNil(createdCard)
        XCTAssertEqual(createdCard?["needsTmuxSession"] as? Bool, true)
    }

    func testCreateCardWithLLMPromptAndNextAction() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        let created = try HeadlessWriter.createCard(
            name: "LLM Card",
            columnName: "To Do",
            workingDirectory: "/tmp",
            description: "Test",
            llmPrompt: "This is a persistent prompt",
            llmNextAction: "Do this next",
            tags: nil,
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(created.llmPrompt, "This is a persistent prompt")
        XCTAssertEqual(created.llmNextAction, "Do this next")
    }

    func testCreateCardWithTags() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        let tags: [(String, String)] = [
            ("project", "test"),
            ("priority", "high"),
        ]

        let created = try HeadlessWriter.createCard(
            name: "Tagged Card",
            columnName: "To Do",
            workingDirectory: "/tmp",
            description: nil,
            llmPrompt: nil,
            llmNextAction: nil,
            tags: tags,
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(created.tags.count, 2)
        XCTAssertTrue(created.tags.contains { $0.key == "project" && $0.value == "test" })
        XCTAssertTrue(created.tags.contains { $0.key == "priority" && $0.value == "high" })
    }

    // MARK: - HeadlessWriter.updateCard Tests

    func testUpdateCardFields() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let cardId = board.cards[0].id.uuidString

        let params = HeadlessWriter.UpdateParameters(
            name: "Updated Name",
            description: "Updated Description",
            badge: "urgent",
            llmPrompt: "New prompt",
            llmNextAction: "New action",
            favourite: true,
            tags: [("status", "updated")],
            replaceTags: true
        )

        let updated = try HeadlessWriter.updateCard(
            identifier: cardId,
            params: params,
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(updated.title, "Updated Name")
        XCTAssertEqual(updated.description, "Updated Description")
        XCTAssertEqual(updated.badge, "urgent")
        XCTAssertEqual(updated.llmPrompt, "New prompt")
        XCTAssertEqual(updated.llmNextAction, "New action")
        XCTAssertTrue(updated.isFavourite)
        XCTAssertEqual(updated.tags.count, 1)
        XCTAssertEqual(updated.tags[0].key, "status")
        XCTAssertEqual(updated.tags[0].value, "updated")
    }

    func testUpdateCardWithTagMerge() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        // Create card with existing tags
        var card = board.cards[0]
        card = try BoardWriter.updateCard(
            identifier: card.id.uuidString,
            updates: ["tags": [["id": UUID().uuidString, "key": "existing", "value": "tag"]]],
            dataDirectory: tempDirectory
        )

        // Update with new tags, merge mode
        let params = HeadlessWriter.UpdateParameters(
            tags: [("new", "tag")],
            replaceTags: false
        )

        let updated = try HeadlessWriter.updateCard(
            identifier: card.id.uuidString,
            params: params,
            dataDirectory: tempDirectory
        )

        // Should have both tags
        XCTAssertEqual(updated.tags.count, 2)
        XCTAssertTrue(updated.tags.contains { $0.key == "existing" })
        XCTAssertTrue(updated.tags.contains { $0.key == "new" })
    }

    // MARK: - HeadlessWriter.moveCard Tests

    func testMoveCard() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let cardId = board.cards[0].id.uuidString

        let moved = try HeadlessWriter.moveCard(
            identifier: cardId,
            toColumn: "Done",
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(moved.columnId, board.columns[2].id)
    }

    // MARK: - HeadlessWriter.deleteCard Tests (Critical Bug Fixes)

    func testDeleteCardUsesTimeIntervalFormat() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let cardId = board.cards[0].id.uuidString

        // Soft delete the card
        try HeadlessWriter.deleteCard(
            identifier: cardId,
            permanent: false,
            dataDirectory: tempDirectory
        )

        // Load raw JSON to check deletedAt format
        let rawBoard = try loadRawBoardJSON()
        let cards = rawBoard["cards"] as! [[String: Any]]
        let deletedCard = cards.first { ($0["id"] as? String) == cardId }

        XCTAssertNotNil(deletedCard)

        // CRITICAL: deletedAt must be a number (TimeInterval), not a string
        guard let deletedAt = deletedCard?["deletedAt"] else {
            XCTFail("deletedAt field not found")
            return
        }

        // Verify it's a number (Double/TimeInterval)
        XCTAssertTrue(deletedAt is Double || deletedAt is NSNumber,
                      "deletedAt must be TimeInterval (number), not ISO8601 string")

        // Verify it's a reasonable timestamp (between 2001 and 2050)
        if let timestamp = deletedAt as? Double {
            XCTAssertGreaterThan(timestamp, 0, "TimeInterval should be positive")
            XCTAssertLessThan(timestamp, 1_577_836_800, "TimeInterval should be reasonable (< 2050)")
        }
    }

    func testDeleteCardCanBeReloadedAsCard() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let cardId = board.cards[0].id.uuidString

        // Soft delete
        try HeadlessWriter.deleteCard(
            identifier: cardId,
            permanent: false,
            dataDirectory: tempDirectory
        )

        // CRITICAL: Board should still be decodable after soft delete
        XCTAssertNoThrow(try BoardLoader.loadBoard(dataDirectory: tempDirectory),
                         "Board must be decodable after soft delete operation")

        // Verify card is present but marked as deleted
        let reloaded = try BoardLoader.loadBoard(dataDirectory: tempDirectory)
        let deletedCard = reloaded.cards.first { $0.id.uuidString == cardId }

        XCTAssertNotNil(deletedCard, "Deleted card should still exist in cards array")
        XCTAssertTrue(deletedCard!.isDeleted, "Card should be marked as deleted")
        XCTAssertNotNil(deletedCard!.deletedAt, "deletedAt timestamp should be set")

        // Verify card is NOT in activeCards
        XCTAssertFalse(reloaded.activeCards.contains { $0.id.uuidString == cardId },
                       "Deleted card should not appear in activeCards")
    }

    func testDeleteCardAllowsUpdateAfterDelete() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let cardId = board.cards[0].id.uuidString

        // Soft delete
        try HeadlessWriter.deleteCard(
            identifier: cardId,
            permanent: false,
            dataDirectory: tempDirectory
        )

        // CRITICAL: Should be able to update a deleted card
        // (This was failing before the fix - updateCard couldn't find deleted cards)
        XCTAssertNoThrow(
            try BoardWriter.updateCard(
                identifier: cardId,
                updates: ["description": "Updated after delete"],
                dataDirectory: tempDirectory
            ),
            "Should be able to update a card even after it's been soft-deleted"
        )

        // Verify the update worked
        let reloaded = try BoardLoader.loadBoard(dataDirectory: tempDirectory)
        let card = reloaded.cards.first { $0.id.uuidString == cardId }
        XCTAssertEqual(card?.description, "Updated after delete")
        XCTAssertTrue(card!.isDeleted, "Card should still be deleted")
    }

    func testPermanentDeleteRemovesCard() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let cardId = board.cards[0].id.uuidString

        let initialCount = board.cards.count

        // Permanent delete
        try HeadlessWriter.deleteCard(
            identifier: cardId,
            permanent: true,
            dataDirectory: tempDirectory
        )

        // Reload and verify card is gone
        let reloaded = try BoardLoader.loadBoard(dataDirectory: tempDirectory)
        XCTAssertEqual(reloaded.cards.count, initialCount - 1)
        XCTAssertNil(reloaded.cards.first { $0.id.uuidString == cardId })
    }

    func testSoftDeletePreservesCardData() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let card = board.cards[0]
        let cardId = card.id.uuidString

        // Soft delete
        try HeadlessWriter.deleteCard(
            identifier: cardId,
            permanent: false,
            dataDirectory: tempDirectory
        )

        // Reload and verify all original data is preserved
        let reloaded = try BoardLoader.loadBoard(dataDirectory: tempDirectory)
        let deletedCard = reloaded.cards.first { $0.id.uuidString == cardId }!

        XCTAssertEqual(deletedCard.id, card.id)
        XCTAssertEqual(deletedCard.title, card.title)
        XCTAssertEqual(deletedCard.workingDirectory, card.workingDirectory)
        XCTAssertEqual(deletedCard.columnId, card.columnId)
        XCTAssertTrue(deletedCard.isDeleted, "Should be marked as deleted")
    }

    // MARK: - Edge Cases

    func testCreateCardInDefaultColumn() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        let created = try HeadlessWriter.createCard(
            name: "Default Column Card",
            columnName: nil, // Should use first column
            workingDirectory: "/tmp",
            description: nil,
            llmPrompt: nil,
            llmNextAction: nil,
            tags: nil,
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(created.columnId, board.columns[0].id)
    }

    func testUpdateCardWithPartialParameters() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let originalCard = board.cards[0]

        // Update only badge, leave everything else unchanged
        let params = HeadlessWriter.UpdateParameters(badge: "new-badge")

        let updated = try HeadlessWriter.updateCard(
            identifier: originalCard.id.uuidString,
            params: params,
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(updated.badge, "new-badge")
        XCTAssertEqual(updated.title, originalCard.title) // Unchanged
        XCTAssertEqual(updated.workingDirectory, originalCard.workingDirectory) // Unchanged
    }

    func testDeleteCardByName() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        // Delete by name instead of UUID
        try HeadlessWriter.deleteCard(
            identifier: "Test Card 1",
            permanent: false,
            dataDirectory: tempDirectory
        )

        let reloaded = try BoardLoader.loadBoard(dataDirectory: tempDirectory)
        let deletedCard = reloaded.cards.first { $0.title == "Test Card 1" }
        XCTAssertTrue(deletedCard!.isDeleted)
    }
}
