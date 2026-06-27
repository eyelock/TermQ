import Foundation
import XCTest

@testable import TermQShared

/// Single-board workspace model: every card lives in one `board.json` and carries a
/// `workspaceId` tag. These cover the pure filter (`Board.cardsInWorkspace`), the
/// `Card` round-trip of the new field, and `BoardWriter.createCard` stamping — the
/// path the CLI and MCP server create cards through.
final class WorkspaceCardFilterTests: XCTestCase {
    private let wsA = UUID()
    private let wsB = UUID()

    private func card(_ title: String, workspace: UUID?) -> Card {
        Card(title: title, columnId: UUID(), workspaceId: workspace)
    }

    // MARK: - cardsInWorkspace filter

    func testFilter_nilOrEmptyWorkspace_returnsEverything() {
        let cards = [card("a", workspace: wsA), card("b", workspace: nil)]
        XCTAssertEqual(Board.cardsInWorkspace(cards, workspaceId: nil).map(\.title), ["a", "b"])
        XCTAssertEqual(Board.cardsInWorkspace(cards, workspaceId: "").map(\.title), ["a", "b"])
    }

    func testFilter_pinnedWorkspace_returnsOnlyItsCards() {
        let cards = [
            card("a", workspace: wsA),
            card("b", workspace: wsB),
            card("unassigned", workspace: nil),
        ]
        // wsB and unassigned are hidden from a consumer pinned to wsA.
        XCTAssertEqual(Board.cardsInWorkspace(cards, workspaceId: wsA.uuidString).map(\.title), ["a"])
    }

    func testFilter_unknownWorkspace_returnsEmpty() {
        let cards = [card("a", workspace: wsA)]
        XCTAssertTrue(Board.cardsInWorkspace(cards, workspaceId: UUID().uuidString).isEmpty)
    }

    func testFilter_invalidUuidString_returnsEverything() {
        // A non-UUID workspace value can't match any card; treat as "All" (don't hide everything).
        let cards = [card("a", workspace: wsA)]
        XCTAssertEqual(Board.cardsInWorkspace(cards, workspaceId: "not-a-uuid").map(\.title), ["a"])
    }

    // MARK: - Card round-trip

    func testCard_roundTripsWorkspaceId() throws {
        let decoded = try JSONDecoder().decode(
            Card.self, from: JSONEncoder().encode(card("x", workspace: wsA)))
        XCTAssertEqual(decoded.workspaceId, wsA)
    }

    func testCard_absentWorkspaceId_decodesAsNil() throws {
        // A pre-workspace board.json card simply has no workspaceId key.
        let dict: [String: Any] = [
            "id": UUID().uuidString,
            "title": "legacy",
            "columnId": UUID().uuidString,
        ]
        let decoded = try JSONDecoder().decode(
            Card.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertNil(decoded.workspaceId)
    }

    // MARK: - createCard stamping (the path CLI + MCP create through)

    func testCreateCard_stampsWorkspaceId() throws {
        let dir = try makeTempBoard()
        let created = try BoardWriter.createCard(
            name: "c", columnName: "To Do", workingDirectory: "/tmp",
            workspaceId: wsA.uuidString, dataDirectory: dir)
        XCTAssertEqual(created.workspaceId, wsA)
    }

    func testCreateCard_withoutWorkspace_isUnassigned() throws {
        let dir = try makeTempBoard()
        let created = try BoardWriter.createCard(
            name: "c", columnName: "To Do", workingDirectory: "/tmp", dataDirectory: dir)
        XCTAssertNil(created.workspaceId)
    }

    private func makeTempBoard() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-WSFilter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let board = Board(columns: [Column(id: UUID(), name: "To Do", orderIndex: 0)], cards: [])
        try JSONEncoder().encode(board).write(to: dir.appendingPathComponent("board.json"))
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
}
