import Foundation
import MCP
import TermQShared
import XCTest

@testable import MCPServerLib

/// Tests for resource handler implementations
final class ResourceHandlersTests: XCTestCase {
    var tempDirectory: URL!
    var server: TermQMCPServer!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-ResourceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        server = nil
    }

    // MARK: - Helper

    private func createTestBoard(columns: [(UUID, String, Int)] = [], cards: [(String, UUID)] = []) throws {
        var columnJSON: [[String: Any]] = []
        for (id, name, order) in columns {
            columnJSON.append([
                "id": id.uuidString,
                "name": name,
                "orderIndex": order,
                "color": "#6B7280",
            ])
        }

        var cardJSON: [[String: Any]] = []
        for (title, columnId) in cards {
            cardJSON.append([
                "id": UUID().uuidString,
                "title": title,
                "description": "",
                "columnId": columnId.uuidString,
                "orderIndex": 0,
                "workingDirectory": "/tmp",
                "llmPrompt": "",
                "llmNextAction": "",
                "tags": [] as [[String: Any]],
            ])
        }

        let boardDict: [String: Any] = ["columns": columnJSON, "cards": cardJSON]
        let data = try JSONSerialization.data(withJSONObject: boardDict)
        try data.write(to: tempDirectory.appendingPathComponent("board.json"))

        server = TermQMCPServer(dataDirectory: tempDirectory)
    }

    // MARK: - Terminals Resource Tests

    func testTerminalsResourceSuccess() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [(columnId, "To Do", 0)],
            cards: [("Card 1", columnId), ("Card 2", columnId)]
        )

        let params = ReadResource.Parameters(uri: "termq://terminals")
        let result = try await server.dispatchResourceRead(params)

        XCTAssertEqual(result.contents.count, 1)
        let json = result.contents[0].text ?? ""
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminals.count, 2)
    }

    func testTerminalsResourceEmptyBoard() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [(columnId, "To Do", 0)],
            cards: []
        )

        let params = ReadResource.Parameters(uri: "termq://terminals")
        let result = try await server.dispatchResourceRead(params)

        let json = result.contents[0].text ?? ""
        let terminals = try JSONDecoder().decode([TerminalOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(terminals.count, 0)
    }

    func testTerminalsResourceWithLoadError() async throws {
        // Server with no board.json
        server = TermQMCPServer(dataDirectory: tempDirectory)

        let params = ReadResource.Parameters(uri: "termq://terminals")
        let result = try await server.dispatchResourceRead(params)

        // Should return empty array on error
        let json = result.contents[0].text ?? ""
        XCTAssertEqual(json, "[]")
    }

    // MARK: - Columns Resource Tests

    func testColumnsResourceSuccess() async throws {
        let col1 = UUID()
        let col2 = UUID()
        try createTestBoard(
            columns: [(col1, "To Do", 0), (col2, "Done", 1)],
            cards: [("Card 1", col1), ("Card 2", col1)]
        )

        let params = ReadResource.Parameters(uri: "termq://columns")
        let result = try await server.dispatchResourceRead(params)

        XCTAssertEqual(result.contents.count, 1)
        let json = result.contents[0].text ?? ""
        let columns = try JSONDecoder().decode([ColumnOutput].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(columns.count, 2)
        XCTAssertEqual(columns[0].name, "To Do")
        XCTAssertEqual(columns[0].terminalCount, 2)
        XCTAssertEqual(columns[1].terminalCount, 0)
    }

    func testColumnsResourceWithLoadError() async throws {
        server = TermQMCPServer(dataDirectory: tempDirectory)

        let params = ReadResource.Parameters(uri: "termq://columns")
        let result = try await server.dispatchResourceRead(params)

        let json = result.contents[0].text ?? ""
        XCTAssertEqual(json, "[]")
    }

    // MARK: - Pending Resource Tests

    func testPendingResourceSuccess() async throws {
        let columnId = UUID()

        // Create cards with varying staleness
        let cardJSON: [[String: Any]] = [
            [
                "id": UUID().uuidString,
                "title": "Fresh Card",
                "description": "",
                "columnId": columnId.uuidString,
                "orderIndex": 0,
                "workingDirectory": "/tmp",
                "llmPrompt": "",
                "llmNextAction": "Do something",
                "tags": [["id": UUID().uuidString, "key": "staleness", "value": "fresh"]],
            ],
            [
                "id": UUID().uuidString,
                "title": "Stale Card",
                "description": "",
                "columnId": columnId.uuidString,
                "orderIndex": 1,
                "workingDirectory": "/tmp",
                "llmPrompt": "",
                "llmNextAction": "",
                "tags": [["id": UUID().uuidString, "key": "staleness", "value": "stale"]],
            ],
        ]

        let columnJSON: [[String: Any]] = [
            [
                "id": columnId.uuidString,
                "name": "To Do",
                "orderIndex": 0,
                "color": "#6B7280",
            ]
        ]

        let boardDict: [String: Any] = ["columns": columnJSON, "cards": cardJSON]
        let data = try JSONSerialization.data(withJSONObject: boardDict)
        try data.write(to: tempDirectory.appendingPathComponent("board.json"))

        server = TermQMCPServer(dataDirectory: tempDirectory)

        let params = ReadResource.Parameters(uri: "termq://pending")
        let result = try await server.dispatchResourceRead(params)

        let json = result.contents[0].text ?? ""
        let output = try JSONDecoder().decode(PendingOutput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(output.summary.total, 2)
        XCTAssertEqual(output.summary.withNextAction, 1)
        XCTAssertEqual(output.summary.stale, 1)
        XCTAssertEqual(output.summary.fresh, 1)
    }

    func testPendingResourceWithLoadError() async throws {
        server = TermQMCPServer(dataDirectory: tempDirectory)

        let params = ReadResource.Parameters(uri: "termq://pending")
        let result = try await server.dispatchResourceRead(params)

        let json = result.contents[0].text ?? ""
        XCTAssertEqual(json, "{}")
    }

    func testPendingResourceSortsByActionsFirst() async throws {
        let columnId = UUID()

        let cardJSON: [[String: Any]] = [
            [
                "id": UUID().uuidString,
                "title": "No Action",
                "description": "",
                "columnId": columnId.uuidString,
                "orderIndex": 0,
                "workingDirectory": "/tmp",
                "llmPrompt": "",
                "llmNextAction": "",
                "tags": [] as [[String: Any]],
            ],
            [
                "id": UUID().uuidString,
                "title": "Has Action",
                "description": "",
                "columnId": columnId.uuidString,
                "orderIndex": 1,
                "workingDirectory": "/tmp",
                "llmPrompt": "",
                "llmNextAction": "Do this",
                "tags": [] as [[String: Any]],
            ],
        ]

        let columnJSON: [[String: Any]] = [
            [
                "id": columnId.uuidString,
                "name": "To Do",
                "orderIndex": 0,
                "color": "#6B7280",
            ]
        ]

        let boardDict: [String: Any] = ["columns": columnJSON, "cards": cardJSON]
        let data = try JSONSerialization.data(withJSONObject: boardDict)
        try data.write(to: tempDirectory.appendingPathComponent("board.json"))

        server = TermQMCPServer(dataDirectory: tempDirectory)

        let params = ReadResource.Parameters(uri: "termq://pending")
        let result = try await server.dispatchResourceRead(params)

        let json = result.contents[0].text ?? ""
        let output = try JSONDecoder().decode(PendingOutput.self, from: json.data(using: .utf8)!)

        // First terminal should be the one with action
        XCTAssertEqual(output.terminals[0].name, "Has Action")
    }

    // MARK: - Context Resource Tests

    func testContextResourceSuccess() async throws {
        try createTestBoard(columns: [], cards: [])

        let params = ReadResource.Parameters(uri: "termq://context")
        let result = try await server.dispatchResourceRead(params)

        XCTAssertEqual(result.contents.count, 1)
        let content = result.contents[0].text ?? ""
        XCTAssertTrue(content.contains("TermQ MCP Server"))
        XCTAssertTrue(content.contains("SESSION START CHECKLIST"))
    }

    func testContextResourceIncludesURI() async throws {
        try createTestBoard(columns: [], cards: [])

        let params = ReadResource.Parameters(uri: "termq://context")
        let result = try await server.dispatchResourceRead(params)

        // The resource content should include the URI
        XCTAssertEqual(result.contents[0].uri, "termq://context")
    }

    // MARK: - Unknown Resource Tests

    func testUnknownResourceThrows() async throws {
        try createTestBoard(columns: [], cards: [])

        let params = ReadResource.Parameters(uri: "termq://unknown")

        do {
            _ = try await server.dispatchResourceRead(params)
            XCTFail("Should have thrown for unknown resource")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Unknown resource"))
        }
    }

    func testInvalidURIThrows() async throws {
        try createTestBoard(columns: [], cards: [])

        let params = ReadResource.Parameters(uri: "invalid://resource")

        do {
            _ = try await server.dispatchResourceRead(params)
            XCTFail("Should have thrown for invalid URI")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Unknown resource"))
        }
    }

    // MARK: - Resource URI Tests

    func testResourceURIsInResult() async throws {
        let columnId = UUID()
        try createTestBoard(
            columns: [(columnId, "To Do", 0)],
            cards: [("Card", columnId)]
        )

        // Test each resource has correct URI in result
        let terminalParams = ReadResource.Parameters(uri: "termq://terminals")
        let terminalResult = try await server.dispatchResourceRead(terminalParams)
        XCTAssertEqual(terminalResult.contents[0].uri, "termq://terminals")

        let columnParams = ReadResource.Parameters(uri: "termq://columns")
        let columnResult = try await server.dispatchResourceRead(columnParams)
        XCTAssertEqual(columnResult.contents[0].uri, "termq://columns")

        let pendingParams = ReadResource.Parameters(uri: "termq://pending")
        let pendingResult = try await server.dispatchResourceRead(pendingParams)
        XCTAssertEqual(pendingResult.contents[0].uri, "termq://pending")
    }
}
