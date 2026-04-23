import XCTest

@testable import TermQ

final class YNHDetectorSemverTests: XCTestCase {

    func test_equalVersions_returnZero() {
        XCTAssertEqual(YNHDetector.compareSemver("0.2.0", "0.2.0"), 0)
    }

    func test_higherPatch_returnsPositive() {
        XCTAssertGreaterThan(YNHDetector.compareSemver("0.2.1", "0.2.0"), 0)
    }

    func test_lowerMinor_returnsNegative() {
        XCTAssertLessThan(YNHDetector.compareSemver("0.1.9", "0.2.0"), 0)
    }

    func test_missingTrailingSegment_treatedAsZero() {
        XCTAssertEqual(YNHDetector.compareSemver("0.2", "0.2.0"), 0)
        XCTAssertEqual(YNHDetector.compareSemver("1", "1.0.0"), 0)
    }

    func test_nonNumericSegment_treatedAsZero() {
        // "0.2.0-rc1" splits to ["0","2","0-rc1"] → last parses as 0 (Int fails)
        XCTAssertEqual(YNHDetector.compareSemver("0.2.0-rc1", "0.2.0"), 0)
    }

    func test_majorVersionDominatesMinor() {
        XCTAssertGreaterThan(YNHDetector.compareSemver("1.0.0", "0.99.99"), 0)
    }
}

final class YNHDetectorCapabilityGateTests: XCTestCase {

    func test_nilCapabilities_failsGate() {
        XCTAssertFalse(YNHDetector.capabilityMeets(nil, minimum: "0.2.0"))
    }

    func test_emptyCapabilities_failsGate() {
        // Empty string splits to zero segments → all segments compare as zero →
        // "" compares equal to "0.0.0", which is below any non-zero minimum.
        XCTAssertFalse(YNHDetector.capabilityMeets("", minimum: "0.2.0"))
    }

    func test_belowMinimum_failsGate() {
        XCTAssertFalse(YNHDetector.capabilityMeets("0.1.9", minimum: "0.2.0"))
    }

    func test_equalMinimum_passesGate() {
        XCTAssertTrue(YNHDetector.capabilityMeets("0.2.0", minimum: "0.2.0"))
    }

    func test_aboveMinimum_passesGate() {
        XCTAssertTrue(YNHDetector.capabilityMeets("0.2.1", minimum: "0.2.0"))
        XCTAssertTrue(YNHDetector.capabilityMeets("1.0.0", minimum: "0.2.0"))
    }

    func test_shortCapabilityAgainstLongerMinimum_comparesEquivalently() {
        // "0.2" should satisfy "0.2.0" — trailing segments default to zero.
        XCTAssertTrue(YNHDetector.capabilityMeets("0.2", minimum: "0.2.0"))
    }

    func test_minimumVersionIsPublishedAsExpected() {
        // Guards against an accidental silent downgrade of the built-in gate;
        // bumping this value must be an explicit decision.
        XCTAssertEqual(YNHDetector.minimumCapabilitiesVersion, "0.2.0")
    }
}
