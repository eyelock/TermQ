import XCTest

@testable import TermQ

final class WorkspaceTests: XCTestCase {

    // MARK: - Workspace Codable round-trip

    func test_workspace_codableRoundTrip() throws {
        let original = Workspace(
            id: UUID(),
            name: "Work",
            repoIds: [UUID(), UUID()],
            addedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(Workspace.self, from: encoder.encode(original))

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.repoIds, original.repoIds)
        XCTAssertEqual(
            decoded.addedAt.timeIntervalSince1970,
            original.addedAt.timeIntervalSince1970,
            accuracy: 1)
    }

    func test_workspace_defaultsToEmptyMembership() {
        let workspace = Workspace(name: "Empty")
        XCTAssertTrue(workspace.repoIds.isEmpty)
    }

    // MARK: - WorkspaceConfig Codable round-trip

    func test_config_empty_roundTrip() throws {
        let decoded = try JSONDecoder().decode(
            WorkspaceConfig.self, from: JSONEncoder().encode(WorkspaceConfig()))
        XCTAssertNil(decoded.activeWorkspaceId)
        XCTAssertTrue(decoded.workspaces.isEmpty)
    }

    func test_config_withActiveAndWorkspaces_roundTrip() throws {
        let active = UUID()
        let original = WorkspaceConfig(
            activeWorkspaceId: active,
            workspaces: [
                Workspace(id: active, name: "Work", repoIds: [UUID()]),
                Workspace(name: "Personal"),
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(WorkspaceConfig.self, from: encoder.encode(original))

        XCTAssertEqual(decoded.activeWorkspaceId, active)
        XCTAssertEqual(decoded.workspaces.count, 2)
        XCTAssertEqual(decoded.workspaces[0].name, "Work")
        XCTAssertEqual(decoded.workspaces[1].name, "Personal")
    }
}
