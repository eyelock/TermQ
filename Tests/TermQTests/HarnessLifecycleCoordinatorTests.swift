import TermQShared
import XCTest

@testable import TermQ

@MainActor
final class HarnessLifecycleCoordinatorTests: XCTestCase {

    private func makeCoordinator() -> HarnessLifecycleCoordinator {
        let detector = MockYNHDetector(status: .missing)
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

    func testInit_hasEmptyTrackingSetsAndHiddenSheets() {
        let coord = makeCoordinator()
        XCTAssertTrue(coord.installCardIDs.isEmpty)
        XCTAssertTrue(coord.uninstallCardIDs.isEmpty)
        XCTAssertNil(coord.harnessIDToFork)
        XCTAssertFalse(coord.showForkSheet)
        XCTAssertNil(coord.harnessIDToUpdate)
        XCTAssertFalse(coord.showUpdateSheet)
        XCTAssertFalse(coord.showInstallSheet)
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
        // Coordinator's detector is `.missing`; `.ready` guard fails.
        let coord = makeCoordinator()
        coord.updateHarness(id: "foo")
        XCTAssertNil(coord.harnessIDToUpdate)
        XCTAssertFalse(coord.showUpdateSheet)
    }

    // MARK: - Transient session exit handling

    func testHandleTransientSessionExit_unknownCardId_returnsNil() {
        let coord = makeCoordinator()
        let result = coord.handleTransientSessionExit(cardId: UUID(), succeeded: true)
        XCTAssertNil(result, "Coordinator should not claim cards it didn't track")
    }

    func testHandleTransientSessionExit_trackedInstallCard_returnsSuccess() {
        let coord = makeCoordinator()
        let cardId = UUID()
        coord.installCardIDs.insert(cardId)

        let shouldClose = coord.handleTransientSessionExit(cardId: cardId, succeeded: true)

        XCTAssertEqual(shouldClose, true)
        XCTAssertFalse(
            coord.installCardIDs.contains(cardId),
            "Tracked id should be removed from the set after handling")
    }

    // MARK: - Delete (uninstall + remove on-disk source)

    func testDeleteLocalHarness_whenDetectorNotReady_andHarnessIsTracked_isNoop() {
        // Detector is `.missing`; the YNH-managed branch's `.ready` guard
        // fails, so no transient card is added. We can't easily inject
        // an in-repo harness without a stubbed command runner, but the
        // guard exits cleanly without crashing — that's the contract
        // exercised here.
        let coord = makeCoordinator()
        coord.deleteLocalHarness(id: "nonexistent-id")
        XCTAssertTrue(coord.uninstallCardIDs.isEmpty)
    }

    func testDeleteLocalHarness_whenHarnessNotInRepo_isSafeNoop() {
        // The untracked branch (`installedFrom == nil`) requires the
        // harness to exist in the repo. When the id doesn't match
        // anything, the method should fall through to the `.ready`
        // guard and exit without effect — no crash, no side effect.
        let coord = makeCoordinator()
        coord.deleteLocalHarness(id: "nope")
        XCTAssertTrue(coord.uninstallCardIDs.isEmpty)
    }

    func testBuildDeleteLocalCommand_chainsUninstallThenRm() {
        // Both halves must appear and be ordered: uninstall first,
        // rm -rf second, gated by `&&`. The `exit` at the tail closes
        // the transient terminal once both succeed.
        let cmd = HarnessLifecycleCoordinator.buildDeleteLocalCommand(
            ynhPath: "/usr/local/bin/ynh",
            id: "local/my-fork",
            pathToRemove: "/Users/test/forks/my-fork"
        )
        XCTAssertEqual(
            cmd,
            "/usr/local/bin/ynh uninstall 'local/my-fork' "
                + "&& rm -rf '/Users/test/forks/my-fork' && exit"
        )
    }

    func testBuildDeleteLocalCommand_quotesPathsContainingSpacesOrQuotes() {
        // A path with a space must remain a single shell argument; a path
        // with a single quote must escape correctly. Both are common on
        // macOS user directories.
        let cmd = HarnessLifecycleCoordinator.buildDeleteLocalCommand(
            ynhPath: "/usr/local/bin/ynh",
            id: "local/x",
            pathToRemove: "/Users/test/My Forks/it's-mine"
        )
        XCTAssertTrue(cmd.contains(#"'/Users/test/My Forks/it'\''s-mine'"#))
        XCTAssertTrue(cmd.contains("&& rm -rf"))
        XCTAssertTrue(cmd.contains("&& exit"))
    }

    // MARK: - Transient session exit handling

    func testHandleTransientSessionExit_trackedUninstallCard_returnsSuccess() {
        let coord = makeCoordinator()
        let cardId = UUID()
        coord.uninstallCardIDs[cardId] = "foo"

        let shouldClose = coord.handleTransientSessionExit(cardId: cardId, succeeded: false)

        XCTAssertEqual(shouldClose, false)
        XCTAssertNil(coord.uninstallCardIDs[cardId])
    }
}
