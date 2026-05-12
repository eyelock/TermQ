import TermQShared
import XCTest

@testable import TermQ

@MainActor
final class HarnessLifecycleCoordinatorTests: XCTestCase {

    fileprivate static let testPaths = YNHPaths(
        home: "/tmp/ynh-home",
        config: "/tmp/ynh-home/config",
        harnesses: "/tmp/ynh-home/harnesses",
        symlinks: "/tmp/ynh-home/symlinks",
        cache: "/tmp/ynh-home/cache",
        run: "/tmp/ynh-home/run",
        bin: "/tmp/ynh-home/bin"
    )

    private func makeCoordinator(
        detector: MockYNHDetector = MockYNHDetector(status: .missing)
    )
        -> HarnessLifecycleCoordinator
    {
        let repo = HarnessRepository(ynhDetector: detector)
        let tempBoardURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarnessLifecycleCoordTests-\(UUID().uuidString).json")
        let bvm = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        return HarnessLifecycleCoordinator(
            ynhDetector: detector,
            harnessRepo: repo,
            boardViewModel: bvm,
            ynhPersistence: YNHPersistence.shared
        )
    }

    // MARK: - Initial state

    func testInit_hasHiddenSheets() {
        let coord = makeCoordinator()
        XCTAssertNil(coord.harnessIDToFork)
        XCTAssertFalse(coord.showForkSheet)
        XCTAssertNil(coord.harnessIDToUpdate)
        XCTAssertFalse(coord.showUpdateSheet)
        XCTAssertFalse(coord.showInstallSheet)
        XCTAssertNil(coord.harnessConfigToInstall)
        XCTAssertFalse(coord.showInstallProgressSheet)
        XCTAssertNil(coord.harnessIDToUninstall)
        XCTAssertFalse(coord.showUninstallSheet)
        XCTAssertNil(coord.pendingExport)
        XCTAssertFalse(coord.showExportSheet)
    }

    // MARK: - Fork

    func testForkHarness_setsSheetState() {
        let coord = makeCoordinator()
        coord.forkHarness(id: "foo")
        XCTAssertEqual(coord.harnessIDToFork, "foo")
        XCTAssertTrue(coord.showForkSheet)
    }

    func testHandleForkCompleted_clearsForkSheetState() {
        let coord = makeCoordinator()
        coord.forkHarness(id: "foo")

        coord.handleForkCompleted(newID: "foo-fork")

        XCTAssertFalse(coord.showForkSheet)
        XCTAssertNil(coord.harnessIDToFork)
    }

    // MARK: - Update sheet

    func testUpdateHarness_whenDetectorNotReady_isNoop() {
        let coord = makeCoordinator()
        coord.updateHarness(id: "foo")
        XCTAssertNil(coord.harnessIDToUpdate)
        XCTAssertFalse(coord.showUpdateSheet)
    }

    // MARK: - Install sheet

    func testInstallHarness_whenDetectorNotReady_isNoop() {
        let coord = makeCoordinator()
        coord.installHarness(HarnessInstallConfig(displayName: "foo", installArgs: ["foo"]))
        XCTAssertNil(coord.harnessConfigToInstall)
        XCTAssertFalse(coord.showInstallProgressSheet)
    }

    func testInstallHarness_whenDetectorReady_setsSheetState() {
        let detector = MockYNHDetector(
            status: .ready(
                ynhPath: "/usr/local/bin/ynh", yndPath: nil, paths: Self.testPaths))
        let coord = makeCoordinator(detector: detector)

        coord.installHarness(HarnessInstallConfig(displayName: "foo", installArgs: ["foo"]))

        XCTAssertEqual(coord.harnessConfigToInstall?.displayName, "foo")
        XCTAssertTrue(coord.showInstallProgressSheet)
    }

    // MARK: - Uninstall sheet

    func testUninstallHarness_whenDetectorNotReady_isNoop() {
        let coord = makeCoordinator()
        coord.uninstallHarness(id: "registry/foo")
        XCTAssertNil(coord.harnessIDToUninstall)
        XCTAssertFalse(coord.showUninstallSheet)
    }

    func testUninstallHarness_whenDetectorReady_setsSheetState() {
        let detector = MockYNHDetector(
            status: .ready(
                ynhPath: "/usr/local/bin/ynh", yndPath: nil, paths: Self.testPaths))
        let coord = makeCoordinator(detector: detector)

        coord.uninstallHarness(id: "registry/foo")

        XCTAssertEqual(coord.harnessIDToUninstall, "registry/foo")
        XCTAssertTrue(coord.showUninstallSheet)
    }
}
