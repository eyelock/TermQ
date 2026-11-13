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

    // MARK: - Opening a seat: fresh unless the terminal is in use

    func testASeatWithNoCardLaunchesNew() {
        XCTAssertEqual(
            HarnessLaunchCoordinator.seatOpen(hasCard: false, running: false, hasFocusOrPrompt: false), .launchNew)
        XCTAssertEqual(
            HarnessLaunchCoordinator.seatOpen(hasCard: false, running: false, hasFocusOrPrompt: true), .launchNew)
    }

    func testASeatWhoseTerminalIsOffStartsFresh() {
        XCTAssertEqual(
            HarnessLaunchCoordinator.seatOpen(hasCard: true, running: false, hasFocusOrPrompt: false), .startFresh)
    }

    func testARunningSeatIsShownAndResumedIfOnlyItsShellIsLeft() {
        XCTAssertEqual(
            HarnessLaunchCoordinator.seatOpen(hasCard: true, running: true, hasFocusOrPrompt: false),
            .showResumingIfExited)
    }

    func testAFocusStartsAStoppedSeatOrIsSentToARunningOne() {
        XCTAssertEqual(
            HarnessLaunchCoordinator.seatOpen(hasCard: true, running: false, hasFocusOrPrompt: true), .startWithFocus)
        XCTAssertEqual(
            HarnessLaunchCoordinator.seatOpen(hasCard: true, running: true, hasFocusOrPrompt: true), .sendToSession)
    }
}
