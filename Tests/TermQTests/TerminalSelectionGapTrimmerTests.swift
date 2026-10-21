import XCTest

@testable import SwiftTerm
@testable import TermQ

/// `TerminalSelectionGapTrimmer` drops a right-edge glyph only when the
/// terminal's cells prove the gap before it was never written. The pure tests
/// drive `trim(_:rawRows:)` with hand-built rows; the SwiftTerm-backed tests
/// feed real escape sequences through a headless terminal and copy with the
/// same selection service the view uses.
final class TerminalSelectionGapTrimmerTests: XCTestCase {

    private let nul = String(TerminalSelectionGapTrimmer.unwrittenCell)

    private func gap(_ count: Int) -> String { String(repeating: nul, count: count) }
    private func spaces(_ count: Int) -> String { String(repeating: " ", count: count) }

    // MARK: - Pure: when nothing can be trimmed

    func testTrim_noEdgeGlyph_returnsTextAndNeverReadsRows() {
        var rowsRead = false
        let text = "plain text   \nanother line"
        let result = TerminalSelectionGapTrimmer.trim(text) {
            rowsRead = true
            return []
        }
        XCTAssertEqual(result, text)
        XCTAssertFalse(rowsRead, "rows are only scanned when a line could carry a gap glyph")
    }

    func testTrim_glyphWithoutSpaceBefore_returnsText() {
        let text = "a|b|"
        let result = TerminalSelectionGapTrimmer.trim(text) { ["a|b" + gap(3) + "|"] }
        XCTAssertEqual(result, text)
    }

    func testTrim_borderPaddedWithRealSpaces_keepsBorder() {
        // The row was written with explicit spaces, so no NUL precedes the bar.
        let row = "│ text" + spaces(10) + "│"
        let result = TerminalSelectionGapTrimmer.trim(row) { [row] }
        XCTAssertEqual(result, row)
    }

    func testTrim_gapFollowedByWord_keepsWord() {
        // Right-aligned text after a cursor jump is content, not a border.
        let raw = "left" + gap(10) + "Auto"
        let copied = "left" + spaces(10) + "Auto"
        let result = TerminalSelectionGapTrimmer.trim(copied) { [raw] }
        XCTAssertEqual(result, copied)
    }

    func testTrim_emptyText_returnsEmpty() {
        XCTAssertEqual(TerminalSelectionGapTrimmer.trim("") { [] }, "")
    }

    // MARK: - Pure: full rows

    func testTrim_fullRowWithGapBeforeBar_dropsBarAndGap() {
        let raw = "│ Confirm folder trust" + gap(77) + "│"
        let copied = "│ Confirm folder trust" + spaces(77) + "│"
        let result = TerminalSelectionGapTrimmer.trim(copied) { [raw] }
        XCTAssertEqual(result, "│ Confirm folder trust")
    }

    func testTrim_rowThatIsOnlyBorders_leavesLeftBorder() {
        let raw = "│" + gap(98) + "│"
        let copied = "│" + spaces(98) + "│"
        let result = TerminalSelectionGapTrimmer.trim(copied) { [raw] }
        XCTAssertEqual(result, "│")
    }

    func testTrim_scrollbarBlockGlyph_isDropped() {
        let raw = "some transcript text" + gap(30) + "█"
        let copied = "some transcript text" + spaces(30) + "█"
        let result = TerminalSelectionGapTrimmer.trim(copied) { [raw] }
        XCTAssertEqual(result, "some transcript text")
    }

    func testTrim_asciiPipe_isDropped() {
        let raw = "text" + gap(5) + "|"
        let copied = "text" + spaces(5) + "|"
        let result = TerminalSelectionGapTrimmer.trim(copied) { [raw] }
        XCTAssertEqual(result, "text")
    }

    func testTrim_multiLine_trimsOnlyFlaggedRowsAndKeepsLineBreaks() {
        let flaggedRaw = "row two" + gap(20) + "│"
        let paddedRaw = "row three" + spaces(18) + "│"
        let copied = ["row one", "row two" + spaces(20) + "│", paddedRaw, "", "row five"]
            .joined(separator: "\n")
        let result = TerminalSelectionGapTrimmer.trim(copied) { [flaggedRaw, paddedRaw, "row one"] }
        XCTAssertEqual(result, ["row one", "row two", paddedRaw, "", "row five"].joined(separator: "\n"))
    }

    // MARK: - Pure: partial rows at the selection edges

    func testTrim_lastLineIsSuffixOfFlaggedRow_isTrimmed() {
        let raw = "│ Confirm folder trust" + gap(77) + "│"
        let copied = "first line\nfolder trust" + spaces(77) + "│"
        let result = TerminalSelectionGapTrimmer.trim(copied) { [raw] }
        XCTAssertEqual(result, "first line\nfolder trust")
    }

    func testTrim_singleLineSuffixOfFlaggedRow_isTrimmed() {
        let raw = "│ Confirm folder trust" + gap(77) + "│"
        let copied = "trust" + spaces(77) + "│"
        let result = TerminalSelectionGapTrimmer.trim(copied) { [raw] }
        XCTAssertEqual(result, "trust")
    }

    func testTrim_middleLineThatOnlyMatchesBySuffix_isLeftAlone() {
        // Middle lines are whole rows; a suffix match there means a different row.
        let raw = "│ Confirm folder trust" + gap(77) + "│"
        let middle = "trust" + spaces(77) + "│"
        let copied = "first\n" + middle + "\nlast"
        let result = TerminalSelectionGapTrimmer.trim(copied) { [raw] }
        XCTAssertEqual(result, copied)
    }

    func testTrim_bareTailOnEdgeLine_isLeftAlone() {
        // A first or last line made only of gap and glyph ends every flagged
        // row, so it must not borrow their evidence.
        let raw = "│ Confirm folder trust" + gap(77) + "│"
        let copied = "first\n" + spaces(3) + "│"
        let result = TerminalSelectionGapTrimmer.trim(copied) { [raw] }
        XCTAssertEqual(result, copied)
    }

    func testTrim_rowWithWideCharacters_isLeftAlone() {
        // The raw export carries a NUL placeholder after each wide character,
        // which the copy path drops, so such rows never match and the border
        // is kept rather than guessed at.
        let raw = "│ 日本語" + gap(30) + "│"
        let copied = "│ 日本語" + spaces(30) + "│"
        let result = TerminalSelectionGapTrimmer.trim(copied) { [raw.replacingOccurrences(of: "語", with: "語" + nul)] }
        XCTAssertEqual(result, copied)
    }

    // MARK: - isEdgeGlyph

    func testIsEdgeGlyph_boxDrawingBlockAndPipe() {
        for glyph: Character in ["│", "┃", "║", "╎", "█", "▐", "▌", "░", "|"] {
            XCTAssertTrue(TerminalSelectionGapTrimmer.isEdgeGlyph(glyph), "\(glyph)")
        }
        for glyph: Character in ["a", " ", "x", "é", "🙂"] {
            XCTAssertFalse(TerminalSelectionGapTrimmer.isEdgeGlyph(glyph), "\(glyph)")
        }
    }

    func testIsEdgeGlyph_horizontalRuleCountsAsBoxDrawing() {
        // Box-drawing is matched by block, not by orientation; a row ending in a
        // horizontal rule after a gap is just as much a border.
        XCTAssertTrue(TerminalSelectionGapTrimmer.isEdgeGlyph("─"))
    }

    // MARK: - SwiftTerm-backed

    private func makeTerminal(cols: Int = 40, rows: Int = 6) -> Terminal {
        let headless = HeadlessTerminal(queue: nil) { _ in }
        headless.terminal.resize(cols: cols, rows: rows)
        return headless.terminal
    }

    private func rawRows(_ terminal: Terminal) -> [String] {
        TerminalSelectionGapTrimmer.rawRows(fromBufferData: terminal.getBufferAsData(kind: .active))
    }

    private func copiedText(_ terminal: Terminal, from start: Position, to end: Position) -> String {
        let selection = SelectionService(terminal: terminal)
        selection.setSelection(start: start, end: end)
        return selection.getSelectedText()
    }

    func testRawRows_cursorForwardLeavesUnwrittenCells() {
        let terminal = makeTerminal()
        terminal.feed(text: "abc\u{1b}[20C│\r\n")

        let rows = rawRows(terminal)
        XCTAssertEqual(rows.first, "abc" + gap(20) + "│")
    }

    func testRawRows_explicitSpacesAreNotUnwritten() {
        let terminal = makeTerminal()
        terminal.feed(text: "abc" + spaces(20) + "│\r\n")

        let rows = rawRows(terminal)
        XCTAssertEqual(rows.first, "abc" + spaces(20) + "│")
    }

    // SwiftTerm never includes the final column of a selection's last row
    // (the end column is exclusive), so every scenario below ends the selection
    // on a row after the one carrying the border, which is how a drag that
    // sweeps a TUI dialog actually lands.

    func testCopy_copilotStyleDialog_dropsRightBorder() {
        let terminal = makeTerminal(cols: 40)
        // What Copilot CLI emits for a dialog row: left border, text, cursor
        // jump to the last column, right border.
        terminal.feed(text: "│ Confirm folder trust\u{1b}[17C│\r\n")
        terminal.feed(text: "│\u{1b}[38C│\r\n")
        terminal.feed(text: "next\r\n")

        let copied = copiedText(terminal, from: Position(col: 0, row: 0), to: Position(col: 4, row: 2))
        XCTAssertTrue(copied.contains(spaces(17) + "│"), "SwiftTerm copies the gap as spaces")

        let trimmed = TerminalSelectionGapTrimmer.trim(copied) { rawRows(terminal) }
        XCTAssertEqual(trimmed, "│ Confirm folder trust\n│\nnext")
    }

    func testCopy_spacePaddedBox_isUnchanged() {
        let terminal = makeTerminal(cols: 40)
        let row = "│ padded" + spaces(31) + "│"
        terminal.feed(text: row + "\r\n")
        terminal.feed(text: "next\r\n")

        let copied = copiedText(terminal, from: Position(col: 0, row: 0), to: Position(col: 4, row: 1))
        XCTAssertEqual(copied, row + "\nnext")

        let trimmed = TerminalSelectionGapTrimmer.trim(copied) { rawRows(terminal) }
        XCTAssertEqual(trimmed, copied)
    }

    func testCopy_partialSelectionEndingAtBorder_isTrimmed() {
        let terminal = makeTerminal(cols: 40)
        terminal.feed(text: "│ Confirm folder trust\u{1b}[17C│\r\n")
        terminal.feed(text: "next\r\n")

        let copied = copiedText(terminal, from: Position(col: 10, row: 0), to: Position(col: 4, row: 1))
        XCTAssertEqual(copied, "folder trust" + spaces(17) + "│\nnext")

        let trimmed = TerminalSelectionGapTrimmer.trim(copied) { rawRows(terminal) }
        XCTAssertEqual(trimmed, "folder trust\nnext")
    }
}
