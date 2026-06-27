import Foundation
import XCTest

@testable import TermQCore

/// `TerminalCard` carries a `workspaceId` (the per-card workspace tag used to filter
/// the board display). It has custom Codable, so verify the new field round-trips
/// and that legacy cards (no key) decode as unassigned (`nil`).
final class TerminalCardWorkspaceTests: XCTestCase {
    func testRoundTripsWorkspaceId() throws {
        let ws = UUID()
        let card = TerminalCard(columnId: UUID(), workspaceId: ws)
        let decoded = try JSONDecoder().decode(TerminalCard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(decoded.workspaceId, ws)
    }

    func testAbsentWorkspaceId_decodesAsNil() throws {
        // A card persisted before workspaces existed has no workspaceId key.
        let dict: [String: Any] = [
            "id": UUID().uuidString,
            "title": "legacy",
            "description": "",
            "tags": [[String: Any]](),
            "columnId": UUID().uuidString,
            "orderIndex": 0,
            "shellPath": "/bin/zsh",
            "workingDirectory": "/tmp",
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(TerminalCard.self, from: data)
        XCTAssertNil(decoded.workspaceId)
    }
}
