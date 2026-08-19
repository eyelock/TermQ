import XCTest

@testable import TermQ
@testable import TermQShared

/// Covers filling a stack branch's change request in from TermQ's own PR data.
///
/// `gh stack link` says of itself that it "does not rely on gh-stack local tracking
/// state": it registers the stack on GitHub and writes nothing locally. So immediately
/// after a successful link the tracking file still reports no pull request for a branch
/// that has just had one opened, and the sidebar showed "no PR" against it.
///
/// Every gh-stack command that would reconcile this carries a side effect TermQ must not
/// apply unasked — `sync` force-pushes, `checkout` moves HEAD, `init` refuses once a
/// branch is tracked — so this shows what is already known instead of mutating the
/// repository to make the tracking file true.
@MainActor
final class StackPullRequestAdoptionTests: XCTestCase {

    private func branch(
        _ name: String, changeRequest: StackChangeRequest? = nil, remoteStackID: String? = nil
    ) -> StackBranch {
        StackBranch(
            name: name, isCurrent: false, checkedOutElsewhere: nil, parent: nil, children: [],
            needsRestack: false, changeRequest: changeRequest, push: nil, isQueued: false,
            remoteStackID: remoteStackID)
    }

    func testABranchWithNoTrackedChangeRequestAdoptsItsOpenPullRequest() {
        let graph = StackGraph(branches: [branch("link-a"), branch("link-b")])

        let result = WorktreeSidebarViewModel.adoptingPullRequests(
            in: graph, openPRNumbersByBranch: ["link-a": 116, "link-b": 117])

        XCTAssertEqual(result.branch(named: "link-a")?.changeRequest?.id, "116")
        XCTAssertEqual(result.branch(named: "link-b")?.changeRequest?.id, "117")
        XCTAssertEqual(result.branch(named: "link-b")?.changeRequest?.status, .open)
    }

    /// The provider's own value carries a URL and a real status — merged, closed — that a
    /// list of open pull requests cannot. It must never be overwritten.
    func testATrackedChangeRequestIsNeverOverwritten() {
        let tracked = StackChangeRequest(
            id: "99", url: "https://example.com/99", status: .merged, commentCount: 3)
        let graph = StackGraph(branches: [branch("tracked", changeRequest: tracked)])

        let result = WorktreeSidebarViewModel.adoptingPullRequests(
            in: graph, openPRNumbersByBranch: ["tracked": 116])

        XCTAssertEqual(result.branch(named: "tracked")?.changeRequest, tracked)
    }

    func testABranchWithNoPullRequestIsLeftAlone() {
        let graph = StackGraph(branches: [branch("lonely")])

        let result = WorktreeSidebarViewModel.adoptingPullRequests(
            in: graph, openPRNumbersByBranch: ["somewhere-else": 5])

        XCTAssertNil(result.branch(named: "lonely")?.changeRequest)
    }

    /// Regression guard. `remoteStackID` is the last parameter of `StackBranch.init` AND
    /// defaulted, so a memberwise rebuild that forgets it compiles silently and blanks the
    /// stack number on every branch — which hides Merge Stack and Check Out Whole Stack,
    /// since both gate on it. That exact bug shipped once already.
    func testAdoptionPreservesEveryOtherFieldIncludingTheStackNumber() {
        let original = StackBranch(
            name: "b", isCurrent: true, checkedOutElsewhere: "/tmp/wt", parent: "a",
            children: ["c"], needsRestack: true, changeRequest: nil,
            push: StackPushState(ahead: 2, behind: 1, needsPush: true), isQueued: true,
            remoteStackID: "42")
        let graph = StackGraph(branches: [original])

        let result = WorktreeSidebarViewModel.adoptingPullRequests(
            in: graph, openPRNumbersByBranch: ["b": 7])
        let filled = result.branch(named: "b")

        XCTAssertEqual(filled?.changeRequest?.id, "7", "the pull request should have been adopted")
        XCTAssertEqual(filled?.remoteStackID, "42", "the stack number must survive adoption")
        XCTAssertEqual(filled?.isCurrent, true)
        XCTAssertEqual(filled?.checkedOutElsewhere, "/tmp/wt")
        XCTAssertEqual(filled?.parent, "a")
        XCTAssertEqual(filled?.children, ["c"])
        XCTAssertEqual(filled?.needsRestack, true)
        XCTAssertEqual(filled?.isQueued, true)
        XCTAssertEqual(filled?.push?.ahead, 2)
        XCTAssertEqual(filled?.push?.behind, 1)
    }

    // MARK: - Merged marking

    func testAMergedChangeRequestIsReportedAsMerged() {
        let open = StackChangeRequest(
            id: "112", url: "https://example.com/112", status: .open, commentCount: 2)
        let graph = StackGraph(branches: [branch("schema", changeRequest: open)])

        let result = WorktreeSidebarViewModel.markingMerged(in: graph, mergedIDs: ["112"])
        let cr = result.branch(named: "schema")?.changeRequest

        XCTAssertEqual(cr?.status, .merged)
        XCTAssertEqual(cr?.url, "https://example.com/112", "the URL must survive")
        XCTAssertEqual(cr?.commentCount, 2, "the comment count must survive")
    }

    func testAChangeRequestThatWasNotMergedIsUntouched() {
        let open = StackChangeRequest(id: "116", url: nil, status: .open, commentCount: nil)
        let graph = StackGraph(branches: [branch("other", changeRequest: open)])

        let result = WorktreeSidebarViewModel.markingMerged(in: graph, mergedIDs: ["112"])

        XCTAssertEqual(result.branch(named: "other")?.changeRequest?.status, .open)
    }

    func testMergedMarkingPreservesTheStackNumber() {
        let open = StackChangeRequest(id: "112", url: nil, status: .open, commentCount: nil)
        let original = StackBranch(
            name: "schema", isCurrent: false, checkedOutElsewhere: nil, parent: nil,
            children: ["api"], needsRestack: false, changeRequest: open, push: nil,
            isQueued: false, remoteStackID: "115")

        let result = WorktreeSidebarViewModel.markingMerged(
            in: StackGraph(branches: [original]), mergedIDs: ["112"])

        XCTAssertEqual(result.branch(named: "schema")?.changeRequest?.status, .merged)
        XCTAssertEqual(result.branch(named: "schema")?.remoteStackID, "115")
        XCTAssertEqual(result.branch(named: "schema")?.children, ["api"])
    }

    func testNoMergedIDsLeavesTheGraphIdentical() {
        let open = StackChangeRequest(id: "112", url: nil, status: .open, commentCount: nil)
        let graph = StackGraph(branches: [branch("schema", changeRequest: open)])

        XCTAssertEqual(WorktreeSidebarViewModel.markingMerged(in: graph, mergedIDs: []), graph)
    }

    func testAnEmptyPullRequestListLeavesTheGraphIdentical() {
        let graph = StackGraph(branches: [branch("a"), branch("b")])

        let result = WorktreeSidebarViewModel.adoptingPullRequests(
            in: graph, openPRNumbersByBranch: [:])

        XCTAssertEqual(result, graph)
    }
}
