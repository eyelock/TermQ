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
        XCTAssertTrue(coord.uninstallCardNames.isEmpty)
        XCTAssertNil(coord.harnessNameToFork)
        XCTAssertFalse(coord.showForkSheet)
        XCTAssertNil(coord.harnessNameToUpdate)
        XCTAssertFalse(coord.showUpdateSheet)
        XCTAssertFalse(coord.showInstallSheet)
    }

    // MARK: - Fork

    func testForkHarness_setsSheetState() {
        let coord = makeCoordinator()
        coord.forkHarness(name: "foo")
        XCTAssertEqual(coord.harnessNameToFork, "foo")
        XCTAssertTrue(coord.showForkSheet)
    }

    func testHandleForkCompleted_clearsForkSheetState() {
        let coord = makeCoordinator()
        coord.forkHarness(name: "foo")

        coord.handleForkCompleted(newName: "foo-fork")

        XCTAssertFalse(coord.showForkSheet)
        XCTAssertNil(coord.harnessNameToFork)
    }

    // MARK: - Update sheet

    func testUpdateHarness_whenDetectorNotReady_isNoop() {
        // Coordinator's detector is `.missing`; `.ready` guard fails.
        let coord = makeCoordinator()
        coord.updateHarness(name: "foo")
        XCTAssertNil(coord.harnessNameToUpdate)
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
        coord.uninstallCardNames[cardId] = "foo"

        let shouldClose = coord.handleTransientSessionExit(cardId: cardId, succeeded: false)

        XCTAssertEqual(shouldClose, false)
        XCTAssertNil(coord.uninstallCardNames[cardId])
    }
}
