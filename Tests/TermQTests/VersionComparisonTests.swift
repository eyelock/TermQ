import Sparkle
import XCTest

// Tests for Sparkle version comparison behaviour with the MAJOR.MINOR.PATCH.bN scheme.
//
// These tests run against the real SUStandardVersionComparator so any upstream
// change to Sparkle's algorithm is caught immediately.
//
// Regression guards (test_dashTruncation and test_gitSHA) document the original
// bugs — they must PASS (i.e. the bugs must remain bugs in the old format) to
// prove we have not accidentally changed comparator semantics.
final class VersionComparisonTests: XCTestCase {

    private let comparator = SUStandardVersionComparator.default

    // MARK: - Forward-looking correctness tests (new .bN scheme)

    func test_betaToBeta_newerDetected() {
        XCTAssertEqual(
            comparator.compareVersion("0.7.0.b8", toVersion: "0.7.0.b9"),
            .orderedAscending,
            "0.7.0.b8 should be older than 0.7.0.b9"
        )
    }

    func test_betaToStable_newerDetected() {
        XCTAssertEqual(
            comparator.compareVersion("0.7.0.b9", toVersion: "0.7.0"),
            .orderedAscending,
            "0.7.0.b9 should be older than 0.7.0 (stable)"
        )
    }

    func test_stableToNextBeta_newerDetected() {
        XCTAssertEqual(
            comparator.compareVersion("0.7.0", toVersion: "0.8.0.b1"),
            .orderedAscending,
            "0.7.0 should be older than 0.8.0.b1"
        )
    }

    func test_stableToStable_newerDetected() {
        XCTAssertEqual(
            comparator.compareVersion("0.7.0", toVersion: "0.7.1"),
            .orderedAscending,
            "0.7.0 should be older than 0.7.1"
        )
    }

    func test_sameVersion_notNewer() {
        XCTAssertEqual(
            comparator.compareVersion("0.7.0.b9", toVersion: "0.7.0.b9"),
            .orderedSame,
            "Same version should compare as equal"
        )
    }

    // MARK: - Regression guards (document old bugs — these behaviours must stay broken)

    func test_dashTruncation_provesWhyDashesBreak() {
        // SUStandardVersionComparator truncates at the first dash, so
        // "0.7.0-beta.8" and "0.7.0-beta.9" both reduce to "0.7.0" and
        // compare as equal. This means the dash format cannot distinguish
        // consecutive beta releases — which is why we use the .bN format.
        XCTAssertEqual(
            comparator.compareVersion("0.7.0-beta.8", toVersion: "0.7.0-beta.9"),
            .orderedSame,
            "Dashes cause truncation: both reduce to 0.7.0 and compare as equal"
        )
    }

    func test_gitSHA_comparesBroken() {
        // All historical beta SHAs start with a high hex digit, so Sparkle's
        // numeric comparator sees them as numerically larger than any sane version.
        // This is the root cause of 9 betas never offering an update.
        XCTAssertEqual(
            comparator.compareVersion("0.7.0-beta.9", toVersion: "8be83a1"),
            .orderedAscending,
            "Git SHA 8be83a1 must compare as numerically newer than 0.7.0-beta.9 (documents original bug)"
        )
    }

    // MARK: - Version conversion (tag → Sparkle format)

    func test_versionConversion() {
        XCTAssertEqual(sparkleVersion("0.7.0-beta.9"), "0.7.0.b9")
        XCTAssertEqual(sparkleVersion("0.7.0-beta.1"), "0.7.0.b1")
        XCTAssertEqual(sparkleVersion("0.7.0-alpha.3"), "0.7.0.a3")
        XCTAssertEqual(sparkleVersion("0.7.0-rc.2"), "0.7.0.rc2")
        XCTAssertEqual(sparkleVersion("0.7.0"), "0.7.0")
        XCTAssertEqual(sparkleVersion("1.0.0"), "1.0.0")
    }

    // MARK: - Private helpers

    /// Mirrors the conversion applied by Makefile / generate-appcast.sh / CI workflow:
    /// strips the leading "v" then converts dash pre-release notation to dot notation.
    ///   0.7.0-beta.9  →  0.7.0.b9
    ///   0.7.0-alpha.3 →  0.7.0.a3
    ///   0.7.0-rc.2    →  0.7.0.rc2
    ///   0.7.0         →  0.7.0
    private func sparkleVersion(_ tagVersion: String) -> String {
        tagVersion
            .replacingOccurrences(of: "-beta.", with: ".b")
            .replacingOccurrences(of: "-alpha.", with: ".a")
            .replacingOccurrences(of: "-rc.", with: ".rc")
    }
}
