import XCTest

@testable import TermQCLICore

final class CLIMutationsTests: CLITestCase {

    private var col1 = UUID(uuidString: "00000000-0000-0000-0004-000000000001")!
    private var col2 = UUID(uuidString: "00000000-0000-0000-0004-000000000002")!
    private var cardId = UUID(uuidString: "00000000-0000-0000-0004-AAAAAAAAAAAA")!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try seedBoard(
            columns: [
                SeedColumn(id: col1, name: "To Do", orderIndex: 0),
                SeedColumn(id: col2, name: "Done", orderIndex: 1),
            ],
            cards: [
                SeedCard(
                    id: cardId,
                    name: "My Card",
                    description: "Original description",
                    workingDirectory: "/projects/mycard",
                    columnId: col1
                )
            ]
        )
    }

    // MARK: - Set: name

    func test_set_name_updatesCardName() throws {
        try captureOutput {
            var cmd = try Set.parse([
                "My Card", "--name", "Renamed Card", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertEqual(board.activeCards[0].title, "Renamed Card")
    }

    // MARK: - Set: description

    func test_set_description_updatesDescription() throws {
        try captureOutput {
            var cmd = try Set.parse([
                "My Card", "--set-description", "New description", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertEqual(board.activeCards[0].description, "New description")
    }

    // MARK: - Set: badge

    func test_set_badge_updatesBadge() throws {
        try captureOutput {
            var cmd = try Set.parse([
                "My Card", "--badge", "urgent", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertEqual(board.activeCards[0].badge, "urgent")
    }

    // MARK: - Set: llmPrompt

    func test_set_llmPrompt_updatesPrompt() throws {
        try captureOutput {
            var cmd = try Set.parse([
                "My Card", "--llm-prompt", "Remember this context", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertEqual(board.activeCards[0].llmPrompt, "Remember this context")
    }

    // MARK: - Set: llmNextAction

    func test_set_llmNextAction_updatesNextAction() throws {
        try captureOutput {
            var cmd = try Set.parse([
                "My Card", "--llm-next-action", "Fix the bug", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertEqual(board.activeCards[0].llmNextAction, "Fix the bug")
    }

    // MARK: - Set: tags (merge)

    func test_set_addTag_mergesWithExisting() throws {
        try captureOutput {
            var cmd = try Set.parse([
                "My Card", "--tag", "env=dev", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertTrue(board.activeCards[0].tags.contains { $0.key == "env" && $0.value == "dev" })
    }

    // MARK: - Set: favourite

    func test_set_favourite_setsIsFavouriteTrue() throws {
        try captureOutput {
            var cmd = try Set.parse([
                "My Card", "--favourite", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertTrue(board.activeCards[0].isFavourite)
    }

    func test_set_unfavourite_clearsFavourite() throws {
        // First set as favourite
        try captureOutput {
            var cmd = try Set.parse(["My Card", "--favourite", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        // Then unfavourite
        try captureOutput {
            var cmd = try Set.parse(["My Card", "--unfavourite", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertFalse(board.activeCards[0].isFavourite)
    }

    // MARK: - Set: column move

    func test_set_column_movesCardToColumn() throws {
        try captureOutput {
            var cmd = try Set.parse([
                "My Card", "--column", "Done", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        let card = board.activeCards.first!
        XCTAssertEqual(board.columnName(for: card.columnId), "Done")
    }

    // MARK: - Set: terminal not found

    func test_set_unknownTerminal_throwsFailure() {
        XCTAssertThrowsError(try captureOutput {
            var cmd = try Set.parse([
                "Nonexistent Card", "--name", "New Name", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        })
    }

    // MARK: - Move

    func test_move_movesCardToTargetColumn() throws {
        try captureOutput {
            var cmd = try Move.parse([
                "My Card", "Done", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        let card = board.activeCards.first!
        XCTAssertEqual(board.columnName(for: card.columnId), "Done")
    }

    func test_move_invalidColumn_throwsFailure() {
        XCTAssertThrowsError(try captureOutput {
            var cmd = try Move.parse([
                "My Card", "Nonexistent", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        })
    }

    func test_move_unknownTerminal_throwsFailure() {
        XCTAssertThrowsError(try captureOutput {
            var cmd = try Move.parse([
                "Ghost Card", "Done", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        })
    }

    // MARK: - Delete: soft

    func test_delete_soft_setsDeletedAt() throws {
        try captureOutput {
            var cmd = try Delete.parse([
                "My Card", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertTrue(board.activeCards.isEmpty)
        // Card should still exist but be soft-deleted
        XCTAssertEqual(board.cards.count, 1)
        XCTAssertNotNil(board.cards[0].deletedAt)
    }

    // MARK: - Delete: permanent

    func test_delete_permanent_removesCardFromBoard() throws {
        try captureOutput {
            var cmd = try Delete.parse([
                "My Card", "--permanent", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertTrue(board.cards.isEmpty)
    }

    func test_delete_unknownTerminal_throwsFailure() {
        XCTAssertThrowsError(try captureOutput {
            var cmd = try Delete.parse([
                "Ghost Card", "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        })
    }
}
