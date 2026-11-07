import XCTest

@testable import TermQ

@MainActor
final class TabManagerAttentionTests: XCTestCase {
    func testFirstBellSetsTheTimeAndLaterBellsKeepIt() async throws {
        let tabs = TabManager()
        let card = UUID()
        tabs.markNeedsAttention(card, currentSelection: nil)
        let first = try XCTUnwrap(tabs.attentionSince[card])
        try await Task.sleep(for: .milliseconds(20))
        tabs.markNeedsAttention(card, currentSelection: nil)
        XCTAssertEqual(tabs.attentionSince[card], first)
        XCTAssertTrue(tabs.needsAttention.contains(card))
    }

    func testBellFromTheSelectedCardIsIgnored() {
        let tabs = TabManager()
        let card = UUID()
        tabs.markNeedsAttention(card, currentSelection: card)
        XCTAssertNil(tabs.attentionSince[card])
        XCTAssertFalse(tabs.needsAttention.contains(card))
    }

    func testClearingAttentionClearsTheTime() {
        let tabs = TabManager()
        let card = UUID()
        tabs.markNeedsAttention(card, currentSelection: nil)
        tabs.clearAttention(card)
        XCTAssertNil(tabs.attentionSince[card])
        XCTAssertFalse(tabs.needsAttention.contains(card))
    }
}
