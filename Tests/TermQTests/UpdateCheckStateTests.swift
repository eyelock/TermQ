import Foundation
import XCTest

@testable import TermQ

final class UpdateCheckStateTests: XCTestCase {
    func testEquality_idle() {
        XCTAssertEqual(UpdateCheckState.idle, .idle)
    }

    func testEquality_loading() {
        XCTAssertEqual(UpdateCheckState.loading, .loading)
    }

    func testEquality_stale() {
        XCTAssertEqual(UpdateCheckState.stale, .stale)
    }

    func testEquality_freshDistinguishesByDate() {
        let now = Date()
        let later = now.addingTimeInterval(60)
        XCTAssertEqual(UpdateCheckState.fresh(at: now), .fresh(at: now))
        XCTAssertNotEqual(UpdateCheckState.fresh(at: now), .fresh(at: later))
    }

    func testEquality_errorDistinguishesByReason() {
        XCTAssertEqual(
            UpdateCheckState.error(reason: "network"),
            .error(reason: "network"))
        XCTAssertNotEqual(
            UpdateCheckState.error(reason: "network"),
            .error(reason: "auth"))
    }

    func testEquality_distinctCasesNotEqual() {
        XCTAssertNotEqual(UpdateCheckState.idle, .loading)
        XCTAssertNotEqual(UpdateCheckState.loading, .stale)
        XCTAssertNotEqual(UpdateCheckState.stale, .fresh(at: Date()))
        XCTAssertNotEqual(UpdateCheckState.idle, .error(reason: "x"))
    }
}
