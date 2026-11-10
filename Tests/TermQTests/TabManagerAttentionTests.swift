import AppKit
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

    func testStageBellCountsEvenForTheSelectedCard() {
        let tabs = TabManager()
        let card = UUID()
        tabs.markStageBell(card)
        XCTAssertTrue(tabs.needsAttention.contains(card))
        XCTAssertNotNil(tabs.attentionSince[card])
    }

    func testClickingTheFocusedRingingPaneClearsItsBell() throws {
        let (stage, tabs, card) = try ringingFocusedPane()
        XCTAssertNil(stage.paneClicked(card, tabs: tabs))
        XCTAssertFalse(tabs.needsAttention.contains(card))
    }

    func testClickingAnUnfocusedPaneAsksToFocusItAndLeavesTheBell() throws {
        let (stage, tabs, card) = try ringingFocusedPane()
        // Pinned, the first pane stays when another comes up beside it.
        stage.pin(card)
        let other = UUID()
        stage.show(other)
        stage.focus(card)
        XCTAssertTrue(stage.isOnStage(other))
        tabs.markStageBell(other)
        XCTAssertEqual(stage.paneClicked(other, tabs: tabs), other)
        XCTAssertTrue(tabs.needsAttention.contains(other))
    }

    func testTypingClearsOnlyAnOnStagePanesBell() throws {
        let (stage, tabs, card) = try ringingFocusedPane()
        let offStage = UUID()
        tabs.markStageBell(offStage)
        stage.paneTyped(offStage, tabs: tabs)
        XCTAssertTrue(tabs.needsAttention.contains(offStage))
        stage.paneTyped(card, tabs: tabs)
        XCTAssertFalse(tabs.needsAttention.contains(card))
    }

    /// A stage with one pane, focused and ringing.
    private func ringingFocusedPane() throws -> (WheelhouseStage, TabManager, UUID) {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TabManagerAttentionTests-\(UUID().uuidString)"))
        let stage = WheelhouseStage(defaults: defaults)
        let tabs = TabManager()
        let card = UUID()
        stage.show(card)
        stage.focus(card)
        tabs.markStageBell(card)
        return (stage, tabs, card)
    }

    func testPlainKeysCountAsTypingButCommandShortcutsDoNot() {
        XCTAssertTrue(StagePaneClickMonitor.countsAsTyping([]))
        XCTAssertTrue(StagePaneClickMonitor.countsAsTyping([.shift]))
        XCTAssertTrue(StagePaneClickMonitor.countsAsTyping([.control]))
        XCTAssertFalse(StagePaneClickMonitor.countsAsTyping([.command]))
        XCTAssertFalse(StagePaneClickMonitor.countsAsTyping([.command, .shift]))
    }
}
