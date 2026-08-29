import XCTest

@testable import TermQCLICore

final class CLIHelpersTests: XCTestCase {

    // MARK: - parseTags

    func test_parseTags_empty_returnsEmpty() {
        XCTAssertTrue(parseTags([]).isEmpty)
    }

    func test_parseTags_singleValidTag_returnsTuple() {
        let result = parseTags(["key=value"])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].key, "key")
        XCTAssertEqual(result[0].value, "value")
    }

    func test_parseTags_multipleValidTags_returnsAllTuples() {
        let result = parseTags(["a=1", "b=2", "c=3"])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].key, "a")
        XCTAssertEqual(result[1].key, "b")
        XCTAssertEqual(result[2].key, "c")
    }

    func test_parseTags_tagWithoutEquals_skipped() {
        let result = parseTags(["invalidtag"])
        XCTAssertTrue(result.isEmpty)
    }

    func test_parseTags_mixedValidAndInvalid_onlyValidReturned() {
        let result = parseTags(["good=tag", "bad", "also=good"])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].key, "good")
        XCTAssertEqual(result[1].key, "also")
    }

    func test_parseTags_multipleEqualsInValue_splitsOnFirstOnly() {
        let result = parseTags(["key=a=b=c"])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].key, "key")
        XCTAssertEqual(result[0].value, "a=b=c")
    }

    func test_parseTags_emptyValue_skipped() {
        // split(separator:) omits trailing empty subsequences, so "key=" produces 1 part not 2
        let result = parseTags(["key="])
        XCTAssertTrue(result.isEmpty)
    }

    func test_parseTags_emptyKey_skipped() {
        // split(separator:) omits empty subsequences by default, so "=value" produces 1 part not 2
        let result = parseTags(["=value"])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - shouldUseDebugMode

    func test_shouldUseDebugMode_false_returnsFalseInRelease() {
        // In non-TERMQ_DEBUG_BUILD environments the explicit flag controls the result
        #if !TERMQ_DEBUG_BUILD
            XCTAssertFalse(shouldUseDebugMode(false))
            XCTAssertTrue(shouldUseDebugMode(true))
        #endif
    }

    // MARK: - waitForBoardCondition

    func test_waitForBoardCondition_conditionTrue_returnsTrueWithoutRetrying() {
        var evaluations = 0
        let result = waitForBoardCondition(maxAttempts: 4, initialDelayMs: 1) {
            evaluations += 1
            return true
        }

        XCTAssertTrue(result)
        XCTAssertEqual(evaluations, 1)
    }

    func test_waitForBoardCondition_conditionNeverTrue_returnsFalseAfterBudget() {
        var evaluations = 0
        let result = waitForBoardCondition(maxAttempts: 3, initialDelayMs: 1) {
            evaluations += 1
            return false
        }

        XCTAssertFalse(result)
        XCTAssertEqual(evaluations, 3)
    }

    func test_waitForBoardCondition_conditionBecomesTrue_returnsTrue() {
        var evaluations = 0
        let result = waitForBoardCondition(maxAttempts: 4, initialDelayMs: 1) {
            evaluations += 1
            return evaluations == 2
        }

        XCTAssertTrue(result)
        XCTAssertEqual(evaluations, 2)
    }

    /// A read can fail while the app is mid-write, which is a reason to look again rather than to
    /// call the command dropped.
    func test_waitForBoardCondition_conditionThrows_keepsRetrying() {
        struct ReadFailure: Error {}
        var evaluations = 0
        let result = waitForBoardCondition(maxAttempts: 4, initialDelayMs: 1) {
            evaluations += 1
            if evaluations == 1 { throw ReadFailure() }
            return true
        }

        XCTAssertTrue(result)
        XCTAssertEqual(evaluations, 2)
    }
}
