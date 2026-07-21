import Foundation
import TermQShared
import XCTest

@testable import MCPServerLib

/// Single-board workspace pinning: `HeadlessWriter.createCard` stamps the new card
/// with the caller's workspace so the app/CLI/MCP filter it into that workspace's
/// view. All cards live in one `board.json`; pinning is the `workspaceId` field, not
/// a separate file.
final class HeadlessWriterWorkspaceTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-HeadlessWorkspaceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let board = Board(columns: [Column(id: UUID(), name: "To Do", orderIndex: 0)], cards: [])
        try JSONEncoder().encode(board).write(to: tempDir.appendingPathComponent("board.json"))
        tempDirectory = tempDir
    }

    override func tearDownWithError() throws {
        if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
    }

    func testCreateCard_stampsWorkspaceId() throws {
        let ws = UUID()
        let card = try HeadlessWriter.createCard(
            HeadlessWriter.CardCreationOptions(
                workingDirectory: "/tmp", name: "ws-card", column: "To Do"),
            workspaceId: ws.uuidString, dataDirectory: tempDirectory)
        XCTAssertEqual(card.workspaceId, ws)

        // The persisted card carries the workspace too.
        let reloaded = try BoardLoader.loadBoard(dataDirectory: tempDirectory).activeCards
        XCTAssertEqual(reloaded.map(\.workspaceId), [ws])
    }

    func testCreateCard_withoutWorkspace_isUnassigned() throws {
        let card = try HeadlessWriter.createCard(
            HeadlessWriter.CardCreationOptions(
                workingDirectory: "/tmp", name: "default-card", column: "To Do"),
            dataDirectory: tempDirectory)
        XCTAssertNil(card.workspaceId)
    }
}
