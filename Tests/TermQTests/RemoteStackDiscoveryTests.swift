import XCTest

@testable import TermQ
@testable import TermQShared

/// Decoding for `repos/{owner}/{repo}/stacks`, captured from the live endpoint.
///
/// This is a preview API, so leniency is the point being tested: a renamed or missing
/// field must cost the Check Out Whole Stack affordance, never break the pull request feed
/// the menu item sits inside.
@MainActor
final class RemoteStackDiscoveryTests: XCTestCase {
    /// Captured 2026-08-01 from a live repository with two stacks.
    private let live = """
        [
          {
            "id": 96127,
            "number": 6,
            "node_id": "PRS_kwDOTpqvdM4AAXd_",
            "url": "https://api.github.com/repos/example/repo/stacks/6",
            "base": {"ref": "main"},
            "open": true,
            "created_at": "2026-08-01T11:03:52Z",
            "pull_requests": [
              {"number": 4, "state": "open", "draft": false, "merged_at": null,
               "head": {"ref": "link-a", "sha": "996e497"}},
              {"number": 5, "state": "open", "draft": false, "merged_at": null,
               "head": {"ref": "link-b", "sha": "1c5c996"}}
            ]
          },
          {
            "id": 91470,
            "number": 3,
            "base": {"ref": "main"},
            "open": false,
            "pull_requests": [
              {"number": 1, "state": "closed", "draft": false,
               "merged_at": "2026-08-01T07:52:47Z", "head": {"ref": "stack-a"}}
            ]
          }
        ]
        """

    private func decode(_ json: String) -> [RemoteStack] {
        RemoteStackDiscoveryService.decodeStacks(Data(json.utf8))
    }

    func testDecodesLivePayload() {
        let stacks = decode(live)
        XCTAssertEqual(stacks.map(\.number), [6, 3])
        XCTAssertEqual(stacks[0].baseRef, "main")
        XCTAssertTrue(stacks[0].isOpen)
        XCTAssertEqual(stacks[0].pullRequests.map(\.number), [4, 5])
        XCTAssertEqual(stacks[0].pullRequests[0].headRef, "link-a")
    }

    func testMergedAtBecomesIsMerged() {
        // The REST shape reports a timestamp rather than a boolean, and `null` for
        // unmerged — unlike `gh pr view`, which omits `merged` entirely.
        let stacks = decode(live)
        XCTAssertFalse(stacks[0].pullRequests[0].isMerged)
        XCTAssertTrue(stacks[1].pullRequests[0].isMerged)
    }

    func testFindsTheStackContainingAPullRequest() {
        // The one query the Remote PRs feed actually asks.
        let stacks = decode(live)
        XCTAssertEqual(stacks.first { $0.contains(prNumber: 5) }?.number, 6)
        XCTAssertEqual(stacks.first { $0.contains(prNumber: 1) }?.number, 3)
        XCTAssertNil(stacks.first { $0.contains(prNumber: 999) })
    }

    func testRemoteStackIDIsTheNumber() {
        // What `gh stack checkout` is given. Anything else would fail to resolve.
        XCTAssertEqual(decode(live)[0].remoteStackID, "6")
    }

    // MARK: - Preview-API leniency

    func testStackWithoutANumberIsDropped() {
        // `gh stack checkout` addresses stacks by number and nothing else, so a stack
        // without one cannot be acted on — dropping it is better than offering a
        // menu item that cannot work.
        let stacks = decode(
            """
            [{"base": {"ref": "main"}, "pull_requests": [{"number": 1}]}]
            """)
        XCTAssertTrue(stacks.isEmpty)
    }

    func testUnknownAndMissingFieldsDegradeRatherThanFail() {
        // A future field, and several absent ones. The feed must survive both.
        let stacks = decode(
            """
            [{"number": 9, "some_new_field": {"x": 1},
              "pull_requests": [{"number": 2}]}]
            """)
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks[0].baseRef, "")
        XCTAssertTrue(stacks[0].isOpen, "absent `open` reads as open")
        XCTAssertEqual(stacks[0].pullRequests[0].headRef, "")
        XCTAssertFalse(stacks[0].pullRequests[0].isMerged)
    }

    func testMalformedPayloadYieldsNoStacks() {
        // A 404 body (stacked PRs not enabled) or an error object must read as
        // "no stacks here", which is a normal state, not a failure to report.
        XCTAssertTrue(decode("{\"message\": \"Not Found\"}").isEmpty)
        XCTAssertTrue(decode("not json at all").isEmpty)
        XCTAssertTrue(decode("[]").isEmpty)
    }

    func testPullRequestWithoutANumberIsSkipped_butTheStackSurvives() {
        let stacks = decode(
            """
            [{"number": 9, "pull_requests": [{"number": 2}, {"state": "open"}]}]
            """)
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks[0].pullRequests.map(\.number), [2])
    }
}
