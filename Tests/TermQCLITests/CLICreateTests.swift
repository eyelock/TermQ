import XCTest

@testable import TermQCLICore

final class CLICreateTests: CLITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try seedBoard()  // default "To Do" column
    }

    // MARK: - New command (headless)

    func test_new_headless_createsCard() throws {
        try captureOutput {
            let cmd = try New.parse([
                "--name", "My Terminal",
                "--path", "/projects/test",
                "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertEqual(board.activeCards.count, 1)
        XCTAssertEqual(board.activeCards[0].title, "My Terminal")
        XCTAssertEqual(board.activeCards[0].workingDirectory, "/projects/test")
    }

    func test_new_headless_defaultsNameToDirectoryName() throws {
        try captureOutput {
            let cmd = try New.parse([
                "--path", "/projects/myapp",
                "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertEqual(board.activeCards[0].title, "myapp")
    }

    func test_new_headless_withColumn_placesCardInColumn() throws {
        let colId = UUID(uuidString: "00000000-0000-0000-0003-000000000002")!
        try seedBoard(
            columns: [
                SeedColumn(id: defaultColumnId, name: "To Do", orderIndex: 0),
                SeedColumn(id: colId, name: "In Progress", orderIndex: 1),
            ]
        )

        try captureOutput {
            let cmd = try New.parse([
                "--name", "Test",
                "--path", "/tmp",
                "--column", "In Progress",
                "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        let card = try XCTUnwrap(board.activeCards.first)
        XCTAssertEqual(board.columnName(for: card.columnId), "In Progress")
    }

    func test_new_headless_outputsJSON() throws {
        let output = try captureOutput {
            let cmd = try New.parse([
                "--name", "Output Test",
                "--path", "/tmp",
                "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let data = Data(output.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["name"] as? String, "Output Test")
        XCTAssertNotNil(json["id"])
    }

    // MARK: - Create command (headless)

    func test_create_headless_createsCard() throws {
        try captureOutput {
            let cmd = try Create.parse([
                "--name", "Created Terminal",
                "--path", "/projects/created",
                "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertEqual(board.activeCards.count, 1)
        XCTAssertEqual(board.activeCards[0].title, "Created Terminal")
    }

    func test_create_headless_withDescription_setsDescription() throws {
        try captureOutput {
            let cmd = try Create.parse([
                "--name", "Described",
                "--description", "A test terminal",
                "--path", "/tmp",
                "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertEqual(board.activeCards[0].description, "A test terminal")
    }

    func test_create_headless_withTags_setsTagsOnCard() throws {
        try captureOutput {
            let cmd = try Create.parse([
                "--name", "Tagged",
                "--path", "/tmp",
                "--tag", "project=myapp",
                "--tag", "env=dev",
                "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        let card = try XCTUnwrap(board.activeCards.first)
        XCTAssertEqual(card.tags.count, 2)
        XCTAssertTrue(card.tags.contains { $0.key == "project" && $0.value == "myapp" })
        XCTAssertTrue(card.tags.contains { $0.key == "env" && $0.value == "dev" })
    }

    func test_create_headless_invalidColumn_throwsFailure() throws {
        XCTAssertThrowsError(
            try {
                try captureOutput {
                    let cmd = try Create.parse([
                        "--name", "Test",
                        "--column", "Nonexistent Column",
                        "--path", "/tmp",
                        "--data-directory", tempDirectory.path,
                    ])
                    try cmd.run()
                }
            }())
    }

    func test_create_headless_setsNeedsTmuxSession() throws {
        try captureOutput {
            let cmd = try Create.parse([
                "--name", "Tmux Card",
                "--path", "/tmp",
                "--data-directory", tempDirectory.path,
            ])
            try cmd.run()
        }
        let board = try loadBoard()
        XCTAssertTrue(board.activeCards[0].needsTmuxSession)
    }
}
