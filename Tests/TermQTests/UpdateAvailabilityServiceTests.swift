import Foundation
import XCTest

@testable import TermQ

@MainActor
final class UnknownUpdateAvailabilityServiceTests: XCTestCase {
    func testStateForHarness_isIdle() {
        let service = UnknownUpdateAvailabilityService()
        XCTAssertEqual(service.state(forHarness: "any/harness/id"), .idle)
    }

    func testStateForInclude_isIdle() {
        let service = UnknownUpdateAvailabilityService()
        XCTAssertEqual(
            service.state(forInclude: "github.com/eyelock/assistants", inHarness: "h"),
            .idle)
    }

    func testRefresh_doesNotChangeState() async {
        let service = UnknownUpdateAvailabilityService()
        await service.refresh(harness: "h")
        XCTAssertEqual(service.state(forHarness: "h"), .idle)
    }

    func testInvalidate_doesNotChangeState() {
        let service = UnknownUpdateAvailabilityService()
        service.invalidate(harness: "h")
        XCTAssertEqual(service.state(forHarness: "h"), .idle)
    }
}
