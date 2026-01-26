import Foundation
import XCTest

@testable import TermQShared

final class BoardLoaderTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        // Create temporary directory for test data
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-BoardLoaderTests-\(UUID().uuidString)")
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
            Column(id: UUID(), name: "To Do", description: "Tasks to start", orderIndex: 0, color: "#FF0000"),
            Column(id: UUID(), name: "In Progress", description: "Active work", orderIndex: 1, color: "#00FF00"),
            Column(id: UUID(), name: "Done", description: "", orderIndex: 2, color: "#0000FF"),
        ]

        let cards = [
            Card(
                id: UUID(),
                title: "Test Card 1",
                description: "First test card",
                columnId: columns[0].id,
                orderIndex: 0,
                workingDirectory: "/Users/test/project1"
            ),
            Card(
                id: UUID(),
                title: "Test Card 2",
                description: "Second test card",
                columnId: columns[1].id,
                orderIndex: 0,
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

    private func writeRawJSON(_ json: String) throws {
        try json.data(using: .utf8)!.write(to: tempDirectory.appendingPathComponent("board.json"))
    }

    // MARK: - BoardLoader.getDataDirectoryPath Tests

    func testGetDataDirectoryPathWithCustomDirectory() {
        let customDir = URL(fileURLWithPath: "/custom/path")
        let result = BoardLoader.getDataDirectoryPath(customDirectory: customDir)
        XCTAssertEqual(result, customDir)
    }

    func testGetDataDirectoryPathWithoutCustomDirectory() {
        let result = BoardLoader.getDataDirectoryPath()
        XCTAssertTrue(result.path.contains("Application Support"))
        XCTAssertTrue(result.path.contains("TermQ"))
    }

    func testGetDataDirectoryPathDebugMode() {
        let result = BoardLoader.getDataDirectoryPath(debug: true)
        XCTAssertTrue(result.path.contains("TermQ-Debug"))
    }

    func testGetDataDirectoryPathNonDebugMode() {
        let result = BoardLoader.getDataDirectoryPath(debug: false)
        XCTAssertTrue(result.path.contains("TermQ"))
        XCTAssertFalse(result.path.contains("TermQ-Debug"))
    }

    // MARK: - BoardLoader.loadBoard Tests

    func testLoadBoardSuccess() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        let loaded = try BoardLoader.loadBoard(dataDirectory: tempDirectory)

        XCTAssertEqual(loaded.columns.count, 3)
        XCTAssertEqual(loaded.cards.count, 2)
        XCTAssertEqual(loaded.columns[0].name, "To Do")
    }

    func testLoadBoardNotFound() {
        XCTAssertThrowsError(try BoardLoader.loadBoard(dataDirectory: tempDirectory)) { error in
            guard let loadError = error as? BoardLoader.LoadError else {
                XCTFail("Expected LoadError")
                return
            }
            if case .boardNotFound(let path) = loadError {
                XCTAssertTrue(path.contains("board.json"))
            } else {
                XCTFail("Expected boardNotFound error")
            }
        }
    }

    func testLoadBoardDecodingFailed() throws {
        // Write invalid JSON
        try writeRawJSON("{ invalid json }")

        XCTAssertThrowsError(try BoardLoader.loadBoard(dataDirectory: tempDirectory)) { error in
            guard let loadError = error as? BoardLoader.LoadError else {
                XCTFail("Expected LoadError, got \(error)")
                return
            }
            if case .decodingFailed(let message) = loadError {
                XCTAssertFalse(message.isEmpty)
            } else {
                XCTFail("Expected decodingFailed error")
            }
        }
    }

    // MARK: - LoadError Tests

    func testLoadErrorBoardNotFoundDescription() {
        let error = BoardLoader.LoadError.boardNotFound(path: "/test/path/board.json")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("/test/path/board.json"))
        XCTAssertTrue(error.errorDescription!.contains("not found"))
    }

    func testLoadErrorDecodingFailedDescription() {
        let error = BoardLoader.LoadError.decodingFailed("Invalid format")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Invalid format"))
        XCTAssertTrue(error.errorDescription!.contains("decode"))
    }

    func testLoadErrorCoordinationFailedDescription() {
        let error = BoardLoader.LoadError.coordinationFailed("Lock acquisition failed")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Lock acquisition failed"))
        XCTAssertTrue(error.errorDescription!.contains("coordination"))
    }

    // MARK: - BoardWriter.loadRawBoard Tests

    func testLoadRawBoardSuccess() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        let (url, data) = try BoardWriter.loadRawBoard(dataDirectory: tempDirectory)

        XCTAssertTrue(url.path.contains("board.json"))
        XCTAssertNotNil(data["columns"])
        XCTAssertNotNil(data["cards"])
    }

    func testLoadRawBoardNotFound() {
        XCTAssertThrowsError(try BoardWriter.loadRawBoard(dataDirectory: tempDirectory)) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .boardNotFound = writeError {
                // Expected
            } else {
                XCTFail("Expected boardNotFound error")
            }
        }
    }

    func testLoadRawBoardInvalidFormat() throws {
        // Write valid JSON but not a dictionary
        try writeRawJSON("[1, 2, 3]")

        XCTAssertThrowsError(try BoardWriter.loadRawBoard(dataDirectory: tempDirectory)) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError, got \(error)")
                return
            }
            if case .encodingFailed(let message) = writeError {
                XCTAssertTrue(message.contains("Invalid"))
            } else {
                XCTFail("Expected encodingFailed error")
            }
        }
    }

    // MARK: - BoardWriter.saveRawBoard Tests

    func testSaveRawBoardSuccess() throws {
        let board: [String: Any] = [
            "columns": [[String: Any]](),
            "cards": [[String: Any]](),
        ]
        let url = tempDirectory.appendingPathComponent("board.json")

        try BoardWriter.saveRawBoard(board, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        let loaded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(loaded)
    }

    // MARK: - BoardWriter.updateCard Tests

    func testUpdateCardByUUID() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let cardId = board.cards[0].id.uuidString

        let updated = try BoardWriter.updateCard(
            identifier: cardId,
            updates: ["description": "Updated description"],
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(updated.description, "Updated description")
    }

    func testUpdateCardByExactName() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        let updated = try BoardWriter.updateCard(
            identifier: "Test Card 1",
            updates: ["description": "Updated by name"],
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(updated.description, "Updated by name")
    }

    func testUpdateCardByPartialName() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        let updated = try BoardWriter.updateCard(
            identifier: "Card 1",
            updates: ["badge": "urgent"],
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(updated.badge, "urgent")
    }

    func testUpdateCardNotFound() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        XCTAssertThrowsError(
            try BoardWriter.updateCard(
                identifier: "nonexistent",
                updates: [:],
                dataDirectory: tempDirectory
            )
        ) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .cardNotFound(let identifier) = writeError {
                XCTAssertEqual(identifier, "nonexistent")
            } else {
                XCTFail("Expected cardNotFound error")
            }
        }
    }

    func testUpdateCardInvalidCardsFormat() throws {
        // Write board with invalid cards format
        let json = """
            {
                "columns": [],
                "cards": "not an array"
            }
            """
        try writeRawJSON(json)

        XCTAssertThrowsError(
            try BoardWriter.updateCard(
                identifier: "test",
                updates: [:],
                dataDirectory: tempDirectory
            )
        ) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .encodingFailed = writeError {
                // Expected
            } else {
                XCTFail("Expected encodingFailed error")
            }
        }
    }

    // MARK: - BoardWriter.moveCard Tests

    func testMoveCardToDifferentColumn() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let cardId = board.cards[0].id.uuidString

        let moved = try BoardWriter.moveCard(
            identifier: cardId,
            toColumn: "Done",
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(moved.columnId, board.columns[2].id)
    }

    func testMoveCardCaseInsensitiveColumnName() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let cardId = board.cards[0].id.uuidString

        let moved = try BoardWriter.moveCard(
            identifier: cardId,
            toColumn: "in progress",
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(moved.columnId, board.columns[1].id)
    }

    func testMoveCardColumnNotFound() throws {
        let board = createTestBoard()
        try writeTestBoard(board)
        let cardId = board.cards[0].id.uuidString

        XCTAssertThrowsError(
            try BoardWriter.moveCard(
                identifier: cardId,
                toColumn: "Nonexistent Column",
                dataDirectory: tempDirectory
            )
        ) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .columnNotFound(let name) = writeError {
                XCTAssertEqual(name, "Nonexistent Column")
            } else {
                XCTFail("Expected columnNotFound error")
            }
        }
    }

    func testMoveCardInvalidBoardFormat() throws {
        // Write board with invalid format
        let json = """
            {
                "columns": [],
                "cards": "not an array"
            }
            """
        try writeRawJSON(json)

        XCTAssertThrowsError(
            try BoardWriter.moveCard(
                identifier: "test",
                toColumn: "Done",
                dataDirectory: tempDirectory
            )
        ) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .encodingFailed = writeError {
                // Expected
            } else {
                XCTFail("Expected encodingFailed error")
            }
        }
    }

    func testMoveCardOrderIndexCalculation() throws {
        // Create a board with multiple cards in the target column
        let columns = [
            Column(id: UUID(), name: "To Do", orderIndex: 0),
            Column(id: UUID(), name: "Done", orderIndex: 1),
        ]
        let cards = [
            Card(id: UUID(), title: "Card to move", columnId: columns[0].id, orderIndex: 0),
            Card(id: UUID(), title: "Existing 1", columnId: columns[1].id, orderIndex: 0),
            Card(id: UUID(), title: "Existing 2", columnId: columns[1].id, orderIndex: 1),
        ]
        let board = Board(columns: columns, cards: cards)
        try writeTestBoard(board)

        let moved = try BoardWriter.moveCard(
            identifier: "Card to move",
            toColumn: "Done",
            dataDirectory: tempDirectory
        )

        // Should be placed at end with orderIndex 2
        XCTAssertEqual(moved.orderIndex, 2)
    }

    // MARK: - BoardWriter.createCard Tests

    func testCreateCardWithSpecifiedColumn() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        let created = try BoardWriter.createCard(
            name: "New Card",
            columnName: "In Progress",
            workingDirectory: "/Users/test/new",
            description: "A new card",
            dataDirectory: tempDirectory
        )

        XCTAssertEqual(created.title, "New Card")
        XCTAssertEqual(created.description, "A new card")
        XCTAssertEqual(created.workingDirectory, "/Users/test/new")
        XCTAssertEqual(created.columnId, board.columns[1].id)
    }

    func testCreateCardWithDefaultColumn() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        let created = try BoardWriter.createCard(
            name: "Default Column Card",
            columnName: nil,
            workingDirectory: "/Users/test/default",
            dataDirectory: tempDirectory
        )

        // Should use first column (To Do)
        XCTAssertEqual(created.columnId, board.columns[0].id)
    }

    func testCreateCardColumnNotFound() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        XCTAssertThrowsError(
            try BoardWriter.createCard(
                name: "New Card",
                columnName: "Nonexistent",
                workingDirectory: "/test",
                dataDirectory: tempDirectory
            )
        ) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .columnNotFound(let name) = writeError {
                XCTAssertEqual(name, "Nonexistent")
            } else {
                XCTFail("Expected columnNotFound error")
            }
        }
    }

    func testCreateCardInvalidBoardFormat() throws {
        let json = """
            {
                "columns": [],
                "cards": "not an array"
            }
            """
        try writeRawJSON(json)

        XCTAssertThrowsError(
            try BoardWriter.createCard(
                name: "New",
                columnName: nil,
                workingDirectory: "/test",
                dataDirectory: tempDirectory
            )
        ) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .encodingFailed = writeError {
                // Expected
            } else {
                XCTFail("Expected encodingFailed error")
            }
        }
    }

    func testCreateCardNoColumnsAvailable() throws {
        let json = """
            {
                "columns": [],
                "cards": []
            }
            """
        try writeRawJSON(json)

        XCTAssertThrowsError(
            try BoardWriter.createCard(
                name: "New",
                columnName: nil,
                workingDirectory: "/test",
                dataDirectory: tempDirectory
            )
        ) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .columnNotFound = writeError {
                // Expected
            } else {
                XCTFail("Expected columnNotFound error")
            }
        }
    }

    func testCreateCardOrderIndexCalculation() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        // Create first card in "Done" column (which has no cards)
        let created1 = try BoardWriter.createCard(
            name: "First in Done",
            columnName: "Done",
            workingDirectory: "/test1",
            dataDirectory: tempDirectory
        )
        XCTAssertEqual(created1.orderIndex, 0)

        // Create second card in "Done" column
        let created2 = try BoardWriter.createCard(
            name: "Second in Done",
            columnName: "Done",
            workingDirectory: "/test2",
            dataDirectory: tempDirectory
        )
        XCTAssertEqual(created2.orderIndex, 1)
    }

    // MARK: - WriteError Tests

    func testWriteErrorBoardNotFoundDescription() {
        let error = BoardWriter.WriteError.boardNotFound(path: "/test/path")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("/test/path"))
    }

    func testWriteErrorCardNotFoundDescription() {
        let error = BoardWriter.WriteError.cardNotFound(identifier: "my-card")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("my-card"))
    }

    func testWriteErrorColumnNotFoundDescription() {
        let error = BoardWriter.WriteError.columnNotFound(name: "My Column")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("My Column"))
    }

    func testWriteErrorEncodingFailedDescription() {
        let error = BoardWriter.WriteError.encodingFailed("Invalid data")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Invalid data"))
    }

    func testWriteErrorWriteFailedDescription() {
        let error = BoardWriter.WriteError.writeFailed("Permission denied")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Permission denied"))
    }

    func testWriteErrorCoordinationFailedDescription() {
        let error = BoardWriter.WriteError.coordinationFailed("Unable to acquire lock")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Unable to acquire lock"))
        XCTAssertTrue(error.errorDescription!.contains("coordination"))
    }

    // MARK: - findCardIndex Edge Cases

    func testFindCardByUUIDExcludesDeletedCards() throws {
        let columnId = UUID()
        let deletedCardId = UUID()
        let json = """
            {
                "columns": [{"id": "\(columnId.uuidString)", "name": "Test", "orderIndex": 0}],
                "cards": [
                    {"id": "\(deletedCardId.uuidString)", "title": "Deleted", "columnId": "\(columnId.uuidString)", "deletedAt": 791061521.05710804}
                ]
            }
            """
        try writeRawJSON(json)

        // After bug fix: updateCard CAN now find and update deleted cards
        // This is intentional - needed for soft-delete to work properly
        XCTAssertNoThrow(
            try BoardWriter.updateCard(
                identifier: deletedCardId.uuidString,
                updates: ["description": "Updated deleted card"],
                dataDirectory: tempDirectory
            ),
            "updateCard should be able to update deleted cards after bug fix"
        )

        // Verify the update worked
        let board = try BoardLoader.loadBoard(dataDirectory: tempDirectory)
        let card = board.cards.first { $0.id == deletedCardId }
        XCTAssertEqual(card?.description, "Updated deleted card")
        XCTAssertTrue(card!.isDeleted, "Card should still be marked as deleted")
    }

    func testFindCardByNameExcludesDeletedCards() throws {
        let columnId = UUID()
        let cardId = UUID()
        let json = """
            {
                "columns": [{"id": "\(columnId.uuidString)", "name": "Test", "orderIndex": 0}],
                "cards": [
                    {"id": "\(cardId.uuidString)", "title": "My Card", "columnId": "\(columnId.uuidString)", "deletedAt": 791061521.05710804}
                ]
            }
            """
        try writeRawJSON(json)

        // After bug fix: updateCard CAN now find and update deleted cards
        // This is intentional - needed for soft-delete to work properly
        XCTAssertNoThrow(
            try BoardWriter.updateCard(
                identifier: "My Card",
                updates: ["description": "Updated"],
                dataDirectory: tempDirectory
            ),
            "updateCard should be able to update deleted cards after bug fix"
        )

        // Verify the update worked
        let board = try BoardLoader.loadBoard(dataDirectory: tempDirectory)
        let card = board.cards.first { $0.id == cardId }
        XCTAssertEqual(card?.description, "Updated")
        XCTAssertTrue(card!.isDeleted, "Card should still be marked as deleted")
    }

    // MARK: - Debug Mode Tests

    func testLoadBoardWithDebugMode() throws {
        // Create debug directory
        let debugDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-Debug-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: debugDir)
        }

        let board = createTestBoard()
        let encoder = JSONEncoder()
        let data = try encoder.encode(board)
        try data.write(to: debugDir.appendingPathComponent("board.json"))

        let loaded = try BoardLoader.loadBoard(dataDirectory: debugDir, debug: true)
        XCTAssertEqual(loaded.columns.count, 3)
    }

    func testLoadRawBoardWithDebugMode() throws {
        let board = createTestBoard()
        try writeTestBoard(board)

        let (_, data) = try BoardWriter.loadRawBoard(dataDirectory: tempDirectory, debug: true)
        XCTAssertNotNil(data["columns"])
    }

    // MARK: - DecodingError Tests

    func testLoadBoardDecodingErrorMissingRequiredField() throws {
        // Write valid JSON but with missing required fields - this should trigger DecodingError
        let json = """
            {
                "columns": [{"name": "Test"}]
            }
            """
        try writeRawJSON(json)

        XCTAssertThrowsError(try BoardLoader.loadBoard(dataDirectory: tempDirectory)) { error in
            guard let loadError = error as? BoardLoader.LoadError else {
                XCTFail("Expected LoadError, got \(type(of: error)): \(error)")
                return
            }
            if case .decodingFailed(let message) = loadError {
                // Should contain info about the decoding failure
                XCTAssertFalse(message.isEmpty)
            } else {
                XCTFail("Expected decodingFailed error")
            }
        }
    }

    func testLoadBoardDecodingErrorWrongType() throws {
        // Write valid JSON but with wrong types - triggers DecodingError
        let json = """
            {
                "columns": [{"id": 123, "name": "Test", "orderIndex": 0}],
                "cards": []
            }
            """
        try writeRawJSON(json)

        XCTAssertThrowsError(try BoardLoader.loadBoard(dataDirectory: tempDirectory)) { error in
            guard let loadError = error as? BoardLoader.LoadError else {
                XCTFail("Expected LoadError, got \(type(of: error)): \(error)")
                return
            }
            if case .decodingFailed = loadError {
                // Expected - wrong type for id (Int instead of UUID string)
            } else {
                XCTFail("Expected decodingFailed error")
            }
        }
    }

    // MARK: - Column ID Edge Cases

    func testCreateCardColumnIdNotString() throws {
        // Write board with column that has non-string id
        let json = """
            {
                "columns": [{"id": 12345, "name": "Test", "orderIndex": 0}],
                "cards": []
            }
            """
        try writeRawJSON(json)

        XCTAssertThrowsError(
            try BoardWriter.createCard(
                name: "New Card",
                columnName: "Test",
                workingDirectory: "/test",
                dataDirectory: tempDirectory
            )
        ) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .columnNotFound = writeError {
                // Expected - column id is not a string so it can't be found properly
            } else {
                XCTFail("Expected columnNotFound error")
            }
        }
    }

    func testMoveCardToColumnWithInvalidId() throws {
        // Write board with column that has non-string id
        let json = """
            {
                "columns": [{"id": 12345, "name": "Target", "orderIndex": 0}],
                "cards": [{"id": "\(UUID().uuidString)", "title": "Test", "columnId": "some-id", "orderIndex": 0}]
            }
            """
        try writeRawJSON(json)

        XCTAssertThrowsError(
            try BoardWriter.moveCard(
                identifier: "Test",
                toColumn: "Target",
                dataDirectory: tempDirectory
            )
        ) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .columnNotFound = writeError {
                // Expected - column id is not a string
            } else {
                XCTFail("Expected columnNotFound error")
            }
        }
    }

    // MARK: - MoveCard Invalid Columns Format

    func testMoveCardInvalidColumnsFormat() throws {
        // Write board with invalid columns format (not an array)
        let json = """
            {
                "columns": "not an array",
                "cards": []
            }
            """
        try writeRawJSON(json)

        XCTAssertThrowsError(
            try BoardWriter.moveCard(
                identifier: "test",
                toColumn: "Done",
                dataDirectory: tempDirectory
            )
        ) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .encodingFailed = writeError {
                // Expected - columns is not an array
            } else {
                XCTFail("Expected encodingFailed error")
            }
        }
    }

    // MARK: - CreateCard Invalid Columns Format

    func testCreateCardInvalidColumnsFormat() throws {
        // Write board with invalid columns format
        let json = """
            {
                "columns": "not an array",
                "cards": []
            }
            """
        try writeRawJSON(json)

        XCTAssertThrowsError(
            try BoardWriter.createCard(
                name: "New",
                columnName: nil,
                workingDirectory: "/test",
                dataDirectory: tempDirectory
            )
        ) { error in
            guard let writeError = error as? BoardWriter.WriteError else {
                XCTFail("Expected WriteError")
                return
            }
            if case .encodingFailed = writeError {
                // Expected - columns is not an array
            } else {
                XCTFail("Expected encodingFailed error")
            }
        }
    }
}
