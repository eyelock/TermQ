import AppKit
import Foundation
import SwiftTerm

/// Drops the right-edge border or scrollbar glyph that a TUI parks at the end
/// of a row by jumping the cursor across the gap instead of writing spaces.
///
/// Copilot CLI draws `text ESC[77C │`: the cells between the text and the bar
/// are never written. SwiftTerm's copy trims unwritten cells only when they
/// trail the row, so the bar in the last column keeps the whole gap alive and
/// the clipboard receives the text, 77 spaces, and the bar. A plain terminal
/// avoids this only because such apps handle mouse selection themselves;
/// TermQ turns mouse reporting off while dragging, so the grid copy is what
/// the user gets.
///
/// The decision is made per cell, not per character: a glyph is dropped only
/// when the raw row shows unwritten cells directly before it. Borders padded
/// with real spaces are copied as they are.
enum TerminalSelectionGapTrimmer {
    /// How SwiftTerm renders a never-written cell in raw row text. Copied
    /// text has these replaced with spaces.
    static let unwrittenCell: Character = "\u{0}"

    /// Rewrites `text` (the copied selection) with gap-positioned edge glyphs
    /// removed and the trailing gap trimmed.
    ///
    /// `rawRows` supplies every row of the terminal buffer with trailing
    /// unwritten cells trimmed and interior ones left as `unwrittenCell`. It is
    /// only invoked when some line of `text` could carry such a glyph, so the
    /// common copy pays nothing.
    static func trim(_ text: String, rawRows: () -> [String]) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.contains(where: isCandidate) else { return text }

        let flagged = Set(rawRows().compactMap(flaggedDisplayRow))
        guard !flagged.isEmpty else { return text }

        let lastIndex = lines.count - 1
        let trimmed = lines.enumerated().map { index, line -> String in
            guard isCandidate(line) else { return line }
            // Rows copied whole match a flagged row exactly. The first and last
            // lines of a selection may start part-way through a row, so they
            // match any flagged row they end, provided they carry some text of
            // their own: a bare gap-and-glyph tail would end every flagged row.
            let stripped = strippingTail(line)
            let endsFlaggedRow =
                flagged.contains(line)
                || ((index == 0 || index == lastIndex) && !stripped.isEmpty
                    && flagged.contains { $0.hasSuffix(line) })
            return endsFlaggedRow ? stripped : line
        }
        return trimmed.joined(separator: "\n")
    }

    /// Box-drawing (U+2500–U+257F) and block-element (U+2580–U+259F) glyphs,
    /// or an ASCII pipe: what TUIs draw borders and scrollbars with.
    static func isEdgeGlyph(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first
        else { return false }
        return scalar == "|" || (0x2500...0x259F).contains(scalar.value)
    }

    /// A copied line that ends in an edge glyph preceded by at least one space.
    private static func isCandidate(_ line: String) -> Bool {
        guard let last = line.last, isEdgeGlyph(last) else { return false }
        return line.dropLast().last == " "
    }

    /// The display form (unwritten cells shown as spaces) of a raw row whose
    /// final glyph sits directly after unwritten cells; nil for any other row.
    private static func flaggedDisplayRow(_ raw: String) -> String? {
        guard let last = raw.last, isEdgeGlyph(last), raw.dropLast().last == unwrittenCell
        else { return nil }
        return String(raw.map { $0 == unwrittenCell ? " " : $0 })
    }

    /// Drop the final glyph and the gap before it.
    private static func strippingTail(_ line: String) -> String {
        var result = line.dropLast()
        while result.last == " " { result = result.dropLast() }
        return String(result)
    }
}

// MARK: - SwiftTerm bridge

extension TerminalSelectionGapTrimmer {
    /// Splits a SwiftTerm `getBufferAsData` export (every row of the active
    /// buffer, scrollback included, newline-separated) into the raw rows
    /// `trim(_:rawRows:)` expects.
    ///
    /// At the pinned SwiftTerm revision that export keeps never-written cells as
    /// NUL. Upstream #718 (merged after the pin) replaces them with spaces; on a
    /// re-pin that includes it, trimming silently stops and
    /// `testRawRows_cursorForwardLeavesUnwrittenCells` fails to say so.
    ///
    /// Rows holding wide characters carry one NUL placeholder after each, which
    /// the copy path drops. Those rows never match a copied line, so a border
    /// after CJK or emoji text is left in place rather than guessed at.
    static func rawRows(fromBufferData data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n")
    }
}

extension TerminalView {
    /// Re-read the pasteboard after a standard `copy(_:)` and drop any edge
    /// glyphs the inner app positioned with a cursor jump. Call right after
    /// `super.copy(_:)`, which writes the pasteboard synchronously.
    func rewritePasteboardTrimmingUnwrittenGaps() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else { return }

        let trimmed = TerminalSelectionGapTrimmer.trim(text) {
            TerminalSelectionGapTrimmer.rawRows(fromBufferData: getBufferAsData(kind: .active))
        }
        guard trimmed != text else { return }

        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
    }
}
