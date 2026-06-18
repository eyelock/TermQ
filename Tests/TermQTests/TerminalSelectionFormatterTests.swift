import XCTest

@testable import TermQ

final class TerminalSelectionFormatterTests: XCTestCase {

    // MARK: - collapsingLineBreaks

    func testCollapse_emptyString_returnsEmpty() {
        XCTAssertEqual(TerminalSelectionFormatter.collapsingLineBreaks(""), "")
    }

    func testCollapse_singleLine_unchanged() {
        XCTAssertEqual(TerminalSelectionFormatter.collapsingLineBreaks("echo hello"), "echo hello")
    }

    func testCollapse_multiLine_joinedWithSingleSpace() {
        let input = "echo \\\n  hello \\\n  world"
        XCTAssertEqual(
            TerminalSelectionFormatter.collapsingLineBreaks(input), "echo \\ hello \\ world")
    }

    func testCollapse_blankLinesDropped() {
        XCTAssertEqual(
            TerminalSelectionFormatter.collapsingLineBreaks("a\n\n   \nb"), "a b")
    }

    // MARK: - strippingIndentation

    func testStrip_emptyString_returnsEmpty() {
        XCTAssertEqual(TerminalSelectionFormatter.strippingIndentation(""), "")
    }

    func testStrip_singleLineNoIndent_unchanged() {
        XCTAssertEqual(TerminalSelectionFormatter.strippingIndentation("ls -la"), "ls -la")
    }

    func testStrip_uniformIndentRemoved_newlinesPreserved() {
        let input = "  cat <<'JSON'\n  {\"a\":1}\n  JSON"
        let expected = "cat <<'JSON'\n{\"a\":1}\nJSON"
        XCTAssertEqual(TerminalSelectionFormatter.strippingIndentation(input), expected)
    }

    func testStrip_relativeIndentationPreserved() {
        let input = "  if true; then\n      echo hi\n  fi"
        let expected = "if true; then\n    echo hi\nfi"
        XCTAssertEqual(TerminalSelectionFormatter.strippingIndentation(input), expected)
    }

    func testStrip_blankLinesDoNotConstrainCommonIndent() {
        // The empty middle line must not force the common prefix to "".
        let input = "    one\n\n    two"
        let expected = "one\n\ntwo"
        XCTAssertEqual(TerminalSelectionFormatter.strippingIndentation(input), expected)
    }

    func testStrip_whitespaceOnlyLineDoesNotConstrainCommonIndent() {
        // A line of only spaces (shorter than the indent) must not shrink the prefix.
        let input = "    one\n  \n    two"
        let expected = "one\n\ntwo"
        XCTAssertEqual(TerminalSelectionFormatter.strippingIndentation(input), expected)
    }

    func testStrip_noCommonIndent_unchanged() {
        // One unindented line means there is no shared indent to remove.
        let input = "  indented\nflush"
        XCTAssertEqual(TerminalSelectionFormatter.strippingIndentation(input), input)
    }

    func testStrip_tabsTreatedAsIndentation() {
        let input = "\t\techo a\n\t\techo b"
        let expected = "echo a\necho b"
        XCTAssertEqual(TerminalSelectionFormatter.strippingIndentation(input), expected)
    }

    func testStrip_newlinesPreservedNotCollapsed() {
        // Distinguishes this transform from collapsingLineBreaks.
        let input = "  a\n  b"
        XCTAssertTrue(TerminalSelectionFormatter.strippingIndentation(input).contains("\n"))
    }
}
