import TermQCore
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

    // MARK: - Reuse-in-place (existing card)

    private func launchConfig(focus: String?, branch: String?) -> HarnessLaunchConfig {
        HarnessLaunchConfig(
            harnessID: "new/h", vendorID: "", defaultVendor: "",
            focus: focus, profile: nil,
            workingDirectory: "/r/wt", prompt: nil, instructions: nil,
            backend: .direct, branch: branch, interactive: false, cardTitle: nil)
    }

    func testRewriteCardLaunch_swapsLaunchTags_preservingIdentityTags() {
        let (coord, _, bvm) = makeCoordinator()
        let column = bvm.board.columns.first ?? bvm.board.addColumn(name: "Test")
        let card = bvm.board.addCard(to: column, title: "Tab")
        card.workingDirectory = "/r/wt"
        // Stale launch tags + identity tags that must survive the rewrite.
        card.tags = [
            TermQCore.Tag(key: "source", value: "harness"),
            TermQCore.Tag(key: "harness", value: "old/h"),
            TermQCore.Tag(key: "focus", value: "stale"),
            TermQCore.Tag(key: "backend", value: "pty"),
            TermQCore.Tag(key: "shell", value: "zsh"),
            TermQCore.Tag(key: "session", value: "termq-keepme"),
            TermQCore.Tag(key: "window", value: "0"),
            TermQCore.Tag(key: "repository", value: "eyelock/collective"),
        ]
        card.initCommand = "ynh run old/h --focus stale"

        coord.rewriteCardLaunch(card, config: launchConfig(focus: "review", branch: "feat/y"))

        let dict = Dictionary(card.tags.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(dict["harness"], "new/h", "harness tag is swapped to the new launch")
        XCTAssertEqual(dict["focus"], "review")
        XCTAssertEqual(dict["branch"], "feat/y")
        // Identity tags preserved verbatim.
        XCTAssertEqual(dict["backend"], "pty")
        XCTAssertEqual(dict["shell"], "zsh")
        XCTAssertEqual(dict["session"], "termq-keepme")
        XCTAssertEqual(dict["window"], "0")
        XCTAssertEqual(dict["repository"], "eyelock/collective", "repo association survives a relaunch")
        // Init command rebuilt for the new launch, bound to the card's session.
        XCTAssertTrue(card.initCommand.contains("ynh run new/h"), card.initCommand)
        XCTAssertTrue(card.initCommand.contains("--focus review"), card.initCommand)
        XCTAssertTrue(
            card.initCommand.contains("--session-name \(card.tmuxSessionName)"), card.initCommand)
        XCTAssertFalse(card.initCommand.contains("old/h"))
        XCTAssertTrue(card.allowAutorun)
    }

    func testRewriteCardLaunch_noFocus_omitsFocusFlagAndTag() {
        let (coord, _, bvm) = makeCoordinator()
        let column = bvm.board.columns.first ?? bvm.board.addColumn(name: "Test")
        let card = bvm.board.addCard(to: column, title: "Tab")
        card.workingDirectory = "/r/wt"

        coord.rewriteCardLaunch(card, config: launchConfig(focus: nil, branch: nil))

        XCTAssertFalse(card.tags.contains { $0.key == "focus" })
        XCTAssertFalse(card.initCommand.contains("--focus"), card.initCommand)
        XCTAssertTrue(card.initCommand.contains("ynh run new/h"), card.initCommand)
    }
}
