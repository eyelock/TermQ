import TermQShared
import XCTest

@testable import TermQCLICore

final class CLIFindTests: CLITestCase {

    private var col1 = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
    private var col2 = UUID(uuidString: "00000000-0000-0000-0001-000000000002")!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try seedBoard(
            columns: [
                SeedColumn(id: col1, name: "To Do", orderIndex: 0),
                SeedColumn(id: col2, name: "In Progress", orderIndex: 1),
            ],
            cards: [
                SeedCard(
                    name: "API Project",
                    description: "Build the REST API",
                    workingDirectory: "/projects/api",
                    columnId: col1,
                    orderIndex: 0,
                    badge: "urgent",
                    llmNextAction: "Fix the auth bug",
                    tags: [(key: "project", value: "eyelock/api"), (key: "staleness", value: "stale")]
                ),
                SeedCard(
                    name: "Frontend App",
                    description: "React dashboard",
                    workingDirectory: "/projects/frontend",
                    columnId: col2,
                    orderIndex: 0,
                    isFavourite: true,
                    tags: [(key: "project", value: "eyelock/frontend"), (key: "staleness", value: "fresh")]
                ),
                SeedCard(
                    name: "Database Setup",
                    description: "PostgreSQL migration",
                    workingDirectory: "/projects/db",
                    columnId: col1,
                    orderIndex: 1
                ),
            ]
        )
    }

    // MARK: - normalizeToWords

    func test_normalizeToWords_hyphenSeparated_splitIntoWords() {
        let cmd = Find()
        let result = cmd.normalizeToWords("hello-world")
        XCTAssertTrue(result.contains("hello"))
        XCTAssertTrue(result.contains("world"))
    }

    func test_normalizeToWords_slashSeparated_splitIntoWords() {
        let cmd = Find()
        let result = cmd.normalizeToWords("eyelock/api")
        XCTAssertTrue(result.contains("eyelock"))
        XCTAssertTrue(result.contains("api"))
    }

    func test_normalizeToWords_singleCharWord_filtered() {
        let cmd = Find()
        let result = cmd.normalizeToWords("a b hello")
        XCTAssertFalse(result.contains("a"))
        XCTAssertFalse(result.contains("b"))
        XCTAssertTrue(result.contains("hello"))
    }

    func test_normalizeToWords_uppercase_lowercased() {
        let cmd = Find()
        let result = cmd.normalizeToWords("Hello World")
        XCTAssertTrue(result.contains("hello"))
        XCTAssertTrue(result.contains("world"))
    }

    func test_normalizeToWords_emptyString_returnsEmpty() {
        let cmd = Find()
        XCTAssertTrue(cmd.normalizeToWords("").isEmpty)
    }

    // MARK: - Filter: name

    func test_find_byName_partialMatch_returnsMatches() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--name", "api", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "API Project")
    }

    func test_find_byName_caseInsensitive() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--name", "API PROJECT", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 1)
    }

    func test_find_byName_noMatch_returnsEmpty() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--name", "nonexistent", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Filter: column

    func test_find_byColumn_returnsCardsInColumn() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--column", "To Do", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.column == "To Do" })
    }

    func test_find_byColumn_partialMatch() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--column", "progress", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Frontend App")
    }

    // MARK: - Filter: tag (key only)

    func test_find_byTagKey_returnsMatchingCards() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--tag", "project", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Filter: tag (key=value)

    func test_find_byTagKeyValue_exactMatch() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--tag", "staleness=stale", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "API Project")
    }

    func test_find_byTagKeyValue_noMatch_returnsEmpty() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--tag", "staleness=ancient", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Filter: badge

    func test_find_byBadge_returnsMatchingCard() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--badge", "urgent", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "API Project")
    }

    // MARK: - Filter: favourites

    func test_find_favourites_onlyReturnsFavourites() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--favourites", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Frontend App")
    }

    // MARK: - Filter: by ID

    func test_find_byId_returnsMatchingCard() throws {
        let board = try loadBoard()
        let cardId = board.activeCards.first!.id.uuidString

        let output = try captureOutput {
            var cmd = try Find.parse(["--id", cardId, "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, cardId)
    }

    func test_find_byInvalidUUID_returnsEmpty() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--id", "not-a-uuid", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Smart query

    func test_find_query_matchesAcrossFields() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--query", "postgres", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Database Setup")
    }

    func test_find_query_emptyQuery_returnsAll() throws {
        // An empty --query string means no filter — all active cards are returned
        let output = try captureOutput {
            var cmd = try Find.parse(["--query", "", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 3)
    }

    // MARK: - No filter: returns all active cards

    func test_find_noFilters_returnsAllActive() throws {
        let output = try captureOutput {
            var cmd = try Find.parse(["--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 3)
    }
}
