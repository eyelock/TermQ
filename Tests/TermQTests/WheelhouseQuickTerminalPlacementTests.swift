import Foundation
import SwiftUI
import TermQCore
import TermQShared
import XCTest

@testable import TermQ

/// Where a seat's Quick Terminals open: their own place on the stage, or a
/// panel beneath the seat.
@MainActor
final class WheelhouseQuickTerminalPlacementTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "WheelhouseQuickTerminalPlacementTests-\(UUID().uuidString)")
    }

    func testStagedIsTheDefaultAndThePlacementPersists() {
        XCTAssertEqual(WheelhouseStage(defaults: defaults).quickTerminalPlacement, .staged)
        WheelhouseStage(defaults: defaults).quickTerminalPlacement = .split
        XCTAssertEqual(WheelhouseStage(defaults: defaults).quickTerminalPlacement, .split)
    }

    func testStagedPutsTheQuickTerminalOnTheStage() {
        let stage = WheelhouseStage(defaults: defaults)
        let seat = UUID()
        let quick = UUID()
        stage.showQuickTerminal(quick, seatCard: seat)
        XCTAssertTrue(stage.isOnStage(quick))
        XCTAssertEqual(stage.focused, quick)
    }

    func testSplitShowsTheSeatWithItsPanelOnTheQuickTerminal() {
        let stage = WheelhouseStage(defaults: defaults)
        stage.quickTerminalPlacement = .split
        let seat = UUID()
        let quick = UUID()
        stage.toggleSplitCollapsed(seat)
        stage.showQuickTerminal(quick, seatCard: seat)
        XCTAssertTrue(stage.isOnStage(seat))
        XCTAssertFalse(stage.isOnStage(quick))
        XCTAssertEqual(stage.splitQuickTerminal(for: seat, among: [UUID(), quick]), quick)
        XCTAssertFalse(stage.splitCollapsed.contains(seat), "showing one opens the panel")
    }

    func testSplitWithoutASeatTerminalFallsBackToStaged() {
        let stage = WheelhouseStage(defaults: defaults)
        stage.quickTerminalPlacement = .split
        let quick = UUID()
        stage.showQuickTerminal(quick, seatCard: nil)
        XCTAssertTrue(stage.isOnStage(quick))
    }

    func testPanelShowsThePickedQuickTerminalElseTheFirst() {
        let stage = WheelhouseStage(defaults: defaults)
        let seat = UUID()
        let first = UUID()
        let second = UUID()
        XCTAssertEqual(stage.splitQuickTerminal(for: seat, among: [first, second]), first)
        stage.selectSplitQuickTerminal(second, for: seat)
        XCTAssertEqual(stage.splitQuickTerminal(for: seat, among: [first, second]), second)
        XCTAssertEqual(stage.splitQuickTerminal(for: seat, among: [first]), first, "a closed pick falls back")
        XCTAssertNil(stage.splitQuickTerminal(for: seat, among: []))
    }

    func testPanelHeightStaysBetweenAFifthAndFourFifths() {
        let stage = WheelhouseStage(defaults: defaults)
        let seat = UUID()
        XCTAssertEqual(stage.splitFraction(for: seat), WheelhouseStage.defaultSplitFraction)
        stage.setSplitFraction(0.95, for: seat)
        XCTAssertEqual(stage.splitFraction(for: seat), 0.8)
        stage.setSplitFraction(0.05, for: seat)
        XCTAssertEqual(stage.splitFraction(for: seat), 0.2)
    }

    func testCollapsingToggles() {
        let stage = WheelhouseStage(defaults: defaults)
        let seat = UUID()
        stage.toggleSplitCollapsed(seat)
        XCTAssertTrue(stage.splitCollapsed.contains(seat))
        stage.toggleSplitCollapsed(seat)
        XCTAssertFalse(stage.splitCollapsed.contains(seat))
    }

    // MARK: - Split with real cards

    private let ynw = Wheelhouse(
        root: "/w/ynw", roster: WheelhouseRoster(seats: [WheelhouseSeat(name: "Eno", group: .crew, command: "eno")]))

    private func tagged(_ tags: [(key: String, value: String)]) -> TerminalCard {
        TerminalCard(
            title: "card", tags: tags.map { Tag(key: $0.key, value: $0.value) }, columnId: UUID(),
            workingDirectory: "/w/ynw")
    }

    private func quick() -> TerminalCard {
        tagged(WheelhouseCardMatcher.quickTerminalTags(wheelhouseRoot: "/w/ynw", seatCommand: "eno", number: 1))
    }

    private func seatCard() -> TerminalCard {
        tagged(WheelhouseCardMatcher.tags(wheelhouseRoot: "/w/ynw", seatCommand: "eno"))
    }

    func testSplitHidesOnlyQuickTerminalsWhoseSeatHasACard() {
        let orphan = quick()
        XCTAssertEqual(
            WheelhouseStore.paneCards([orphan], placement: .split, all: [orphan], wheelhouses: [ynw]).map(\.id),
            [orphan.id], "no seat card to sit beneath: it stays a pane")
        let seat = seatCard()
        let hosted = quick()
        XCTAssertEqual(
            WheelhouseStore.paneCards([seat, hosted], placement: .split, all: [seat, hosted], wheelhouses: [ynw])
                .map(\.id), [seat.id])
        XCTAssertEqual(
            WheelhouseStore.paneCards([seat, hosted], placement: .staged, all: [seat, hosted], wheelhouses: [ynw])
                .count, 2)
        XCTAssertEqual(WheelhouseStore.splitHost(of: hosted, in: [seat, hosted], wheelhouses: [ynw])?.id, seat.id)
    }

    func testSwitchingToSplitMovesStagedQuickTerminalsIntoTheirPanels() {
        let stage = WheelhouseStage(defaults: defaults)
        let seat = UUID()
        let hosted = UUID()
        let orphan = UUID()
        stage.show(seat)
        stage.pin(seat)
        stage.show(orphan)
        stage.pin(orphan)
        stage.show(hosted)
        XCTAssertTrue(stage.isOnStage(orphan) && stage.isOnStage(hosted))
        stage.quickTerminalPlacement = .split
        stage.moveQuickTerminalsIntoPanels { $0 == hosted ? seat : nil }
        XCTAssertFalse(stage.isOnStage(hosted))
        XCTAssertTrue(stage.isOnStage(orphan))
        XCTAssertEqual(stage.focused, seat, "the moved one's seat takes the focus")
        XCTAssertEqual(stage.splitQuickTerminal(for: seat, among: [UUID(), hosted]), hosted)
    }

    func testClickingASplitQuickTerminalFocusesItsSeatAndAnswersItsBell() {
        let stage = WheelhouseStage(defaults: defaults)
        let tabs = TabManager()
        let seat = UUID()
        let other = UUID()
        let hosted = UUID()
        stage.show(seat)
        stage.pin(seat)
        stage.show(other)
        tabs.markStageBell(hosted)
        XCTAssertEqual(stage.paneClicked(hosted, host: seat, tabs: tabs), seat)
        XCTAssertFalse(tabs.needsAttention.contains(hosted))
        tabs.markStageBell(hosted)
        stage.paneTyped(hosted, host: seat, tabs: tabs)
        XCTAssertFalse(tabs.needsAttention.contains(hosted))
    }

    func testPanelHeightFitsThePane() {
        typealias Body = WheelhouseSplitSeatBody<EmptyView>
        XCTAssertEqual(Body.panelHeight(total: 600, fraction: 0.5, collapsed: false, strip: 26), 300)
        XCTAssertEqual(Body.panelHeight(total: 600, fraction: 0.5, collapsed: true, strip: 26), 26)
        XCTAssertEqual(Body.panelHeight(total: 60, fraction: 0.5, collapsed: false, strip: 26), 59)
        XCTAssertEqual(Body.panelHeight(total: 20, fraction: 0.5, collapsed: true, strip: 26), 19)
    }
}
