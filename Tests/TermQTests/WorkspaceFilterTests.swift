import XCTest

@testable import TermQ

final class WorkspaceFilterTests: XCTestCase {

    private let repoA = UUID()
    private let repoB = UUID()
    private let repoC = UUID()

    private var allRepoIds: [UUID] { [repoA, repoB, repoC] }

    func test_nilActive_showsAllReposInOrder() {
        let result = WorkspaceFilter.visibleRepoIds(
            active: nil, in: [], allRepoIds: allRepoIds)
        XCTAssertEqual(result, allRepoIds)
    }

    func test_activeWorkspace_showsOnlyItsMembers_inAllReposOrder() {
        // Members listed out of order — result must follow allRepoIds order.
        let workspace = Workspace(id: UUID(), name: "W", repoIds: [repoC, repoA])
        let result = WorkspaceFilter.visibleRepoIds(
            active: workspace.id, in: [workspace], allRepoIds: allRepoIds)
        XCTAssertEqual(result, [repoA, repoC])
    }

    func test_emptyWorkspace_showsNothing() {
        let workspace = Workspace(id: UUID(), name: "Empty", repoIds: [])
        let result = WorkspaceFilter.visibleRepoIds(
            active: workspace.id, in: [workspace], allRepoIds: allRepoIds)
        XCTAssertTrue(result.isEmpty)
    }

    func test_staleMemberId_isIgnored() {
        // Workspace references a repo that no longer exists in allRepoIds.
        let workspace = Workspace(id: UUID(), name: "W", repoIds: [repoA, UUID()])
        let result = WorkspaceFilter.visibleRepoIds(
            active: workspace.id, in: [workspace], allRepoIds: allRepoIds)
        XCTAssertEqual(result, [repoA])
    }

    func test_unknownActiveId_fallsBackToAll() {
        // Active id does not match any workspace (e.g. a deleted workspace).
        let result = WorkspaceFilter.visibleRepoIds(
            active: UUID(), in: [], allRepoIds: allRepoIds)
        XCTAssertEqual(result, allRepoIds)
    }
}
