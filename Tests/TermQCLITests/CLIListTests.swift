import TermQShared
import XCTest

@testable import TermQCLICore

final class CLIListTests: CLITestCase {

    private var col1 = UUID(uuidString: "00000000-0000-0000-0002-000000000001")!
    private var col2 = UUID(uuidString: "00000000-0000-0000-0002-000000000002")!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try seedBoard(
            columns: [
                SeedColumn(id: col1, name: "To Do", orderIndex: 0),
                SeedColumn(id: col2, name: "Done", orderIndex: 1),
            ],
            cards: [
                SeedCard(name: "Alpha", workingDirectory: "/alpha", columnId: col1, orderIndex: 0),
                SeedCard(name: "Beta", workingDirectory: "/beta", columnId: col2, orderIndex: 0),
                SeedCard(name: "Gamma", workingDirectory: "/gamma", columnId: col1, orderIndex: 1),
            ]
        )
    }

    // MARK: - List all

    func test_list_all_returnsAllActiveCards() throws {
        let output = try captureOutput {
            let cmd = try List.parse(["--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 3)
    }

    func test_list_emptyBoard_returnsEmptyArray() throws {
        try seedBoard()
        let output = try captureOutput {
            let cmd = try List.parse(["--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Column filter

    func test_list_filterByColumn_returnsOnlyMatchingCards() throws {
        let output = try captureOutput {
            let cmd = try List.parse(["--column", "To Do", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.column == "To Do" })
    }

    func test_list_filterByColumn_caseInsensitive() throws {
        let output = try captureOutput {
            let cmd = try List.parse(["--column", "done", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Beta")
    }

    func test_list_filterByColumn_noMatch_returnsEmpty() throws {
        let output = try captureOutput {
            let cmd = try List.parse(["--column", "Backlog", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Columns flag

    func test_list_columnsFlag_returnsColumnInfo() throws {
        let output = try captureOutput {
            let cmd = try List.parse(["--columns", "--data-directory", tempDirectory.path])
            try cmd.run()
        }
        // ColumnOutput is a JSON array with id, name, terminalCount fields
        let data = Data(output.utf8)
        let decoded = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        XCTAssertEqual(decoded.count, 2)
        let names = decoded.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("To Do"))
        XCTAssertTrue(names.contains("Done"))
    }

    // MARK: - Sort order

    func test_list_sortedByColumnThenOrderIndex() throws {
        let output = try captureOutput {
            let cmd = try List.parse(["--data-directory", tempDirectory.path])
            try cmd.run()
        }
        let results = try decodeOutput(output, as: [TerminalOutput].self)
        // col1 (To Do) orderIndex 0 < col2 (Done) orderIndex 1
        // Within To Do: Alpha (0) before Gamma (1)
        XCTAssertEqual(results[0].name, "Alpha")
        XCTAssertEqual(results[1].name, "Gamma")
        XCTAssertEqual(results[2].name, "Beta")
    }
}
