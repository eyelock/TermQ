import Foundation
import XCTest

@testable import MCPServerLib

/// Tests for URLOpener URL building methods
///
/// These tests verify that URL schemes are constructed correctly for
/// communication with the TermQ GUI. The actual URL opening (which
/// requires a running GUI) is tested manually via MCP Inspector.
final class URLOpenerTests: XCTestCase {

    // MARK: - Open URL Tests

    func testBuildOpenURLWithMinimalParams() {
        let cardId = UUID()
        let url = URLOpener.buildOpenURL(
            params: URLOpener.OpenURLParams(
                cardId: cardId,
                path: "/Users/test/project"
            )
        )

        XCTAssertTrue(url.starts(with: "termq://open?"))
        XCTAssertTrue(url.contains("id=\(cardId.uuidString)"))
        XCTAssertTrue(url.contains("path=/Users/test/project"))
    }

    func testBuildOpenURLWithAllParams() {
        let cardId = UUID()
        let url = URLOpener.buildOpenURL(
            params: URLOpener.OpenURLParams(
                cardId: cardId,
                path: "/Users/test/project",
                name: "My Terminal",
                description: "A test terminal",
                column: "In Progress",
                tags: [(key: "project", value: "myapp"), (key: "type", value: "dev")],
                llmPrompt: "You are helping with myapp",
                llmNextAction: "Review the tests",
                initCommand: "npm run dev"
            )
        )

        XCTAssertTrue(url.starts(with: "termq://open?"))
        XCTAssertTrue(url.contains("id=\(cardId.uuidString)"))
        XCTAssertTrue(url.contains("path=/Users/test/project"))
        XCTAssertTrue(url.contains("name=My%20Terminal"))
        XCTAssertTrue(url.contains("description=A%20test%20terminal"))
        XCTAssertTrue(url.contains("column=In%20Progress"))
        XCTAssertTrue(url.contains("tag=project%3Dmyapp"))
        XCTAssertTrue(url.contains("tag=type%3Ddev"))
        XCTAssertTrue(url.contains("llmPrompt="))
        XCTAssertTrue(url.contains("llmNextAction="))
        XCTAssertTrue(url.contains("initCommand="))
    }

    func testBuildOpenURLEncodesSpecialCharacters() {
        let cardId = UUID()
        let url = URLOpener.buildOpenURL(
            params: URLOpener.OpenURLParams(
                cardId: cardId,
                path: "/Users/test/my project",
                name: "Terminal & More"
            )
        )

        // Spaces should be encoded
        XCTAssertTrue(url.contains("my%20project"))
        // Ampersands should be encoded
        XCTAssertTrue(url.contains("Terminal%20%26%20More"))
    }

    // MARK: - Update URL Tests

    func testBuildUpdateURLWithMinimalParams() {
        let cardId = UUID()
        let url = URLOpener.buildUpdateURL(
            params: URLOpener.UpdateURLParams(
                cardId: cardId
            )
        )

        XCTAssertTrue(url.starts(with: "termq://update?"))
        XCTAssertTrue(url.contains("id=\(cardId.uuidString)"))
    }

    func testBuildUpdateURLWithAllParams() {
        let cardId = UUID()
        let url = URLOpener.buildUpdateURL(
            params: URLOpener.UpdateURLParams(
                cardId: cardId,
                name: "New Name",
                description: "New description",
                badge: "WIP",
                column: "Done",
                llmPrompt: "New prompt",
                llmNextAction: "New action",
                initCommand: "npm start",
                favourite: true,
                tags: [(key: "status", value: "reviewed")],
                replaceTags: false
            )
        )

        XCTAssertTrue(url.starts(with: "termq://update?"))
        XCTAssertTrue(url.contains("id=\(cardId.uuidString)"))
        XCTAssertTrue(url.contains("name=New%20Name"))
        XCTAssertTrue(url.contains("description=New%20description"))
        XCTAssertTrue(url.contains("badge=WIP"))
        XCTAssertTrue(url.contains("column=Done"))
        XCTAssertTrue(url.contains("favourite=true"))
        XCTAssertTrue(url.contains("tag=status%3Dreviewed"))
        XCTAssertTrue(url.contains("initCommand="))
    }

    func testBuildUpdateURLFavouriteFalse() {
        let cardId = UUID()
        let url = URLOpener.buildUpdateURL(
            params: URLOpener.UpdateURLParams(
                cardId: cardId,
                favourite: false
            )
        )

        XCTAssertTrue(url.contains("favourite=false"))
    }

    func testBuildUpdateURLReplaceTags() {
        let cardId = UUID()
        let url = URLOpener.buildUpdateURL(
            params: URLOpener.UpdateURLParams(
                cardId: cardId,
                tags: [(key: "new", value: "tag")],
                replaceTags: true
            )
        )

        XCTAssertTrue(url.contains("replaceTags=true"))
        XCTAssertTrue(url.contains("tag=new%3Dtag"))
    }

    // MARK: - Move URL Tests

    func testBuildMoveURL() {
        let cardId = UUID()
        let url = URLOpener.buildMoveURL(cardId: cardId, column: "In Progress")

        XCTAssertTrue(url.starts(with: "termq://move?"))
        XCTAssertTrue(url.contains("id=\(cardId.uuidString)"))
        XCTAssertTrue(url.contains("column=In%20Progress"))
    }

    // MARK: - Focus URL Tests

    func testBuildFocusURL() {
        let cardId = UUID()
        let url = URLOpener.buildFocusURL(cardId: cardId)

        XCTAssertTrue(url.starts(with: "termq://focus?"))
        XCTAssertTrue(url.contains("id=\(cardId.uuidString)"))
    }

    // MARK: - Delete URL Tests

    func testBuildDeleteURLSoftDelete() {
        let cardId = UUID()
        let url = URLOpener.buildDeleteURL(cardId: cardId, permanent: false)

        XCTAssertTrue(url.starts(with: "termq://delete?"))
        XCTAssertTrue(url.contains("id=\(cardId.uuidString)"))
        XCTAssertTrue(url.contains("permanent=false"))
    }

    func testBuildDeleteURLPermanentDelete() {
        let cardId = UUID()
        let url = URLOpener.buildDeleteURL(cardId: cardId, permanent: true)

        XCTAssertTrue(url.starts(with: "termq://delete?"))
        XCTAssertTrue(url.contains("id=\(cardId.uuidString)"))
        XCTAssertTrue(url.contains("permanent=true"))
    }

    func testBuildDeleteURLDefaultIsSoftDelete() {
        let cardId = UUID()
        let url = URLOpener.buildDeleteURL(cardId: cardId)

        XCTAssertTrue(url.contains("permanent=false"))
    }

    // MARK: - waitForCondition Tests

    func testWaitForConditionSucceedsImmediately() async {
        var callCount = 0
        let result = await URLOpener.waitForCondition(maxAttempts: 4, initialDelayMs: 10) {
            callCount += 1
            return true  // Succeeds immediately
        }

        XCTAssertTrue(result)
        XCTAssertEqual(callCount, 1)
    }

    func testWaitForConditionSucceedsAfterRetries() async {
        var callCount = 0
        let result = await URLOpener.waitForCondition(maxAttempts: 4, initialDelayMs: 10) {
            callCount += 1
            return callCount >= 3  // Succeeds on 3rd attempt
        }

        XCTAssertTrue(result)
        XCTAssertEqual(callCount, 3)
    }

    func testWaitForConditionFailsAfterMaxAttempts() async {
        var callCount = 0
        let result = await URLOpener.waitForCondition(maxAttempts: 3, initialDelayMs: 10) {
            callCount += 1
            return false  // Never succeeds
        }

        XCTAssertFalse(result)
        XCTAssertEqual(callCount, 3)
    }

    func testWaitForConditionHandlesThrowingCondition() async {
        struct TestError: Error {}
        var callCount = 0
        let result = await URLOpener.waitForCondition(maxAttempts: 3, initialDelayMs: 10) {
            callCount += 1
            if callCount < 3 {
                throw TestError()  // Throws for first 2 attempts
            }
            return true  // Succeeds on 3rd attempt
        }

        XCTAssertTrue(result)
        XCTAssertEqual(callCount, 3)
    }

    func testWaitForConditionRespectsMaxAttempts() async {
        var callCount = 0
        _ = await URLOpener.waitForCondition(maxAttempts: 2, initialDelayMs: 10) {
            callCount += 1
            return false
        }

        XCTAssertEqual(callCount, 2)  // Should only try twice
    }
}
