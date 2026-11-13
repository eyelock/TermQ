import XCTest

@testable import TermQShared

/// The Attention list highlights the review request the selected terminal is
/// working on.
final class ReviewRequestFocusTests: XCTestCase {
    private func request(_ repository: String, _ number: Int) -> ReviewRequest {
        ReviewRequest(
            number: number, title: "PR \(number)", url: "https://github.com/\(repository)/pull/\(number)",
            repository: repository, author: nil, isDraft: false, createdAt: Date(timeIntervalSince1970: 0))
    }

    private let checkouts = "/Users/me/.termq/focus-worktrees"

    func testATerminalInAReviewCheckoutMatchesByFolderName() {
        let requests = [request("Org/admin-ted-claude-config", 88), request("Org/admin-ted-claude-config", 84)]
        let directory = "\(checkouts)/termq-focus--github.com--Org--admin-ted-claude-config--gmat-feat--84"

        let match = ReviewRequests.request(workingIn: directory, among: requests, folders: { _ in [] })

        XCTAssertEqual(match?.number, 84)
    }

    func testFolderNameMatchIgnoresCase() {
        let directory = "\(checkouts)/termq-focus--github.com--org--repo--fix--7"
        XCTAssertEqual(
            ReviewRequests.request(workingIn: directory, among: [request("Org/Repo", 7)], folders: { _ in [] })?
                .number, 7)
    }

    func testTheSameNumberInAnotherRepositoryDoesNotMatch() {
        let directory = "\(checkouts)/termq-focus--github.com--Org--other--fix--7"
        XCTAssertNil(
            ReviewRequests.request(workingIn: directory, among: [request("Org/repo", 7)], folders: { _ in [] }))
    }

    func testATerminalInsideAKnownFolderMatches() {
        let target = request("Org/repo", 12)
        let folders: (ReviewRequest) -> [String] = { $0.number == 12 ? ["/w/repo/.worktrees/feat-x"] : [] }

        XCTAssertEqual(
            ReviewRequests.request(workingIn: "/w/repo/.worktrees/feat-x/Sources", among: [target], folders: folders)?
                .number, 12)
        XCTAssertNil(
            ReviewRequests.request(workingIn: "/w/repo/.worktrees/feat-xy", among: [target], folders: folders),
            "a sibling folder sharing a prefix is not inside")
    }

    func testAnUnrelatedTerminalMatchesNothing() {
        XCTAssertNil(
            ReviewRequests.request(
                workingIn: "/Users/me/Documents", among: [request("Org/repo", 1)], folders: { _ in ["/w/repo"] }))
    }

    func testTheMostSpecificFolderWins() {
        let outer = request("Org/repo", 1)
        let inner = request("Org/repo", 2)
        let folders: (ReviewRequest) -> [String] = {
            $0.number == 1 ? ["/w/repo/.worktrees/a"] : ["/w/repo/.worktrees/a/nested"]
        }
        XCTAssertEqual(
            ReviewRequests.request(
                workingIn: "/w/repo/.worktrees/a/nested/src", among: [outer, inner], folders: folders)?
                .number, 2)
        XCTAssertEqual(
            ReviewRequests.request(workingIn: "/w/repo/.worktrees/a/src", among: [outer, inner], folders: folders)?
                .number, 1)
    }
}
