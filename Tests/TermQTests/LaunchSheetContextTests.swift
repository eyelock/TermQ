import XCTest

@testable import TermQ
@testable import TermQShared

/// The one launch sheet is built from several places; each context turns on
/// only the choices that make sense there.
@MainActor
final class LaunchSheetContextTests: XCTestCase {
    func testAHarnessLaunchChoosesItsFolderBackendAndResume() {
        let context = RunWithFocusContext(
            harnessId: "local/babelfish-dev", workingDirectory: nil, branch: nil, vendorOverride: "claude")

        XCTAssertEqual(context.preferredHarnessId, "local/babelfish-dev")
        XCTAssertEqual(context.workingDirectory, NSHomeDirectory(), "no folder given: start at home")
        XCTAssertTrue(context.choosesDirectory)
        XCTAssertTrue(context.choosesBackend)
        XCTAssertTrue(context.offersResume)
        XCTAssertEqual(context.vendorOverride, "claude")
        XCTAssertFalse(context.fixesHarness)
        XCTAssertNil(context.card)
    }

    func testASeatLaunchFixesItsHarnessAndFolderAndOffersResume() {
        let seat = WheelhouseSeat(name: "Eno", group: .crew, command: "eno")
        let wheelhouse = Wheelhouse(root: "/w/ynw", roster: WheelhouseRoster(seats: [seat]))

        let context = RunWithFocusContext(seat: seat, in: wheelhouse, harnessId: "local/eno")

        XCTAssertEqual(context.workingDirectory, "/w/ynw")
        XCTAssertEqual(context.preferredHarnessId, "local/eno")
        XCTAssertTrue(context.fixesHarness)
        XCTAssertFalse(context.choosesDirectory)
        XCTAssertTrue(context.offersResume)
        XCTAssertEqual(context.seat?.seat.command, "eno")
    }

    func testAPlainLaunchConfigDefaultsToAFreshStart() {
        let config = HarnessLaunchConfig(
            harnessID: "local/eno", vendorID: "", defaultVendor: "claude", focus: "wake", profile: nil,
            workingDirectory: "/w/ynw", prompt: nil, instructions: nil, backend: .direct, branch: nil,
            interactive: true, cardTitle: "Eno")

        XCTAssertFalse(config.resumeSession)
        XCTAssertEqual(config.command(), "ynh run local/eno --focus wake --interactive")
    }
}
