import XCTest

@testable import TermQ

final class ShellEscaperTests: XCTestCase {

    // MARK: - singleQuote

    func testSingleQuotePlainString() {
        XCTAssertEqual(ShellEscaper.singleQuote("hello"), "'hello'")
    }

    func testSingleQuoteStringWithSpaces() {
        XCTAssertEqual(ShellEscaper.singleQuote("hello world"), "'hello world'")
    }

    func testSingleQuoteEmbeddedSingleQuote() {
        // it's → 'it'"'"'s'
        XCTAssertEqual(ShellEscaper.singleQuote("it's"), "'it'\"'\"'s'")
    }

    func testSingleQuoteMultipleEmbeddedQuotes() {
        // don't stop → 'don'"'"'t stop'
        XCTAssertEqual(ShellEscaper.singleQuote("don't stop"), "'don'\"'\"'t stop'")
    }

    func testSingleQuoteEmptyString() {
        XCTAssertEqual(ShellEscaper.singleQuote(""), "''")
    }

    func testSingleQuotePath() {
        XCTAssertEqual(ShellEscaper.singleQuote("/Users/david/my project"), "'/Users/david/my project'")
    }

    func testSingleQuoteDollarSign() {
        // Dollar sign needs no special treatment inside single quotes
        XCTAssertEqual(ShellEscaper.singleQuote("$HOME"), "'$HOME'")
    }

    func testSingleQuoteBacktick() {
        XCTAssertEqual(ShellEscaper.singleQuote("`cmd`"), "'`cmd`'")
    }

    // MARK: - doubleQuote

    func testDoubleQuotePlainString() {
        XCTAssertEqual(ShellEscaper.doubleQuote("hello"), "hello")
    }

    func testDoubleQuoteEscapesBackslash() {
        XCTAssertEqual(ShellEscaper.doubleQuote("a\\b"), "a\\\\b")
    }

    func testDoubleQuoteEscapesDoubleQuote() {
        XCTAssertEqual(ShellEscaper.doubleQuote("say \"hi\""), "say \\\"hi\\\"")
    }

    func testDoubleQuoteEscapesDollarSign() {
        XCTAssertEqual(ShellEscaper.doubleQuote("cost $5"), "cost \\$5")
    }

    func testDoubleQuoteEscapesBacktick() {
        XCTAssertEqual(ShellEscaper.doubleQuote("`date`"), "\\`date\\`")
    }

    func testDoubleQuoteBackslashFirst() {
        // Backslash must be escaped before other substitutions to avoid double-escaping
        XCTAssertEqual(ShellEscaper.doubleQuote("\\$"), "\\\\\\$")
    }

    func testDoubleQuoteEmptyString() {
        XCTAssertEqual(ShellEscaper.doubleQuote(""), "")
    }

    func testDoubleQuoteLLMPromptExample() {
        let prompt = "You are a helpful assistant. Cost: $10. Use `backticks`."
        let result = ShellEscaper.doubleQuote(prompt)
        XCTAssertFalse(result.contains("Cost: $10"))  // bare dollar sign is gone
        XCTAssertTrue(result.contains("\\$"))
        XCTAssertTrue(result.contains("\\`"))
    }

    // MARK: - envVarName

    func testEnvVarNameSimple() {
        XCTAssertEqual(ShellEscaper.envVarName("project"), "PROJECT")
    }

    func testEnvVarNameUppercases() {
        XCTAssertEqual(ShellEscaper.envVarName("myKey"), "MYKEY")
    }

    func testEnvVarNameReplacesDashes() {
        XCTAssertEqual(ShellEscaper.envVarName("my-key"), "MY_KEY")
    }

    func testEnvVarNameReplacesSpaces() {
        XCTAssertEqual(ShellEscaper.envVarName("my key"), "MY_KEY")
    }

    func testEnvVarNameReplacesDotsAndSlashes() {
        XCTAssertEqual(ShellEscaper.envVarName("my.key/value"), "MY_KEY_VALUE")
    }

    func testEnvVarNameStripsLeadingDigits() {
        XCTAssertEqual(ShellEscaper.envVarName("123project"), "PROJECT")
    }

    func testEnvVarNameStripsLeadingUnderscores() {
        XCTAssertEqual(ShellEscaper.envVarName("_project"), "PROJECT")
    }

    func testEnvVarNameStripsLeadingDigitsAndUnderscores() {
        XCTAssertEqual(ShellEscaper.envVarName("1_2_project"), "PROJECT")
    }

    func testEnvVarNameAllInvalid() {
        // All chars become underscores, then all stripped → empty
        XCTAssertEqual(ShellEscaper.envVarName("123"), "")
    }

    func testEnvVarNameAlreadyValid() {
        XCTAssertEqual(ShellEscaper.envVarName("MY_KEY"), "MY_KEY")
    }
}
