import XCTest

@testable import TermQ

final class SafePasteAnalyzerTests: XCTestCase {

    // MARK: - Safe content

    func testEmptyString_returnsNoWarnings() {
        let warnings = SafePasteAnalyzer.analyze("")
        XCTAssertTrue(warnings.isEmpty)
    }

    func testSingleLineSafeContent_returnsNoWarnings() {
        let warnings = SafePasteAnalyzer.analyze("echo hello")
        XCTAssertTrue(warnings.isEmpty)
    }

    func testPlainText_returnsNoWarnings() {
        let warnings = SafePasteAnalyzer.analyze("ls -la /tmp")
        XCTAssertTrue(warnings.isEmpty)
    }

    // MARK: - Multi-line detection

    func testTwoLines_returnsMultilineWarning() {
        let warnings = SafePasteAnalyzer.analyze("echo first\necho second")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("2 lines") }))
    }

    func testThreeLines_lineCountInMessage() {
        let warnings = SafePasteAnalyzer.analyze("echo a\necho b\necho c")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("3 lines") }))
    }

    func testSingleLineWithTrailingNewline_notMultiline() {
        // A trailing newline produces an empty component that gets filtered
        let warnings = SafePasteAnalyzer.analyze("echo hello\n")
        XCTAssertFalse(warnings.contains(where: { $0.message.contains("lines") }))
    }

    // MARK: - sudo detection

    func testSudoWithSpace_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("sudo apt-get install curl")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("sudo") }))
    }

    func testSudoPrefix_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("sudo")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("sudo") }))
    }

    func testSudoInMiddleOfCommand_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("echo hello && sudo rm file")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("sudo") }))
    }

    func testWordContainingSudoSubstring_returnsNoWarning() {
        // "pseudocode" contains "sudo" but the check requires "sudo " or prefix "sudo"
        let warnings = SafePasteAnalyzer.analyze("pseudocode example")
        XCTAssertFalse(warnings.contains(where: { $0.message.contains("sudo") }))
    }

    // MARK: - Destructive patterns

    func testRmRf_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("rm -rf /tmp/dir")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("rm -rf") }))
    }

    func testRmFr_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("rm -fr /tmp/dir")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("rm -fr") }))
    }

    func testMkfs_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("mkfs.ext4 /dev/sda1")
        XCTAssertTrue(warnings.contains(where: { $0.message.lowercased().contains("destructive") }))
    }

    func testDdIf_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("dd if=/dev/zero of=/dev/sda")
        XCTAssertTrue(warnings.contains(where: { $0.message.lowercased().contains("destructive") }))
    }

    func testDevNullRedirect_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("cat file > /dev/null")
        XCTAssertTrue(warnings.contains(where: { $0.message.lowercased().contains("destructive") }))
    }

    func testForkBomb_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze(":(){:|:&};:")
        XCTAssertTrue(warnings.contains(where: { $0.message.lowercased().contains("destructive") }))
    }

    func testChmod777_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("chmod 777 myfile")
        XCTAssertTrue(warnings.contains(where: { $0.message.lowercased().contains("destructive") }))
    }

    func testChmodR777_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("chmod -R 777 /var/www")
        XCTAssertTrue(warnings.contains(where: { $0.message.lowercased().contains("destructive") }))
    }

    func testRegularChmod_returnsNoDestructiveWarning() {
        let warnings = SafePasteAnalyzer.analyze("chmod 755 script.sh")
        XCTAssertFalse(warnings.contains(where: { $0.message.lowercased().contains("destructive") }))
    }

    // MARK: - curl/wget pipe to shell

    func testCurlPipeBash_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("curl https://example.com/install.sh | bash")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("Downloads and executes") }))
    }

    func testCurlPipeSh_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("curl https://example.com | sh")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("Downloads and executes") }))
    }

    func testCurlPipeBashNoSpace_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("curl https://example.com|bash")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("Downloads and executes") }))
    }

    func testCurlPipeShNoSpace_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("curl https://example.com|sh")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("Downloads and executes") }))
    }

    func testWgetPipeBash_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("wget -qO- https://example.com | bash")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("Downloads and executes") }))
    }

    func testCurlAloneWithoutPipe_returnsNoWarning() {
        let warnings = SafePasteAnalyzer.analyze("curl -L https://example.com -o output.txt")
        XCTAssertFalse(warnings.contains(where: { $0.message.contains("Downloads and executes") }))
    }

    func testWgetAloneWithoutPipe_returnsNoWarning() {
        let warnings = SafePasteAnalyzer.analyze("wget https://example.com -O output.txt")
        XCTAssertFalse(warnings.contains(where: { $0.message.contains("Downloads and executes") }))
    }

    func testBashAloneWithoutDownloader_returnsNoWarning() {
        let warnings = SafePasteAnalyzer.analyze("bash script.sh")
        XCTAssertFalse(warnings.contains(where: { $0.message.contains("Downloads and executes") }))
    }

    // MARK: - Environment variable manipulation

    func testExportPath_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("export PATH=/malicious:$PATH")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("environment") }))
    }

    func testExportLdPreload_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("export LD_PRELOAD=/lib/evil.so")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("environment") }))
    }

    func testExportLdLibraryPath_returnsWarning() {
        let warnings = SafePasteAnalyzer.analyze("export LD_LIBRARY_PATH=/evil")
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("environment") }))
    }

    func testExportUnrelatedVar_returnsNoEnvWarning() {
        // "export" without PATH= or LD_ should not trigger environment warning
        let warnings = SafePasteAnalyzer.analyze("export MY_VAR=hello")
        XCTAssertFalse(warnings.contains(where: { $0.message.contains("environment") }))
    }

    // MARK: - Multiple warnings

    func testSudoAndMultiline_returnsTwoWarnings() {
        let warnings = SafePasteAnalyzer.analyze("sudo apt update\nsudo apt upgrade")
        XCTAssertGreaterThanOrEqual(warnings.count, 2)
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("lines") }))
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("sudo") }))
    }

    func testDestructiveAndCurlPipe_returnsTwoWarnings() {
        let warnings = SafePasteAnalyzer.analyze("curl https://example.com | bash && rm -rf /")
        XCTAssertGreaterThanOrEqual(warnings.count, 2)
        XCTAssertTrue(warnings.contains(where: { $0.message.contains("Downloads and executes") }))
        XCTAssertTrue(warnings.contains(where: { $0.message.lowercased().contains("destructive") }))
    }

    // MARK: - Warning message structure

    func testWarning_messageIsNonEmpty() {
        let warnings = SafePasteAnalyzer.analyze("sudo rm -rf /")
        for warning in warnings {
            XCTAssertFalse(warning.message.isEmpty)
        }
    }
}
