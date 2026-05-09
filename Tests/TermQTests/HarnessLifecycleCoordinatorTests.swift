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

    func testHandleTransientSessionExit_trackedUninstallCard_returnsSuccess() {
        let coord = makeCoordinator()
        let cardId = UUID()
        coord.uninstallCardIDs[cardId] = "foo"

        let shouldClose = coord.handleTransientSessionExit(cardId: cardId, succeeded: false)

        XCTAssertEqual(shouldClose, false)
        XCTAssertNil(coord.uninstallCardIDs[cardId])
    }
}
