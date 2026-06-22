import Foundation
import TermQShared
import XCTest

@testable import MCPServerLib

/// Workspace pinning at the MCP handler level. A server constructed with a
/// `workspaceId` must filter its read ops (list/pending) to that workspace's cards;
/// a server with no workspace ("All") sees every card. All cards live in one
/// `board.json` — pinning is the per-card `workspaceId`, resolved from
/// `TERMQ_WORKSPACE_ID` at startup.
final class ToolHandlersWorkspaceFilterTests: XCTestCase {
    private var tempDirectory: URL!
    private let columnId = UUID()
    private let wsA = UUID()
    private let wsB = UUID()

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-ToolHandlersWS-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        // Three cards in one board: wsA, wsB, and one unassigned.
        let board: [String: Any] = [
            "columns": [["id": columnId.uuidString, "name": "To Do", "orderIndex": 0]],
            "cards": [
                cardDict(title: "a", workspace: wsA),
                cardDict(title: "b", workspace: wsB),
                cardDict(title: "loose", workspace: nil),
            ],
        ]
        try JSONSerialization.data(withJSONObject: board)
            .write(to: tempDirectory.appendingPathComponent("board.json"))
    }

    override func tearDownWithError() throws {
        if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
    }

    private func cardDict(title: String, workspace: UUID?) -> [String: Any] {
        var d: [String: Any] = [
            "id": UUID().uuidString,
            "title": title,
            "description": "",
            "columnId": columnId.uuidString,
            "orderIndex": 0,
            "workingDirectory": "/tmp",
        ]
        if let workspace { d["workspaceId"] = workspace.uuidString }
        return d
    }

    private func server(workspace: UUID?) -> TermQMCPServer {
        TermQMCPServer(dataDirectory: tempDirectory, workspaceId: workspace?.uuidString)
    }

    private func listNames(_ server: TermQMCPServer) async throws -> [String] {
        let result = try await server.handleList(nil)
        guard case .text(let json, _, _) = result.content[0] else {
            XCTFail("expected text content")
            return []
        }
        return try JSONDecoder()
            .decode(TerminalListEnvelope.self, from: Data(json.utf8))
            .items.map(\.name).sorted()
    }

    func testList_pinnedToWorkspace_showsOnlyItsCards() async throws {
        let names = try await listNames(server(workspace: wsA))
        XCTAssertEqual(names, ["a"])  // wsB + unassigned hidden
    }

    func testList_unpinned_showsEverything() async throws {
        let names = try await listNames(server(workspace: nil))
        XCTAssertEqual(names, ["a", "b", "loose"])
    }

    func testPending_pinnedToWorkspace_showsOnlyItsCards() async throws {
        let result = try await server(workspace: wsB).handlePending(nil)
        guard case .text(let json, _, _) = result.content[0] else {
            return XCTFail("expected text content")
        }
        let output = try JSONDecoder().decode(PendingOutput.self, from: Data(json.utf8))
        XCTAssertEqual(output.terminals.map(\.name).sorted(), ["b"])
    }
}
