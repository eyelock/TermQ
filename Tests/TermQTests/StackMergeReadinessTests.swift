import XCTest

@testable import TermQ
@testable import TermQShared

@MainActor
final class StackMergeReadinessTests: XCTestCase {
    private func pr(
        _ number: Int,
        draft: Bool = false,
        state: String = "OPEN",
        review: StackReviewState = .approved,
        checks: StackCheckState = .passing
    ) -> StackPRReadiness {
        StackPRReadiness(
            number: number, title: "pr \(number)", branch: "feat-\(number)",
            isDraft: draft, state: state, review: review, checks: checks)
    }

    // MARK: - What blocks a stack merge

    func testDraftBlocks_andClosedBlocks() {
        XCTAssertTrue(pr(1, draft: true).blocksStackMerge)
        XCTAssertTrue(pr(1, state: "CLOSED").blocksStackMerge)
        XCTAssertTrue(pr(1, state: "MERGED").blocksStackMerge)
        XCTAssertFalse(pr(1).blocksStackMerge)
    }

    func testMissingReviewsAndFailingChecks_doNotBlock() {
        // Deliberate: branch protection varies per repository and TermQ cannot read it.
        // Showing these lets the user weigh them; predicting a refusal we are not sure
        // about would be worse than letting GitHub answer. gh-stack itself only checks
        // "open and not a draft" before merging.
        XCTAssertFalse(pr(1, review: .reviewRequired, checks: .failing).blocksStackMerge)
        XCTAssertFalse(pr(1, review: .changesRequested).blocksStackMerge)
    }

    // MARK: - Blocker identification

    func testCleanStack_mergesWhole() {
        let readiness = StackMergeReadiness(
            prs: [pr(1), pr(2), pr(3)], defaultMergeMethod: .squash)
        XCTAssertNil(readiness.blocker)
        XCTAssertTrue(readiness.canMergeWholeStack)
        XCTAssertEqual(readiness.mergeable.map(\.number), [1, 2, 3])
    }

    func testBlockerPartwayUp_isTheLowestOne() {
        // gh-stack refuses the whole-stack merge when a draft sits partway up. The sheet
        // needs the LOWEST blocker, because everything above it is unreachable too.
        let readiness = StackMergeReadiness(
            prs: [pr(1), pr(2, draft: true), pr(3), pr(4, state: "CLOSED")],
            defaultMergeMethod: nil)
        XCTAssertEqual(readiness.blocker?.number, 2)
        XCTAssertFalse(readiness.canMergeWholeStack)
    }

    func testMergeable_isEverythingBelowTheBlocker() {
        // What a partial merge WOULD cover — shown for information. TermQ does not run it:
        // `gh stack merge <n>` treats a bare number as a stack number first, so targeting
        // a PR whose number collides with a stack number would merge the wrong stack.
        let readiness = StackMergeReadiness(
            prs: [pr(1), pr(2), pr(3, draft: true), pr(4)], defaultMergeMethod: nil)
        XCTAssertEqual(readiness.mergeable.map(\.number), [1, 2])
    }

    func testBlockerAtTheBottom_leavesNothingMergeable() {
        let readiness = StackMergeReadiness(
            prs: [pr(1, draft: true), pr(2)], defaultMergeMethod: nil)
        XCTAssertEqual(readiness.blocker?.number, 1)
        XCTAssertTrue(readiness.mergeable.isEmpty)
    }

    func testEmptyStack_cannotMerge() {
        let readiness = StackMergeReadiness(prs: [], defaultMergeMethod: nil)
        XCTAssertFalse(readiness.canMergeWholeStack)
    }

    // MARK: - Decoding

    func testDecode_openApprovedPassing() throws {
        let json = """
            {
              "number": 12, "title": "Add thing", "headRefName": "feat-a",
              "isDraft": false, "state": "OPEN", "reviewDecision": "APPROVED",
              "statusCheckRollup": [
                {"status": "COMPLETED", "conclusion": "SUCCESS"},
                {"status": "COMPLETED", "conclusion": "SUCCESS"}
              ]
            }
            """
        let dto = try JSONDecoder().decode(StackPRReadinessDTO.self, from: Data(json.utf8))
        let readiness = dto.toReadiness()
        XCTAssertEqual(readiness.number, 12)
        XCTAssertEqual(readiness.review, .approved)
        XCTAssertEqual(readiness.checks, .passing)
        XCTAssertFalse(readiness.blocksStackMerge)
    }

    func testDecode_missingReviewDecision_readsAsNone() throws {
        // gh omits reviewDecision entirely when no review is required. That is "none",
        // not "review required" — reporting the stricter state would misinform.
        let json = """
            {"number": 3, "title": "t", "headRefName": "b", "isDraft": false, "state": "OPEN"}
            """
        let readiness = try JSONDecoder()
            .decode(StackPRReadinessDTO.self, from: Data(json.utf8)).toReadiness()
        XCTAssertEqual(readiness.review, .none)
        XCTAssertEqual(readiness.checks, .none)
    }

    func testDecode_absentState_defaultsToOpen() throws {
        // Reporting a PR as closed because a field could not be read would wrongly mark
        // the whole stack blocked. Absence must degrade to the permissive reading.
        let json = """
            {"number": 3}
            """
        let readiness = try JSONDecoder()
            .decode(StackPRReadinessDTO.self, from: Data(json.utf8)).toReadiness()
        XCTAssertEqual(readiness.state, "OPEN")
        XCTAssertFalse(readiness.blocksStackMerge)
    }

    // MARK: - Check roll-up

    func testRollUp_anyFailureWins() {
        let checks: [StackPRReadinessDTO.CheckDTO] = [
            .init(status: "COMPLETED", conclusion: "SUCCESS", state: nil),
            .init(status: "COMPLETED", conclusion: "FAILURE", state: nil),
            .init(status: "IN_PROGRESS", conclusion: nil, state: nil),
        ]
        XCTAssertEqual(StackPRReadinessDTO.rollUp(checks), .failing)
    }

    func testRollUp_stillRunningBeatsSuccess() {
        let checks: [StackPRReadinessDTO.CheckDTO] = [
            .init(status: "COMPLETED", conclusion: "SUCCESS", state: nil),
            .init(status: "IN_PROGRESS", conclusion: nil, state: nil),
        ]
        XCTAssertEqual(StackPRReadinessDTO.rollUp(checks), .pending)
    }

    func testRollUp_commitStatusStyleUsesStateField() {
        // The commit-status API reports `state` where the checks API reports `conclusion`.
        // A rollup mixes both shapes.
        XCTAssertEqual(
            StackPRReadinessDTO.rollUp([.init(status: nil, conclusion: nil, state: "FAILURE")]),
            .failing)
        XCTAssertEqual(
            StackPRReadinessDTO.rollUp([.init(status: nil, conclusion: nil, state: "SUCCESS")]),
            .passing)
    }

    func testRollUp_noChecksConfigured() {
        XCTAssertEqual(StackPRReadinessDTO.rollUp([]), .none)
    }
}
