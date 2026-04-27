import Foundation
import MCPServerLib
import TermQShared
import XCTest

@testable import TermQCLICore

/// Base class for all CLI command tests. Provides a temp board directory,
/// board-writing helpers, and stdout capture for asserting JSON output.
class CLITestCase: XCTestCase {

    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQCLITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        GUIDetector.testModeOverride = false
    }

    override func tearDownWithError() throws {
        GUIDetector.testModeOverride = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    // MARK: - Board Helpers

    func seedBoard(columns: [SeedColumn] = [], cards: [SeedCard] = []) throws {
        let encoder = JSONEncoder()

        var columnsJSON: [[String: Any]] = columns.map { col in
            ["id": col.id.uuidString, "name": col.name, "orderIndex": col.orderIndex]
        }
        if columnsJSON.isEmpty {
            columnsJSON = [["id": defaultColumnId.uuidString, "name": "To Do", "orderIndex": 0]]
        }

        let cardsJSON: [[String: Any]] = cards.map { card in
            var dict: [String: Any] = [
                "id": card.id.uuidString,
                "title": card.name,
                "description": card.description,
                "workingDirectory": card.workingDirectory,
                "columnId": card.columnId.uuidString,
                "orderIndex": card.orderIndex,
                "needsTmuxSession": false,
                "isFavourite": card.isFavourite,
                "badge": card.badge,
                "llmPrompt": card.llmPrompt,
                "llmNextAction": card.llmNextAction,
            ]
            if !card.tags.isEmpty {
                dict["tags"] = card.tags.map { tag in
                    ["id": UUID().uuidString, "key": tag.key, "value": tag.value]
                }
            }
            return dict
        }

        let board: [String: Any] = ["columns": columnsJSON, "cards": cardsJSON]
        _ = encoder  // suppress unused warning; we use JSONSerialization for dict→data
        let data = try JSONSerialization.data(withJSONObject: board)
        let boardURL = tempDirectory.appendingPathComponent("board.json")
        try data.write(to: boardURL)
    }

    var defaultColumnId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func loadBoard() throws -> Board {
        try BoardLoader.loadBoard(dataDirectory: tempDirectory)
    }

    // MARK: - Stdout Capture

    /// Runs `block`, captures everything printed to stdout, and returns it as a String.
    @discardableResult
    func captureOutput(executing block: () throws -> Void) throws -> String {
        let pipe = Pipe()
        let originalFd = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        var caughtError: Error?
        do { try block() } catch { caughtError = error }

        fflush(stdout)
        dup2(originalFd, STDOUT_FILENO)
        close(originalFd)
        pipe.fileHandleForWriting.closeFile()

        if let error = caughtError { throw error }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - JSON Decode Helpers

    func decodeOutput<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Seed Types

struct SeedColumn {
    let id: UUID
    let name: String
    let orderIndex: Int

    init(id: UUID = UUID(), name: String, orderIndex: Int = 0) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
    }
}

struct SeedCard {
    let id: UUID
    let name: String
    let description: String
    let workingDirectory: String
    let columnId: UUID
    let orderIndex: Int
    let isFavourite: Bool
    let badge: String
    let llmPrompt: String
    let llmNextAction: String
    let tags: [(key: String, value: String)]

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        workingDirectory: String = "/tmp",
        columnId: UUID,
        orderIndex: Int = 0,
        isFavourite: Bool = false,
        badge: String = "",
        llmPrompt: String = "",
        llmNextAction: String = "",
        tags: [(key: String, value: String)] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.workingDirectory = workingDirectory
        self.columnId = columnId
        self.orderIndex = orderIndex
        self.isFavourite = isFavourite
        self.badge = badge
        self.llmPrompt = llmPrompt
        self.llmNextAction = llmNextAction
        self.tags = tags
    }
}
