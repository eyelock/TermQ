import XCTest

@testable import TermQShared

/// Seat harnesses are pulled out of the Harnesses list into their
/// Wheelhouse's own group.
final class WheelhouseHarnessGroupingTests: XCTestCase {
    private func harness(_ name: String) -> Harness {
        Harness(
            name: name, version: "0.1.0", defaultVendor: "claude", path: "/h/\(name)",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0))
    }

    private func wheelhouse(_ root: String, seats: [String]) -> Wheelhouse {
        Wheelhouse(
            root: root,
            roster: WheelhouseRoster(seats: seats.map { WheelhouseSeat(name: $0, group: .crew, command: $0) }))
    }

    func testSeatHarnessesLeaveTheRestAndGroupByWheelhouse() {
        let harnesses = ["io", "agents-dev", "orion", "eno"].map(harness)
        let b2be = wheelhouse("/w/b2be", seats: ["io", "orion"])
        let ynw = wheelhouse("/w/ynw", seats: ["eno"])

        let result = WheelhouseHarnessGrouping.split(harnesses, wheelhouses: [b2be, ynw])

        XCTAssertEqual(result.others.map(\.name), ["agents-dev"])
        XCTAssertEqual(result.seatGroups.map(\.wheelhouse.root), ["/w/b2be", "/w/ynw"])
        XCTAssertEqual(result.seatGroups[0].harnesses.map(\.name), ["io", "orion"])
        XCTAssertEqual(result.seatGroups[1].harnesses.map(\.name), ["eno"])
    }

    func testAWheelhouseWithNoInstalledSeatHarnessGetsNoGroup() {
        let result = WheelhouseHarnessGrouping.split(
            [harness("agents-dev")], wheelhouses: [wheelhouse("/w/b2be", seats: ["io"])])
        XCTAssertTrue(result.seatGroups.isEmpty)
        XCTAssertEqual(result.others.map(\.name), ["agents-dev"])
    }

    func testAHarnessSharedByTwoWheelhousesIsListedOnceUnderTheFirst() {
        let result = WheelhouseHarnessGrouping.split(
            [harness("reviewer")],
            wheelhouses: [wheelhouse("/w/a", seats: ["reviewer"]), wheelhouse("/w/b", seats: ["reviewer"])])
        XCTAssertEqual(result.seatGroups.map(\.wheelhouse.root), ["/w/a"])
        XCTAssertTrue(result.others.isEmpty)
    }

    func testNoWheelhousesLeavesEveryHarnessWhereItWas() {
        let result = WheelhouseHarnessGrouping.split(["io", "orion"].map(harness), wheelhouses: [])
        XCTAssertTrue(result.seatGroups.isEmpty)
        XCTAssertEqual(result.others.map(\.name), ["io", "orion"])
    }

    func testWheelhouseOfFindsTheSeatsWheelhouse() {
        let b2be = wheelhouse("/w/b2be", seats: ["io"])
        XCTAssertEqual(WheelhouseHarnessGrouping.wheelhouse(of: harness("io"), in: [b2be])?.root, "/w/b2be")
        XCTAssertNil(WheelhouseHarnessGrouping.wheelhouse(of: harness("agents-dev"), in: [b2be]))
    }
}
