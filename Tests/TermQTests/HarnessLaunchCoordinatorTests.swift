import TermQShared
import XCTest

@testable import TermQ

@MainActor
final class HarnessLaunchCoordinatorTests: XCTestCase {

    private func makeCoordinator(
        harnessRepo: HarnessRepository? = nil
    ) -> (HarnessLaunchCoordinator, HarnessRepository, BoardViewModel) {
        let repo = harnessRepo ?? HarnessRepository(ynhDetector: MockYNHDetector(status: .missing))
        let tempBoardURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarnessLaunchCoordTests-\(UUID().uuidString).json")
        let bvm = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        let coord = HarnessLaunchCoordinator(
            harnessRepo: repo,
            vendorService: VendorService(ynhDetector: MockYNHDetector(status: .missing)),
            boardViewModel: bvm,
            ynhPersistence: YNHPersistence.shared
        )
        return (coord, repo, bvm)
    }

    // MARK: - Initial state

    func testInit_hasEmptyState() {
        let (coord, _, _) = makeCoordinator()
        XCTAssertNil(coord.pendingLaunch)
        XCTAssertNil(coord.launchSheetTarget)
        XCTAssertNil(coord.launchWorkingDirectory)
        XCTAssertNil(coord.launchWorktreeBranch)
        XCTAssertNil(coord.cardBeforeHarness)
    }

    // MARK: - Pending launch lifecycle

    func testRequestLaunch_repoUnloaded_holdsPendingDoesNotPresent() {
        let (coord, _, _) = makeCoordinator()
        coord.requestLaunch(harnessId: "ns/foo", workingDirectory: "/tmp", branch: "main")
        XCTAssertNotNil(coord.pendingLaunch)
        XCTAssertEqual(coord.pendingLaunch?.harnessId, "ns/foo")
        XCTAssertEqual(coord.launchWorkingDirectory, "/tmp")
        XCTAssertEqual(coord.launchWorktreeBranch, "main")
        // Sheet stays nil because repo isn't .loaded yet — this is the
        // white-pill bug fix: presentation is gated on actual data.
        XCTAssertNil(coord.launchSheetTarget)
    }

    func testTryResolvePendingLaunch_repoLoadedWithMatch_resolvesSheetTarget() async {
        let detector = MockYNHDetector(status: .missing)
        let repo = HarnessRepository(ynhDetector: detector)
        // refresh() with .missing status puts repo into .loaded([])
        await repo.refresh()
        XCTAssertTrue(repo.listState.isLoaded)

        let (coord, _, _) = makeCoordinator(harnessRepo: repo)
        coord.requestLaunch(harnessId: "ns/foo", workingDirectory: nil, branch: nil)
        // Repo loaded but harness not in the empty list — pending should
        // drop silently, target remains nil.
        XCTAssertNil(coord.pendingLaunch)
        XCTAssertNil(coord.launchSheetTarget)
    }

    func testDismissLaunchSheet_clearsAllRelatedState() {
        let (coord, _, _) = makeCoordinator()
        coord.requestLaunch(harnessId: "ns/foo", workingDirectory: "/tmp", branch: "main")
        coord.dismissLaunchSheet()
        XCTAssertNil(coord.pendingLaunch)
        XCTAssertNil(coord.launchWorkingDirectory)
        XCTAssertNil(coord.launchWorktreeBranch)
    }

    // MARK: - Detail navigation lifecycle

    func testCaptureCardBeforeHarness_capturesSelectedCard() {
        let (coord, _, bvm) = makeCoordinator()
        let column = bvm.board.columns.first ?? bvm.board.addColumn(name: "Test")
        let card = bvm.board.addCard(to: column, title: "Tab")
        bvm.selectedCard = card

        coord.captureCardBeforeHarness()
        XCTAssertEqual(coord.cardBeforeHarness?.id, card.id)
    }

    func testClearAllSelection_clearsCardBeforeAndRepoSelection() {
        let (coord, repo, bvm) = makeCoordinator()
        let column = bvm.board.columns.first ?? bvm.board.addColumn(name: "Test")
        let card = bvm.board.addCard(to: column, title: "Tab")
        coord.cardBeforeHarness = card
        repo.selectedHarnessId = "ns/foo"

        coord.clearAllSelection()

        XCTAssertNil(coord.cardBeforeHarness)
        XCTAssertNil(repo.selectedHarnessId)
    }
}
