import Foundation
import XCTest

@testable import TermQShared

/// The Actions list: pull requests waiting on the human's review, grouped by
/// how long they have waited since the review was asked for.
final class ReviewRequestsTests: XCTestCase {
    private let iso = ISO8601DateFormatter()

    func testDecodesGhSearchOutput() throws {
        let json = """
            [{"author":{"login":"dependabot[bot]","is_bot":true},"createdAt":"2026-11-09T06:49:52Z","isDraft":false,
              "number":15,"repository":{"name":"actions","nameWithOwner":"eyelock/actions"},
              "title":"ci: Bump","url":"https://github.com/eyelock/actions/pull/15"},
             {"number":"broken"}]
            """
        let requests = try XCTUnwrap(ReviewRequests.decodeSearch(Data(json.utf8)))
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].repository, "eyelock/actions")
        XCTAssertEqual(requests[0].author, "dependabot[bot]")
        XCTAssertEqual(requests[0].createdAt, iso.date(from: "2026-11-09T06:49:52Z"))
        XCTAssertNil(ReviewRequests.decodeSearch(Data("{}".utf8)))
    }

    func testTimelineQueryAliasesEachPullRequest() {
        let query = ReviewRequests.timelineQuery(for: [
            request(1, repo: "eyelock/ynh"), request(2, repo: "acme/web"),
        ])
        XCTAssertTrue(query.contains("pr0: repository(owner: \"eyelock\", name: \"ynh\")"))
        XCTAssertTrue(query.contains("pr1: repository(owner: \"acme\", name: \"web\")"))
        XCTAssertTrue(query.contains("pullRequest(number: 2)"))
    }

    func testRequestTimeIsTheLatestToMeElseTheLatestToATeam() throws {
        let json = """
            {"data":{
              "pr0":{"pullRequest":{"timelineItems":{"nodes":[
                {"createdAt":"2026-11-01T10:00:00Z","requestedReviewer":{"login":"eyelock"}},
                {"createdAt":"2026-11-05T10:00:00Z","requestedReviewer":{"login":"someone"}},
                {"createdAt":"2026-11-03T10:00:00Z","requestedReviewer":{"login":"EyeLock"}}]}}},
              "pr1":{"pullRequest":{"timelineItems":{"nodes":[
                {"createdAt":"2026-11-02T10:00:00Z","requestedReviewer":{"slug":"core"}}]}}},
              "pr2":null}}
            """
        let times = ReviewRequests.requestTimes(fromGraphQL: Data(json.utf8), login: "eyelock")
        XCTAssertEqual(times[0], iso.date(from: "2026-11-03T10:00:00Z"))
        XCTAssertEqual(times[1], iso.date(from: "2026-11-02T10:00:00Z"))
        XCTAssertNil(times[2])
    }

    func testGroupsByWaitLongestFirst() throws {
        let now = try XCTUnwrap(iso.date(from: "2026-11-09T12:00:00Z"))
        var fresh = request(1, created: now.addingTimeInterval(-40 * 86400))
        fresh.requestedAt = now.addingTimeInterval(-3600)  // old PR, asked an hour ago
        let week = request(2, created: now.addingTimeInterval(-3 * 86400))
        let weekOlder = request(3, created: now.addingTimeInterval(-5 * 86400))
        let old = request(4, created: now.addingTimeInterval(-60 * 86400))
        let groups = ReviewRequests.grouped([fresh, week, weekOlder, old], now: now)
        XCTAssertEqual(groups.map(\.wait), [.today, .thisWeek, .older])
        XCTAssertEqual(groups[1].requests.map(\.number), [3, 2], "longest wait first")
        XCTAssertEqual(groups[0].requests.map(\.number), [1], "grouped by when asked, not when opened")
    }

    func testNameWithOwnerFromRemotes() {
        XCTAssertEqual(ReviewRequests.nameWithOwner(fromRemote: "git@github.com:eyelock/TermQ.git\n"), "eyelock/TermQ")
        XCTAssertEqual(ReviewRequests.nameWithOwner(fromRemote: "https://github.com/eyelock/ynh"), "eyelock/ynh")
        XCTAssertEqual(ReviewRequests.nameWithOwner(fromRemote: "https://github.com/eyelock/ynh/"), "eyelock/ynh")
        XCTAssertEqual(ReviewRequests.nameWithOwner(fromRemote: "ssh://git@github.com/a/b.git"), "a/b")
        XCTAssertEqual(ReviewRequests.nameWithOwner(fromRemote: "ssh://git@github.com:22/a/b.git"), "a/b")
        XCTAssertNil(ReviewRequests.nameWithOwner(fromRemote: "https://gitlab.com/a/b"))
        XCTAssertNil(ReviewRequests.nameWithOwner(fromRemote: "https://notgithub.com/a/b"))
        XCTAssertNil(ReviewRequests.nameWithOwner(fromRemote: "https://github.com.evil/a/b"))
    }

    func testTheTermQFilterIgnoresCase() {
        let requests = [request(1, repo: "eyelock/TermQ"), request(2, repo: "acme/web")]
        XCTAssertEqual(
            ReviewRequests.inRepositories(requests, names: ["EyeLock/termq"]).map(\.number), [1])
    }

    func testKnownTimesAreReusedAndTheRestAskedThenFilledByPosition() {
        let time = Date(timeIntervalSince1970: 1_000)
        var requests = [request(1), request(2), request(3)]
        let missing = ReviewRequests.applyKnown(&requests, known: [requests[1].url: time])
        XCTAssertEqual(missing, [0, 2])
        XCTAssertEqual(requests[1].requestedAt, time)
        let later = Date(timeIntervalSince1970: 2_000)
        ReviewRequests.applyTimes([1: later], to: &requests, asked: missing)
        XCTAssertNil(requests[0].requestedAt, "no time from GitHub: falls back to when it opened")
        XCTAssertEqual(requests[2].requestedAt, later)
    }

    func testTimelineQueryEscapesAndKeepsAliasesAligned() {
        let query = ReviewRequests.timelineQuery(for: [request(1, repo: "broken"), request(2, repo: "a\"b/c\\d")])
        XCTAssertFalse(query.contains("pr0:"), "a repository without an owner is skipped")
        XCTAssertTrue(query.contains("pr1: repository(owner: \"a\\\"b\", name: \"c\\\\d\")"), query)
    }

    func testPartialGraphQLDataStillCounts() {
        let json = """
            {"data":{"pr0":null,"pr1":{"pullRequest":{"timelineItems":{"nodes":[
              {"createdAt":"2026-11-02T10:00:00.123Z","requestedReviewer":null}]}}}},
             "errors":[{"message":"SAML enforcement"}]}
            """
        let times = ReviewRequests.requestTimes(fromGraphQL: Data(json.utf8), login: "eyelock")
        XCTAssertNil(times[0])
        XCTAssertNotNil(times[1], "fractional seconds parse, and a deleted reviewer still counts")
        XCTAssertTrue(ReviewRequests.requestTimes(fromGraphQL: Data("[]".utf8), login: "x").isEmpty)
    }

    func testWaitBoundaries() {
        let now = Date(timeIntervalSince1970: 100 * 86400)
        XCTAssertEqual(ReviewWait.of(now.addingTimeInterval(-86399), now: now), .today)
        XCTAssertEqual(ReviewWait.of(now.addingTimeInterval(-86400), now: now), .thisWeek)
        XCTAssertEqual(ReviewWait.of(now.addingTimeInterval(-7 * 86400), now: now), .thisMonth)
        XCTAssertEqual(ReviewWait.of(now.addingTimeInterval(-30 * 86400), now: now), .older)
    }

    func testDecodesDraftsAndMissingAuthors() throws {
        let json = """
            [{"createdAt":"2026-11-09T06:49:52Z","isDraft":true,"number":3,
              "repository":{"nameWithOwner":"a/b"},"title":"t","url":"https://github.com/a/b/pull/3"}]
            """
        let request = try XCTUnwrap(ReviewRequests.decodeSearch(Data(json.utf8))?.first)
        XCTAssertTrue(request.isDraft)
        XCTAssertNil(request.author)
    }

    private func request(_ number: Int, repo: String = "eyelock/ynh", created: Date = Date()) -> ReviewRequest {
        ReviewRequest(
            number: number, title: "PR \(number)", url: "https://github.com/\(repo)/pull/\(number)", repository: repo,
            author: "a", isDraft: false, createdAt: created)
    }
}
