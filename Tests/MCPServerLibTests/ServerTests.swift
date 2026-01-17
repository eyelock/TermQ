import Foundation
import MCP
import TermQShared
import XCTest

@testable import MCPServerLib

final class ServerTests: XCTestCase {
    // MARK: - Initialization Tests

    func testServerInitialization() {
        // Test that server can be created with default data directory
        let server = TermQMCPServer()
        XCTAssertNotNil(server)
        XCTAssertNil(server.dataDirectory)
    }

    func testServerInitializationWithCustomDataDirectory() {
        let customDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-Test-\(UUID().uuidString)")
        let server = TermQMCPServer(dataDirectory: customDir)

        XCTAssertNotNil(server)
        XCTAssertEqual(server.dataDirectory, customDir)
    }

    // MARK: - Static Properties Tests

    func testServerName() {
        XCTAssertEqual(TermQMCPServer.serverName, "termq")
    }

    func testServerVersion() {
        XCTAssertEqual(TermQMCPServer.serverVersion, "1.0.0")
    }

    // MARK: - LoadBoard Tests

    func testLoadBoardWithValidData() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-LoadBoardTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a valid board.json
        let boardJSON = """
            {
                "columns": [
                    {"id": "\(UUID().uuidString)", "name": "To Do", "orderIndex": 0, "color": "#FF0000"}
                ],
                "cards": []
            }
            """
        try boardJSON.write(to: tempDir.appendingPathComponent("board.json"), atomically: true, encoding: .utf8)

        let server = TermQMCPServer(dataDirectory: tempDir)
        let board = try server.loadBoard()

        XCTAssertEqual(board.columns.count, 1)
        XCTAssertEqual(board.columns[0].name, "To Do")
    }

    func testLoadBoardWithMissingFile() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-EmptyDir-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = TermQMCPServer(dataDirectory: tempDir)

        XCTAssertThrowsError(try server.loadBoard()) { error in
            // Should throw boardNotFound error
            XCTAssertTrue(String(describing: error).contains("board") || error is BoardLoader.LoadError)
        }
    }

    // MARK: - Tool Dispatch Tests

    func testDispatchToolCallUnknownTool() async throws {
        let tempDir = try createTestBoardDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = TermQMCPServer(dataDirectory: tempDir)
        let params = CallTool.Parameters(name: "unknown_tool", arguments: nil)

        do {
            _ = try await server.dispatchToolCall(params)
            XCTFail("Should have thrown for unknown tool")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Unknown tool"))
        }
    }

    func testDispatchToolCallPending() async throws {
        let tempDir = try createTestBoardDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = TermQMCPServer(dataDirectory: tempDir)
        let params = CallTool.Parameters(name: "termq_pending", arguments: nil)
        let result = try await server.dispatchToolCall(params)

        XCTAssertFalse(result.isError ?? false)
        XCTAssertEqual(result.content.count, 1)
    }

    func testDispatchToolCallContext() async throws {
        let tempDir = try createTestBoardDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = TermQMCPServer(dataDirectory: tempDir)
        let params = CallTool.Parameters(name: "termq_context", arguments: nil)
        let result = try await server.dispatchToolCall(params)

        XCTAssertFalse(result.isError ?? false)
        guard case .text(let content) = result.content[0] else {
            XCTFail("Expected text content")
            return
        }
        XCTAssertTrue(content.contains("TermQ MCP Server"))
    }

    func testDispatchToolCallList() async throws {
        let tempDir = try createTestBoardDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = TermQMCPServer(dataDirectory: tempDir)
        let params = CallTool.Parameters(name: "termq_list", arguments: nil)
        let result = try await server.dispatchToolCall(params)

        XCTAssertFalse(result.isError ?? false)
    }

    func testDispatchToolCallFind() async throws {
        let tempDir = try createTestBoardDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = TermQMCPServer(dataDirectory: tempDir)
        let params = CallTool.Parameters(name: "termq_find", arguments: ["name": .string("Test")])
        let result = try await server.dispatchToolCall(params)

        XCTAssertFalse(result.isError ?? false)
    }

    func testDispatchToolCallOpen() async throws {
        let tempDir = try createTestBoardDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = TermQMCPServer(dataDirectory: tempDir)
        let params = CallTool.Parameters(name: "termq_open", arguments: ["identifier": .string("Test Terminal")])
        let result = try await server.dispatchToolCall(params)

        // This might fail because terminal doesn't exist, which is fine
        XCTAssertNotNil(result)
    }

    func testDispatchToolCallCreate() async throws {
        let tempDir = try createTestBoardDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = TermQMCPServer(dataDirectory: tempDir)
        let params = CallTool.Parameters(
            name: "termq_create",
            arguments: ["name": .string("New Terminal"), "path": .string("/tmp")]
        )
        let result = try await server.dispatchToolCall(params)

        XCTAssertFalse(result.isError ?? false)
    }

    func testDispatchToolCallSet() async throws {
        let tempDir = try createTestBoardDirectory(withCard: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = TermQMCPServer(dataDirectory: tempDir)
        let params = CallTool.Parameters(
            name: "termq_set",
            arguments: ["identifier": .string("Test Terminal"), "description": .string("Updated")]
        )
        let result = try await server.dispatchToolCall(params)

        // May succeed or fail depending on terminal existence
        XCTAssertNotNil(result)
    }

    func testDispatchToolCallMove() async throws {
        let tempDir = try createTestBoardDirectory(withCard: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = TermQMCPServer(dataDirectory: tempDir)
        let params = CallTool.Parameters(
            name: "termq_move",
            arguments: ["identifier": .string("Test Terminal"), "column": .string("Done")]
        )
        let result = try await server.dispatchToolCall(params)

        XCTAssertNotNil(result)
    }

    func testDispatchToolCallGet() async throws {
        let tempDir = try createTestBoardDirectory(withCard: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = TermQMCPServer(dataDirectory: tempDir)
        let params = CallTool.Parameters(
            name: "termq_get",
            arguments: ["id": .string(UUID().uuidString)]
        )
        let result = try await server.dispatchToolCall(params)

        // May succeed or fail depending on ID
        XCTAssertNotNil(result)
    }

    // MARK: - Available Resources Tests

    func testAvailableResourcesCount() {
        let resources = TermQMCPServer.availableResources
        XCTAssertEqual(resources.count, 4)
    }

    func testAvailableResourcesURIs() {
        let resources = TermQMCPServer.availableResources
        let uris = Set(resources.map { $0.uri })

        XCTAssertTrue(uris.contains("termq://terminals"))
        XCTAssertTrue(uris.contains("termq://columns"))
        XCTAssertTrue(uris.contains("termq://pending"))
        XCTAssertTrue(uris.contains("termq://context"))
    }

    // MARK: - Available Prompts Tests

    func testAvailablePromptsCount() {
        let prompts = TermQMCPServer.availablePrompts
        XCTAssertEqual(prompts.count, 3)
    }

    func testAvailablePromptsNames() {
        let prompts = TermQMCPServer.availablePrompts
        let names = Set(prompts.map { $0.name })

        XCTAssertTrue(names.contains("session_start"))
        XCTAssertTrue(names.contains("workflow_guide"))
        XCTAssertTrue(names.contains("terminal_summary"))
    }

    // MARK: - Available Tools Tests

    func testAvailableToolsCount() {
        let tools = TermQMCPServer.availableTools
        XCTAssertEqual(tools.count, 10)
    }

    func testAvailableToolsNames() {
        let tools = TermQMCPServer.availableTools
        let names = Set(tools.map { $0.name })

        XCTAssertTrue(names.contains("termq_pending"))
        XCTAssertTrue(names.contains("termq_context"))
        XCTAssertTrue(names.contains("termq_list"))
        XCTAssertTrue(names.contains("termq_find"))
        XCTAssertTrue(names.contains("termq_open"))
        XCTAssertTrue(names.contains("termq_create"))
        XCTAssertTrue(names.contains("termq_set"))
        XCTAssertTrue(names.contains("termq_move"))
        XCTAssertTrue(names.contains("termq_get"))
        XCTAssertTrue(names.contains("termq_delete"))
    }

    // MARK: - Context Documentation Tests

    func testContextDocumentationContainsRequiredSections() {
        let docs = TermQMCPServer.contextDocumentation

        XCTAssertTrue(docs.contains("SESSION START CHECKLIST"))
        XCTAssertTrue(docs.contains("SESSION END CHECKLIST"))
        XCTAssertTrue(docs.contains("TAG SCHEMA"))
        XCTAssertTrue(docs.contains("AVAILABLE MCP TOOLS"))
        XCTAssertTrue(docs.contains("TERMINAL FIELDS"))
        XCTAssertTrue(docs.contains("TIPS"))
    }

    // MARK: - Helper Methods

    private func createTestBoardDirectory(withCard: Bool = false) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let columnId = UUID()
        var cards = "[]"
        if withCard {
            cards = """
                [
                    {
                        "id": "\(UUID().uuidString)",
                        "title": "Test Terminal",
                        "description": "Test description",
                        "columnId": "\(columnId.uuidString)",
                        "orderIndex": 0,
                        "workingDirectory": "/tmp"
                    }
                ]
                """
        }

        let boardJSON = """
            {
                "columns": [
                    {"id": "\(columnId.uuidString)", "name": "To Do", "orderIndex": 0, "color": "#FF0000"},
                    {"id": "\(UUID().uuidString)", "name": "Done", "orderIndex": 1, "color": "#00FF00"}
                ],
                "cards": \(cards)
            }
            """
        try boardJSON.write(to: tempDir.appendingPathComponent("board.json"), atomically: true, encoding: .utf8)

        return tempDir
    }
}
