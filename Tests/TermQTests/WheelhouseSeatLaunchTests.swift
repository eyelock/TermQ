import XCTest

@testable import TermQ

@MainActor
final class WheelhouseSeatLaunchTests: XCTestCase {
    func testSessionNameIsReadFromStoredCommand() {
        XCTAssertEqual(
            HarnessLaunchCoordinator.sessionName(inCommand: "ynh run local/eno --session-name termq-f38e7dce"),
            "termq-f38e7dce")
        XCTAssertEqual(
            HarnessLaunchCoordinator.sessionName(
                inCommand: "ynh run local/eno --focus design --session-name termq-1 -- 'hi'"),
            "termq-1")
    }

    func testSessionNameMissingOrDangling() {
        XCTAssertNil(HarnessLaunchCoordinator.sessionName(inCommand: "ynh run local/eno"))
        XCTAssertNil(HarnessLaunchCoordinator.sessionName(inCommand: "ynh run local/eno --session-name"))
    }

    func testHandoffRequestMatchesTheHandoffSkillsTrigger() {
        XCTAssertEqual(HarnessLaunchCoordinator.handoffRequest, "Let's take a beat, and hand off.")
    }
}
