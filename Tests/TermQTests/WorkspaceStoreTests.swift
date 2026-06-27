import XCTest

@testable import TermQ

@MainActor
final class WorkspaceStoreTests: XCTestCase {

    private var tempDir: URL!
    private var fileURL: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WorkspaceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("workspaces.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - First launch

    func test_firstLaunch_isEmptyAndAll() {
        let store = WorkspaceStore(fileURL: fileURL)
        XCTAssertTrue(store.workspaces.isEmpty)
        XCTAssertNil(store.activeWorkspaceId)
    }

    // MARK: - CRUD + persistence across relaunch

    func test_create_persistsAcrossRelaunch() {
        let store = WorkspaceStore(fileURL: fileURL)
        let created = store.create(name: "Work")

        let reborn = WorkspaceStore(fileURL: fileURL)
        XCTAssertEqual(reborn.workspaces.map(\.id), [created.id])
        XCTAssertEqual(reborn.workspaces.first?.name, "Work")
    }

    func test_rename_persists() {
        let store = WorkspaceStore(fileURL: fileURL)
        let created = store.create(name: "Wrok")
        store.rename(created.id, to: "Work")

        let reborn = WorkspaceStore(fileURL: fileURL)
        XCTAssertEqual(reborn.workspace(id: created.id)?.name, "Work")
    }

    func test_delete_removesWorkspace() {
        let store = WorkspaceStore(fileURL: fileURL)
        let created = store.create(name: "Temp")
        store.delete(created.id)

        let reborn = WorkspaceStore(fileURL: fileURL)
        XCTAssertTrue(reborn.workspaces.isEmpty)
    }

    // MARK: - Membership

    func test_addAndRemoveRepo_persists() {
        let store = WorkspaceStore(fileURL: fileURL)
        let ws = store.create(name: "Work")
        let repo = UUID()

        store.add(repoId: repo, to: ws.id)
        XCTAssertTrue(store.contains(repoId: repo, in: ws.id))

        let reborn = WorkspaceStore(fileURL: fileURL)
        XCTAssertTrue(reborn.contains(repoId: repo, in: ws.id))

        reborn.remove(repoId: repo, from: ws.id)
        XCTAssertFalse(reborn.contains(repoId: repo, in: ws.id))
    }

    func test_add_deduplicatesRepo() {
        let store = WorkspaceStore(fileURL: fileURL)
        let ws = store.create(name: "Work")
        let repo = UUID()
        store.add(repoId: repo, to: ws.id)
        store.add(repoId: repo, to: ws.id)
        XCTAssertEqual(store.workspace(id: ws.id)?.repoIds, [repo])
    }

    func test_sameRepo_canBelongToMultipleWorkspaces() {
        let store = WorkspaceStore(fileURL: fileURL)
        let work = store.create(name: "Work")
        let personal = store.create(name: "Personal")
        let repo = UUID()
        store.add(repoId: repo, to: work.id)
        store.add(repoId: repo, to: personal.id)
        XCTAssertTrue(store.contains(repoId: repo, in: work.id))
        XCTAssertTrue(store.contains(repoId: repo, in: personal.id))
    }

    func test_removeRepoFromAll_clearsEveryWorkspace() {
        let store = WorkspaceStore(fileURL: fileURL)
        let work = store.create(name: "Work")
        let personal = store.create(name: "Personal")
        let repo = UUID()
        store.add(repoId: repo, to: work.id)
        store.add(repoId: repo, to: personal.id)

        store.removeRepoFromAll(repoId: repo)

        XCTAssertFalse(store.contains(repoId: repo, in: work.id))
        XCTAssertFalse(store.contains(repoId: repo, in: personal.id))
    }

    // MARK: - Active selection

    func test_setActive_persists() {
        let store = WorkspaceStore(fileURL: fileURL)
        let ws = store.create(name: "Work")
        store.setActive(ws.id)

        let reborn = WorkspaceStore(fileURL: fileURL)
        XCTAssertEqual(reborn.activeWorkspaceId, ws.id)
    }

    func test_deletingActiveWorkspace_fallsBackToAll() {
        let store = WorkspaceStore(fileURL: fileURL)
        let ws = store.create(name: "Work")
        store.setActive(ws.id)
        store.delete(ws.id)
        XCTAssertNil(store.activeWorkspaceId)

        let reborn = WorkspaceStore(fileURL: fileURL)
        XCTAssertNil(reborn.activeWorkspaceId)
    }

    func test_load_dropsActiveIdThatNoLongerExists() throws {
        // Hand-write a config whose active id names no workspace (corruption /
        // out-of-band edit). The store must fall back to "All" on load.
        let danglingActive = UUID()
        let config = WorkspaceConfig(
            activeWorkspaceId: danglingActive,
            workspaces: [Workspace(name: "Work")])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(config).write(to: fileURL)

        let store = WorkspaceStore(fileURL: fileURL)
        XCTAssertNil(store.activeWorkspaceId)
        XCTAssertEqual(store.workspaces.count, 1)
    }

    // MARK: - Filtering integration

    func test_visibleRepoIds_appliesActiveSelection() {
        let store = WorkspaceStore(fileURL: fileURL)
        let repoA = UUID()
        let repoB = UUID()
        let ws = store.create(name: "Work")
        store.add(repoId: repoA, to: ws.id)

        // "All" → everything.
        XCTAssertEqual(store.visibleRepoIds(allRepoIds: [repoA, repoB]), [repoA, repoB])

        // Active workspace → only its member.
        store.setActive(ws.id)
        XCTAssertEqual(store.visibleRepoIds(allRepoIds: [repoA, repoB]), [repoA])
    }
}
