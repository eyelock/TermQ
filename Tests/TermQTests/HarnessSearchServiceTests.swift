import Foundation
import XCTest

@testable import TermQ

/// Tests for `HarnessSearchService` covering logic that does not require
/// subprocess execution: state management via `reset()`, and the guard
/// behaviour when the detector reports a non-ready status.
///
/// `YNHDetector.shared.status` starts as `.missing` in the test process,
/// so any `search(_:)` call resolves immediately with an empty result set —
/// which is the correct behaviour when the toolchain is absent.
@MainActor
final class HarnessSearchServiceTests: XCTestCase {

    // MARK: - reset()

    func test_reset_clearsResults() async {
        let service = HarnessSearchService()
        // Trigger a search that will bail early (detector is `.missing`)
        service.search("anything")
        // Give the Task a tick to settle
        await Task.yield()
        service.reset()
        XCTAssertTrue(service.results.isEmpty)
    }

    func test_reset_clearsError() async {
        let service = HarnessSearchService()
        service.search("query")
        await Task.yield()
        service.reset()
        XCTAssertNil(service.error)
    }

    func test_reset_clearsIsSearching() async {
        let service = HarnessSearchService()
        service.search("query")
        await Task.yield()
        service.reset()
        XCTAssertFalse(service.isSearching)
    }

    func test_reset_isIdempotent() {
        let service = HarnessSearchService()
        service.reset()
        service.reset()
        XCTAssertTrue(service.results.isEmpty)
        XCTAssertFalse(service.isSearching)
        XCTAssertNil(service.error)
    }

    // MARK: - search() guard: detector not ready

    func test_search_whenDetectorNotReady_resultsAreEmpty() async {
        // YNHDetector.shared.status == .missing in test process → guard fires
        let service = HarnessSearchService()
        service.search("termq")
        // Allow the async Task to complete
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(service.results.isEmpty)
    }

    func test_search_emptyQuery_whenDetectorNotReady_resultsAreEmpty() async {
        let service = HarnessSearchService()
        service.search("")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(service.results.isEmpty)
    }

    func test_search_whitespaceOnlyQuery_whenDetectorNotReady_resultsAreEmpty() async {
        let service = HarnessSearchService()
        service.search("   ")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(service.results.isEmpty)
    }

    // MARK: - Initial state

    func test_initialState_resultsEmpty() {
        let service = HarnessSearchService()
        XCTAssertTrue(service.results.isEmpty)
    }

    func test_initialState_notSearching() {
        let service = HarnessSearchService()
        XCTAssertFalse(service.isSearching)
    }

    func test_initialState_noError() {
        let service = HarnessSearchService()
        XCTAssertNil(service.error)
    }
}
