import XCTest

@testable import TermQCLICore

final class CLIPendingTests: CLITestCase {

    private var col1 = UUID(uuidString: "00000000-0000-0000-0005-000000000001")!

    // MARK: - Pending output structure

    private struct PendingJSON: Decodable {
        struct Summary: Decodable {
            let total: Int
            let withNextAction: Int
            let stale: Int
            let fresh: Int
        }
        struct Terminal: Decodable {
            let id: String
            let name: String
            let llmNextAction: String
            let staleness: String
        }
        let terminals: [Terminal]
        let summary: Summary
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try seedBoard(
            columns: [SeedColumn(id: col1, name: "To Do", orderIndex: 0)],
            cards: [
                SeedCard(
                    name: "Has Action",
                    columnId: col1,
                    llmNextAction: "Do something important",
                    tags: [(key: "staleness", value: "stale")]
                ),
                SeedCard(
                    name: "No Action",
                    columnId: col1,
                    tags: [(key: "staleness", value: "fresh")]
                ),
                SeedCard(
                    name: "Another Action",
                    columnId: col1,
                    llmNextAction: "Also important"
                ),
            ]
        )
    }

    // MARK: - All terminals

    func test_pending_returnsAllActiveTerminals() throws {
        let output = try captureOutput {
            let cmd = try Pending.parse(["--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let result = try decodeOutput(output, as: PendingJSON.self)
        XCTAssertEqual(result.summary.total, 3)
    }

    // MARK: - Summary counts

    func test_pending_summaryCountsWithNextAction() throws {
        let output = try captureOutput {
            let cmd = try Pending.parse(["--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let result = try decodeOutput(output, as: PendingJSON.self)
        XCTAssertEqual(result.summary.withNextAction, 2)
    }

    func test_pending_summaryCountsStaleAndFresh() throws {
        let output = try captureOutput {
            let cmd = try Pending.parse(["--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let result = try decodeOutput(output, as: PendingJSON.self)
        XCTAssertEqual(result.summary.stale, 1)
        XCTAssertEqual(result.summary.fresh, 1)
    }

    // MARK: - actions-only flag

    func test_pending_actionsOnly_onlyIncludesCardsWithActions() throws {
        let output = try captureOutput {
            let cmd = try Pending.parse(["--actions-only", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let result = try decodeOutput(output, as: PendingJSON.self)
        XCTAssertEqual(result.summary.total, 2)
        XCTAssertTrue(result.terminals.allSatisfy { !$0.llmNextAction.isEmpty })
    }

    // MARK: - Sort: cards with actions come first

    func test_pending_cardsWithActionsSortFirst() throws {
        let output = try captureOutput {
            let cmd = try Pending.parse(["--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let result = try decodeOutput(output, as: PendingJSON.self)
        // First two entries should have llmNextAction set
        XCTAssertFalse(result.terminals[0].llmNextAction.isEmpty)
        XCTAssertFalse(result.terminals[1].llmNextAction.isEmpty)
        XCTAssertTrue(result.terminals[2].llmNextAction.isEmpty)
    }

    // MARK: - Staleness in output

    func test_pending_includesStalenessField() throws {
        let output = try captureOutput {
            let cmd = try Pending.parse(["--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let result = try decodeOutput(output, as: PendingJSON.self)
        let staleTerminal = result.terminals.first { $0.name == "Has Action" }
        XCTAssertEqual(staleTerminal?.staleness, "stale")
    }

    // MARK: - Empty board

    func test_pending_emptyBoard_returnsZeroTotals() throws {
        try seedBoard(columns: [SeedColumn(id: col1, name: "To Do", orderIndex: 0)])
        let output = try captureOutput {
            let cmd = try Pending.parse(["--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let result = try decodeOutput(output, as: PendingJSON.self)
        XCTAssertEqual(result.summary.total, 0)
        XCTAssertEqual(result.summary.withNextAction, 0)
    }

    // MARK: - getFilteredAndSortedCards (unit test the method directly)

    func test_getFilteredAndSortedCards_withActionsOnly_filtersCorrectly() throws {
        let board = try loadBoard()
        let cmd = try Pending.parse(["--actions-only", "--data-directory", tempDirectory.path])
        let cards = cmd.getFilteredAndSortedCards(from: board)
        XCTAssertTrue(cards.allSatisfy { !$0.llmNextAction.isEmpty })
    }

    func test_buildPendingOutput_countsCorrectly() throws {
        let board = try loadBoard()
        let cmd = try Pending.parse(["--data-directory", tempDirectory.path])
        let cards = cmd.getFilteredAndSortedCards(from: board)
        let output = cmd.buildPendingOutput(cards: cards, board: board)
        XCTAssertEqual(output.summary.total, 3)
        XCTAssertEqual(output.summary.withNextAction, 2)
    }
}
