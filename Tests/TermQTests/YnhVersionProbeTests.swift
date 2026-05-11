import XCTest

@testable import TermQ

final class YnhVersionProbeTests: XCTestCase {
    func testNilCapabilities_notPhase1Capable() {
        XCTAssertFalse(YnhVersionProbe.supportsPhase1(nil))
    }

    func testBelowMinimum_notPhase1Capable() {
        XCTAssertFalse(YnhVersionProbe.supportsPhase1("0.2.0"))
        XCTAssertFalse(YnhVersionProbe.supportsPhase1("0.2.9"))
        XCTAssertFalse(YnhVersionProbe.supportsPhase1("0.1.0"))
    }

    func testExactMinimum_isPhase1Capable() {
        XCTAssertTrue(YnhVersionProbe.supportsPhase1("0.3.0"))
    }

    func testAboveMinimum_isPhase1Capable() {
        XCTAssertTrue(YnhVersionProbe.supportsPhase1("0.3.1"))
        XCTAssertTrue(YnhVersionProbe.supportsPhase1("0.4.0"))
        XCTAssertTrue(YnhVersionProbe.supportsPhase1("1.0.0"))
    }

    func testSemverComparison_correctOrdering() {
        XCTAssertTrue(YnhVersionProbe.semverAtLeast("1.0.0", minimum: "0.9.9"))
        XCTAssertTrue(YnhVersionProbe.semverAtLeast("0.10.0", minimum: "0.9.0"))
        XCTAssertFalse(YnhVersionProbe.semverAtLeast("0.9.9", minimum: "1.0.0"))
    }
}
