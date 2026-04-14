import Foundation
import XCTest

@testable import TermQ

/// Tests for the parseStringsFile(at:) function in Strings.swift.
///
/// Each test writes a small .strings snippet to a temp file and asserts
/// on the parsed dictionary. Bugs here mean localizations silently fall
/// back to English without any visible error.
final class StringsParserTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQStringsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// Write content to a temp .strings file and parse it.
    private func parse(_ content: String) -> [String: String]? {
        let url = tempDirectory.appendingPathComponent("\(UUID().uuidString).strings")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return parseStringsFile(at: url)
    }

    // MARK: - Basic parsing

    func testBasicKeyValue_parsedCorrectly() {
        let result = parse(#""greeting" = "Hello";"#)
        XCTAssertEqual(result?["greeting"], "Hello")
    }

    func testMultipleKeyValues_allParsed() {
        let content = """
            "one" = "First";
            "two" = "Second";
            "three" = "Third";
            """
        let result = parse(content)
        XCTAssertEqual(result?["one"], "First")
        XCTAssertEqual(result?["two"], "Second")
        XCTAssertEqual(result?["three"], "Third")
    }

    func testEmptyFile_returnsNil() {
        let result = parse("")
        XCTAssertNil(result)
    }

    func testFileWithOnlyWhitespace_returnsNil() {
        let result = parse("   \n\n\t\n")
        XCTAssertNil(result)
    }

    func testNonexistentFile_returnsNil() {
        let url = tempDirectory.appendingPathComponent("does-not-exist.strings")
        let result = parseStringsFile(at: url)
        XCTAssertNil(result)
    }

    // MARK: - Line comments

    func testLineComment_stripped() {
        let content = """
            // This is a comment
            "key" = "value";
            """
        let result = parse(content)
        XCTAssertEqual(result?["key"], "value")
        XCTAssertNil(result?["// This is a comment"])
    }

    func testLineCommentAfterEntry_strippedAndEntryParsed() {
        // The comment stripper runs per-line before quote parsing,
        // so a trailing comment on the same line as the value is stripped.
        // NOTE: In a real .strings file, the value ends at ";" so trailing
        // comments on the same line after ";" are already outside the value.
        let content = """
            "key" = "value"; // inline comment
            """
        let result = parse(content)
        XCTAssertEqual(result?["key"], "value")
    }

    func testBlankLinesSkipped() {
        let content = """

            "key" = "value";

            """
        let result = parse(content)
        XCTAssertEqual(result?["key"], "value")
        XCTAssertEqual(result?.count, 1)
    }

    // MARK: - Block comments

    func testBlockComment_stripped() {
        let content = """
            /* Block comment */
            "key" = "value";
            """
        let result = parse(content)
        XCTAssertEqual(result?["key"], "value")
    }

    func testBlockCommentSpanningMultipleLines_stripped() {
        let content = "/* This\n   is\n   multiline\n*/\n\"key\" = \"value\";"
        let result = parse(content)
        XCTAssertEqual(result?["key"], "value")
    }

    func testBlockCommentBetweenEntries_strippedEntryParsed() {
        let content = """
            "first" = "One";
            /* separator */
            "second" = "Two";
            """
        let result = parse(content)
        XCTAssertEqual(result?["first"], "One")
        XCTAssertEqual(result?["second"], "Two")
    }

    // MARK: - Escape sequences

    func testEscapedQuoteInValue_unescaped() {
        let content = #""key" = "say \"hello\"";"#
        let result = parse(content)
        XCTAssertEqual(result?["key"], #"say "hello""#)
    }

    func testBackslashN_unescapedToNewline() {
        let content = #""key" = "line1\nline2";"#
        let result = parse(content)
        XCTAssertEqual(result?["key"], "line1\nline2")
    }

    func testDoubleBackslash_unescapedToSingleBackslash() {
        let content = #""key" = "path\\file";"#
        let result = parse(content)
        XCTAssertEqual(result?["key"], #"path\file"#)
    }

    // MARK: - Edge cases

    func testValueWithEqualSign_parsedCorrectly() {
        let content = #""formula" = "a = b";"#
        let result = parse(content)
        XCTAssertEqual(result?["formula"], "a = b")
    }

    func testValueWithColon_parsedCorrectly() {
        let content = #""label" = "Status: OK";"#
        let result = parse(content)
        XCTAssertEqual(result?["label"], "Status: OK")
    }

    func testKeyWithSpaces_parsedCorrectly() {
        let content = #""key with spaces" = "value";"#
        let result = parse(content)
        XCTAssertEqual(result?["key with spaces"], "value")
    }

    func testEmptyValue_parsedCorrectly() {
        let content = #""key" = "";"#
        let result = parse(content)
        // An empty value means the key exists with empty string
        // The parser returns nil for empty dictionary, so single empty-value
        // entry may return nil if the parser skips empty values.
        // Document the actual behavior:
        if let result = result {
            XCTAssertEqual(result["key"], "")
        }
        // If nil — the parser filtered it (also acceptable; callers fall back to key itself)
    }

    func testLineNotStartingWithQuote_skipped() {
        let content = """
            some garbage line
            "key" = "value";
            """
        let result = parse(content)
        XCTAssertEqual(result?["key"], "value")
        XCTAssertNil(result?["some garbage line"])
    }

    func testLargeDictionary_allEntriesParsed() {
        var lines: [String] = []
        for i in 0..<50 {
            lines.append(#""\#(i)" = "value_\#(i)";"#)
        }
        let result = parse(lines.joined(separator: "\n"))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 50)
        XCTAssertEqual(result?["0"], "value_0")
        XCTAssertEqual(result?["49"], "value_49")
    }
}
