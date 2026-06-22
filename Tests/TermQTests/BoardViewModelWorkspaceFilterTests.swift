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
        XCTAssertEqual(vm.displayedCards(for: column).count, 2, "All shows every card")

        vm.activeWorkspaceProvider = { ws }
        XCTAssertEqual(
            vm.displayedCards(for: column).map(\.id), [mine.id], "workspace shows only its card")
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
