import Foundation
import XCTest

@testable import TermQShared

final class WheelhouseWorkTests: XCTestCase {

    func testParsesPlainArrayKeyedByAssignee() {
        let json = """
            [
              {"id": "ynw-1", "title": "Fix vendor docs", "assignee": "hynde", "notes": ""},
              {"id": "ynw-2", "title": "Second", "assignee": "hynde"},
              {"id": "ynw-3", "title": "Design", "assignee": "eno", "notes": "x\\nPR: https://github.com/eyelock/ynh/pull/754\\n"},
              {"id": "ynw-4", "title": "Unassigned", "assignee": ""},
              {"id": "ynw-5", "title": "No assignee"},
              {"title": "No id", "assignee": "gahan"}
            ]
            """
        let work = WheelhouseWork.parseInProgress(Data(json.utf8))
        XCTAssertEqual(work.keys.sorted(), ["eno", "hynde"])
        XCTAssertEqual(work["hynde"]?.map(\.id), ["ynw-1", "ynw-2"])
        XCTAssertNil(work["hynde"]?.first?.pullRequestURL)
        XCTAssertEqual(work["eno"]?.first?.pullRequestURL, "https://github.com/eyelock/ynh/pull/754")
        XCTAssertEqual(work["eno"]?.first?.pullRequestShortName, "ynh #754")
    }

    func testParsesDataEnvelope() {
        let json = #"{"data": [{"id": "ynw-1", "title": "T", "assignee": "may"}]}"#
        XCTAssertEqual(WheelhouseWork.parseInProgress(Data(json.utf8))["may"]?.count, 1)
    }

    func testSortsFreshestHeartbeatFirst() {
        let json = """
            [
              {"id": "old", "title": "T", "assignee": "gahan", "heartbeat_at": "2026-11-07T09:37:24Z"},
              {"id": "none", "title": "T", "assignee": "gahan"},
              {"id": "new", "title": "T", "assignee": "gahan", "heartbeat_at": "2026-11-07T09:44:15.123Z"}
            ]
            """
        let beads = WheelhouseWork.parseInProgress(Data(json.utf8))["gahan"]
        XCTAssertEqual(beads?.map(\.id), ["new", "old", "none"])
        XCTAssertNotNil(beads?.first?.heartbeatAt)
    }

    func testWorkingMeansARecentHeartbeat() {
        let now = Date()
        let recent = WheelhouseBead(id: "a", title: "T", assignee: "x", heartbeatAt: now.addingTimeInterval(-9 * 60))
        let stale = WheelhouseBead(id: "b", title: "T", assignee: "x", heartbeatAt: now.addingTimeInterval(-3600))
        let never = WheelhouseBead(id: "c", title: "T", assignee: "x")
        XCTAssertTrue(recent.isWorking(now: now))
        XCTAssertFalse(stale.isWorking(now: now))
        XCTAssertFalse(never.isWorking(now: now))
    }

    func testGarbageGivesEmpty() {
        XCTAssertTrue(WheelhouseWork.parseInProgress(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(WheelhouseWork.parseInProgress(Data(#"{"other": 1}"#.utf8)).isEmpty)
    }

    func testLastPullRequestWins() {
        let notes = "PR: https://github.com/a/b/pull/1 then later PR: https://github.com/a/b/pull/2 and PR: not-a-url"
        XCTAssertEqual(WheelhouseWork.lastPullRequestURL(in: notes), "https://github.com/a/b/pull/2")
        XCTAssertNil(WheelhouseWork.lastPullRequestURL(in: "no pr here"))
    }

    func testShortNameNeedsAPullURL() {
        let issue = WheelhouseBead(
            id: "x", title: "t", assignee: "a", pullRequestURL: "https://github.com/eyelock/ynh/issues/12")
        XCTAssertNil(issue.pullRequestShortName)
    }

    func testFindBdUsesFirstExecutableCandidate() {
        XCTAssertNil(WheelhouseWork.findBd(candidates: ["/nonexistent/bd"]))
        XCTAssertEqual(WheelhouseWork.findBd(candidates: ["/nonexistent/bd", "/bin/sh"]), "/bin/sh")
    }

    func testConversationalGroups() {
        XCTAssertTrue(WheelhouseGroup.desk.isConversational)
        XCTAssertTrue(WheelhouseGroup.crew.isConversational)
        XCTAssertFalse(WheelhouseGroup.standing.isConversational)
        XCTAssertFalse(WheelhouseGroup.workers.isConversational)
        XCTAssertTrue(WheelhouseGroup.other("moot").isConversational)
    }

}

final class WheelhouseSeatHarnessTests: XCTestCase {
    func testParsesFocusesLaunchFocusFirst() throws {
        let json = """
            {"launch_focus": "wake", "focuses": {
              "verify": {"prompt": "Verify it."},
              "wake": {"prompt": "Begin."},
              "design": {"prompt": "Design it."},
              "broken": {"nope": 1}
            }}
            """
        let harness = try XCTUnwrap(WheelhouseSeatHarness.parse(Data(json.utf8)))
        XCTAssertEqual(harness.launchFocus, "wake")
        XCTAssertEqual(harness.focuses.map(\.name), ["wake", "design", "verify"])
        XCTAssertEqual(harness.focuses.first?.prompt, "Begin.")
    }

    func testNoFocusesIsEmptyAndNonObjectIsNil() {
        XCTAssertEqual(WheelhouseSeatHarness.parse(Data("{}".utf8))?.focuses, [])
        XCTAssertNil(WheelhouseSeatHarness.parse(Data("[1]".utf8)))
    }

    func testLoaderReadsSeatManifests() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-WheelhouseHarness-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = root.appendingPathComponent("skills/roster/assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let roster = """
            {"seats": [
              {"name": "May", "group": "standing", "command": "may", "harness": "harnesses/may"},
              {"name": "Eno", "group": "crew", "command": "eno", "harness": "harnesses/eno"}
            ]}
            """
        try Data(roster.utf8).write(to: assets.appendingPathComponent("roster.json"))
        let manifestDir = root.appendingPathComponent("harnesses/may/.agents/harness")
        try FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
        try Data(#"{"launch_focus": "wake", "focuses": {"wake": {"prompt": "Begin."}}}"#.utf8)
            .write(to: manifestDir.appendingPathComponent("plugin.json"))

        let wheelhouse = try XCTUnwrap(try WheelhouseLoader.load(root: root.path))
        let may = try XCTUnwrap(wheelhouse.seats.first { $0.command == "may" })
        let eno = try XCTUnwrap(wheelhouse.seats.first { $0.command == "eno" })
        XCTAssertEqual(wheelhouse.focuses(for: may).map(\.name), ["wake"])
        XCTAssertEqual(wheelhouse.focuses(for: eno), [])
    }
}

final class WheelhouseIdentityTests: XCTestCase {
    func testIdentityFromRecallOutput() {
        XCTAssertEqual(WheelhouseIdentity.hasIdentity(recallOutput: Data("[]".utf8)), false)
        XCTAssertEqual(WheelhouseIdentity.hasIdentity(recallOutput: Data(#"[{"memoryId": "x"}]"#.utf8)), true)
        XCTAssertNil(WheelhouseIdentity.hasIdentity(recallOutput: Data("oops".utf8)))
    }
}
