import Foundation
import XCTest

@testable import TermQShared

final class WheelhouseInboxTests: XCTestCase {

    func testParsesReadyBeadsAndLeavesOutEpics() {
        let json = """
            [
              {"id": "ynw-g7rr", "title": "Merge ynm #118", "priority": 1, "issue_type": "task",
               "assignee": "stakker", "created_by": "ynw", "external_ref": "https://github.com/eyelock/ynm/pull/118",
               "labels": ["inbox", "inbox:merge", "repo:ynm"], "dependent_count": 2,
               "description": "Why", "notes": ""},
              {"id": "ynw-e", "title": "An epic", "issue_type": "epic", "assignee": "stakker"},
              {"id": "ynw-q11y", "title": "No labels", "issue_type": "task"}
            ]
            """
        let items = WheelhouseInbox.parse(Data(json.utf8), assignee: "stakker")
        XCTAssertEqual(items?.map(\.id), ["ynw-g7rr", "ynw-q11y"])
        let first = items?.first
        XCTAssertEqual(first?.kind, "merge")
        XCTAssertEqual(first?.priority, 1)
        XCTAssertEqual(first?.askedBy, "ynw")
        XCTAssertEqual(first?.unblocks, 2)
        XCTAssertEqual(first?.details, "Why")
        XCTAssertNil(first?.notes)
        XCTAssertEqual(first?.externalRefShortName, "ynm #118")
        XCTAssertNil(items?.last?.kind)
        XCTAssertEqual(items?.last?.assignee, "stakker")
    }

    func testUnreadableOutputIsNilNotEmpty() {
        XCTAssertNil(WheelhouseInbox.parse(Data("oops".utf8), assignee: "stakker"))
        XCTAssertEqual(WheelhouseInbox.parse(Data("[]".utf8), assignee: "stakker"), [])
        XCTAssertEqual(WheelhouseInbox.parse(Data(#"{"data": []}"#.utf8), assignee: "stakker"), [])
    }

    func testMergeDedupesAndPutsReportsLast() {
        let report = WheelhouseInboxItem(id: "r", title: "R", kind: "report", priority: 0, assignee: "stakker")
        let low = WheelhouseInboxItem(id: "l", title: "L", priority: 3, assignee: "stakker")
        let high = WheelhouseInboxItem(id: "h", title: "H", priority: 1, assignee: "david")
        let merged = WheelhouseInbox.merge([[report, low], [high, low]])
        XCTAssertEqual(merged.map(\.id), ["h", "l", "r"])
    }

    func testAssigneesTrimAndSkipBlanksAndRepeats() {
        XCTAssertEqual(WheelhouseInbox.assignees(humanName: " stakker ", ownName: ""), ["stakker"])
        XCTAssertEqual(WheelhouseInbox.assignees(humanName: "stakker", ownName: "david"), ["stakker", "david"])
        XCTAssertEqual(WheelhouseInbox.assignees(humanName: "david", ownName: "david"), ["david"])
        XCTAssertEqual(WheelhouseInbox.assignees(humanName: "", ownName: ""), [])
    }

    func testShortNamesForLinks() {
        func short(_ ref: String) -> String? {
            WheelhouseInboxItem(id: "x", title: "T", assignee: "a", externalRef: ref).externalRefShortName
        }
        XCTAssertEqual(short("https://github.com/eyelock/ynh/issues/769"), "ynh #769")
        XCTAssertEqual(short("https://github.com/eyelock/ynh/actions/runs/42267428876"), "ynh run 42267428876")
        XCTAssertEqual(short("https://github.com/eyelock/ynh/commit/b657636abcdef"), "ynh b657636")
        XCTAssertNil(short("https://example.com/a/b/pull/1"))
    }
    func testResponseArguments() {
        XCTAssertEqual(
            WheelhouseInbox.arguments(for: .comment("  Go with A  "), id: "ynw-1", actor: "stakker"),
            ["comments", "add", "ynw-1", "--actor", "stakker", "--", "Go with A"])
        XCTAssertNil(WheelhouseInbox.arguments(for: .comment("   "), id: "ynw-1", actor: "stakker"))
        XCTAssertEqual(
            WheelhouseInbox.arguments(for: .close(reason: ""), id: "ynw-1", actor: "david"),
            ["close", "ynw-1", "--actor", "david"])
        XCTAssertEqual(
            WheelhouseInbox.arguments(for: .close(reason: "Merged "), id: "ynw-1", actor: "stakker"),
            ["close", "ynw-1", "--reason", "Merged", "--actor", "stakker"])
    }
}
