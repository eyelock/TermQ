import XCTest

@testable import SwiftTerm

/// Characterization tests for how SwiftTerm's selection behaves when the
/// terminal scrolls. These pin down a dependency behavior we rely on, and
/// document the defect behind the Copilot CLI selection bug.
///
/// The distinction that matters is *how* the scroll happens:
///
/// - Full-screen scroll (and normal-buffer output): SwiftTerm grows the buffer
///   and advances `yBase`/`yDisp`. Absolute row indices stay valid, so a
///   selection keeps pointing at its own text. This is the path every harness
///   except Copilot CLI takes.
/// - Partial scroll region (`DECSTBM`, e.g. `ESC[4;34r`): lines are shifted
///   within the region and `yBase`/`yDisp` do not move, so the absolute rows
///   come to hold different text. SwiftTerm translates the anchors to match
///   (upstream since SwiftTerm #616), keeping the selection on its text.
///   Copilot CLI scrolls its transcript this way, reserving its tab bar and
///   prompt rows.
final class TerminalSelectionScrollBehaviorTests: XCTestCase {

    private func makeTerminal(rows: Int = 10, cols: Int = 40) -> Terminal {
        let headless = HeadlessTerminal(queue: nil) { _ in }
        headless.terminal.resize(cols: cols, rows: rows)
        return headless.terminal
    }

    private func paintLines(_ terminal: Terminal, count: Int) {
        for i in 1...count { terminal.feed(text: "\u{1b}[\(i);1HLINE_\(i)") }
    }

    private func selectionOnRow4(_ terminal: Terminal) -> SelectionService {
        let selection = SelectionService(terminal: terminal)
        selection.setSelection(start: Position(col: 0, row: 4), end: Position(col: 10, row: 4))
        return selection
    }

    private func selectedText(_ selection: SelectionService) -> String {
        selection.getSelectedText().trimmingCharacters(in: .whitespaces)
    }

    /// Guards the dependency pin: if TermQ is ever moved back to an upstream
    /// SwiftTerm without the anchor-translation fix, this fails.
    func test_partialScrollRegion_selectionFollowsItsText() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?1049h")
        paintLines(terminal, count: 10)
        let selection = selectionOnRow4(terminal)
        XCTAssertEqual(selectedText(selection), "LINE_5")

        // Region rows 2...9, then a linefeed on its bottom row — Copilot's pattern.
        terminal.feed(text: "\u{1b}[2;9r\u{1b}[9;1H\r\n\u{1b}[1;10r")

        XCTAssertEqual(terminal.displayBuffer.yDisp, 0, "partial-region scrolls do not advance yDisp")
        XCTAssertEqual(
            selectedText(selection), "LINE_5",
            "anchors are translated with the shifted rows, so the selection keeps its text")
    }

    func test_fullScreenScroll_selectionKeepsItsText() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?1049h")
        paintLines(terminal, count: 9)
        let selection = selectionOnRow4(terminal)
        XCTAssertEqual(selectedText(selection), "LINE_5")

        terminal.feed(text: "\u{1b}[1;10r\u{1b}[10;1H\r\n\u{1b}[1;10r")

        XCTAssertEqual(terminal.displayBuffer.yDisp, 1, "full-screen scrolls advance yDisp")
        XCTAssertEqual(selectedText(selection), "LINE_5")
    }

    func test_normalBufferAppend_selectionKeepsItsText() {
        let terminal = makeTerminal()
        paintLines(terminal, count: 9)
        let selection = selectionOnRow4(terminal)
        XCTAssertEqual(selectedText(selection), "LINE_5")

        terminal.feed(text: "\u{1b}[10;1H\r\nAPPENDED")

        XCTAssertEqual(selectedText(selection), "LINE_5")
    }
}
