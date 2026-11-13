import Foundation
import XCTest

@testable import TermQ
@testable import TermQCore

/// Workspace filtering + new-card stamping in the board view model. The
/// active-workspace source is injected (`activeWorkspaceProvider`) so these exercise
/// the real `displayedCards` filter and the `addTerminal` stamp path without mutating
/// the shared `WorkspaceStore` singleton (which would write to the real data dir).
@MainActor
final class BoardViewModelWorkspaceFilterTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BVMWSFilter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeVM() -> BoardViewModel {
        BoardViewModel(
            persistence: BoardPersistence(saveURL: tempDir.appendingPathComponent("board.json")))
    }

    // MARK: - Pure filter

    func test_cardsInWorkspace_allShowsEverything() {
        let col = UUID()
        let tagged = TerminalCard(columnId: col, workspaceId: UUID())
        let loose = TerminalCard(columnId: col)
        XCTAssertEqual(
            BoardViewModel.cardsInWorkspace([tagged, loose], active: nil).map(\.id),
            [tagged.id, loose.id])
    }

    func test_cardsInWorkspace_workspaceHidesOthersAndUnassigned() {
        let col = UUID()
        let ws = UUID()
        let mine = TerminalCard(columnId: col, workspaceId: ws)
        let other = TerminalCard(columnId: col, workspaceId: UUID())
        let loose = TerminalCard(columnId: col)
        XCTAssertEqual(
            BoardViewModel.cardsInWorkspace([mine, other, loose], active: ws).map(\.id), [mine.id])
    }

    // MARK: - displayedCards honours the injected active workspace

    func test_displayedCards_filtersByActiveWorkspace() {
        let vm = makeVM()
        let ws = UUID()
        let column = vm.board.columns[0]
        let mine = vm.board.addCard(to: column)
        mine.workspaceId = ws
        _ = vm.board.addCard(to: column)  // unassigned

        vm.activeWorkspaceProvider = { nil }
        XCTAssertEqual(vm.displayedCards(for: column, wheelhouseEnabled: false).count, 2, "All shows every card")

        vm.activeWorkspaceProvider = { ws }
        XCTAssertEqual(
            vm.displayedCards(for: column, wheelhouseEnabled: false).map(\.id), [mine.id],
            "workspace shows only its card")
    }

    // MARK: - displayedCards leaves Wheelhouse terminals to the stage

    func test_displayedCards_hidesWheelhouseCardsWhileTheFeatureIsOn() {
        let vm = makeVM()
        vm.activeWorkspaceProvider = { nil }
        let column = vm.board.columns[0]
        let plain = vm.board.addCard(to: column)
        let seat = vm.board.addCard(to: column)
        seat.tags = [Tag(key: "wheelhouse", value: "/w/ynw"), Tag(key: "seat", value: "may")]
        let quick = vm.board.addCard(to: column)
        quick.tags = WheelhouseCardMatcher.quickTerminalTags(wheelhouseRoot: "/w/ynw", seatCommand: "may", number: 1)
            .map { Tag(key: $0.key, value: $0.value) }

        XCTAssertEqual(vm.displayedCards(for: column, wheelhouseEnabled: true).map(\.id), [plain.id])
        XCTAssertEqual(
            vm.displayedCards(for: column, wheelhouseEnabled: false).map(\.id), [plain.id, seat.id, quick.id],
            "with the feature off, seat terminals stay on the board")
    }

    // MARK: - Drops land before the same card in the full list

    func test_dropBeforeAVisibleCard_landsBeforeItPastHiddenCards() {
        let vm = makeVM()
        vm.activeWorkspaceProvider = { nil }
        let column = vm.board.columns[0]
        let first = vm.board.addCard(to: column)
        let seat = vm.board.addCard(to: column)
        seat.tags = [Tag(key: "wheelhouse", value: "/w/ynw"), Tag(key: "seat", value: "may")]
        let target = vm.board.addCard(to: column)
        let moved = vm.board.addCard(to: column)
        let displayed = vm.displayedCards(for: column, wheelhouseEnabled: true)  // [first, target, moved]

        let index = BoardViewModel.fullIndex(
            forDisplayedIndex: 1, displayed: displayed, all: vm.board.cards(for: column))
        vm.board.moveCard(moved, to: column, at: index)

        XCTAssertEqual(vm.board.cards(for: column).map(\.id), [first.id, seat.id, moved.id, target.id])
    }

    func test_dropPastTheLastVisibleCard_appendsToTheFullList() {
        let column = UUID()
        let all = [TerminalCard(columnId: column), TerminalCard(columnId: column)]
        XCTAssertEqual(BoardViewModel.fullIndex(forDisplayedIndex: 1, displayed: [all[0]], all: all), 2)
    }

    // MARK: - New cards are stamped with the active workspace

    func test_addTerminal_stampsActiveWorkspace() {
        let vm = makeVM()
        let ws = UUID()
        vm.activeWorkspaceProvider = { ws }
        let column = vm.board.columns[0]

        vm.addTerminal(to: column)

        XCTAssertEqual(vm.board.cards(for: column).last?.workspaceId, ws)
    }

    func test_addTerminal_inAll_isUnassigned() {
        let vm = makeVM()
        vm.activeWorkspaceProvider = { nil }
        let column = vm.board.columns[0]

        vm.addTerminal(to: column)

        XCTAssertNil(vm.board.cards(for: column).last?.workspaceId)
    }
}
