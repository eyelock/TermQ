import XCTest

@testable import TermQ

final class TerminalSelectionDragControllerTests: XCTestCase {

    // MARK: - shouldClearSelection

    func testShouldClear_liveSelectionInTerminal_clears() {
        XCTAssertTrue(
            TerminalSelectionDragController.shouldClearSelection(
                selectionActive: true, startedInTerminal: true, shiftHeld: false))
    }

    func testShouldClear_noSelection_doesNothing() {
        XCTAssertFalse(
            TerminalSelectionDragController.shouldClearSelection(
                selectionActive: false, startedInTerminal: true, shiftHeld: false))
    }

    func testShouldClear_clickOutsideTerminal_leavesSelection() {
        XCTAssertFalse(
            TerminalSelectionDragController.shouldClearSelection(
                selectionActive: true, startedInTerminal: false, shiftHeld: false))
    }

    func testShouldClear_shiftClick_leavesSelectionForExtend() {
        XCTAssertFalse(
            TerminalSelectionDragController.shouldClearSelection(
                selectionActive: true, startedInTerminal: true, shiftHeld: true))
    }
}
