import Foundation
import TermQCore
import TermQShared
import XCTest

@testable import TermQ

/// The order of the stage's tab strip, which ⌘1–9 follow, and which
/// Wheelhouse the stage shows.
@MainActor
final class WheelhouseStripOrderTests: XCTestCase {
    private let ynw = Wheelhouse(
        root: "/w/ynw",
        roster: WheelhouseRoster(seats: [
            WheelhouseSeat(name: "Marr", group: .standing, command: "marr"),
            WheelhouseSeat(name: "Eno", group: .crew, command: "eno"),
            WheelhouseSeat(name: "Page", group: .crew, command: "page"),
            WheelhouseSeat(name: "Desk", group: .desk, command: "desk"),
        ]))
    private let other = Wheelhouse(
        root: "/w/other",
        roster: WheelhouseRoster(seats: [WheelhouseSeat(name: "Io", group: .desk, command: "io")]))

    private func seat(_ root: String, _ command: String) -> TerminalCard {
        TerminalCard(
            title: command,
            tags: WheelhouseCardMatcher.tags(wheelhouseRoot: root, seatCommand: command).map {
                Tag(key: $0.key, value: $0.value)
            },
            columnId: UUID(), workingDirectory: root)
    }

    func testOrderIsWheelhouseThenGroupThenRoster() {
        let cards = [
            seat("/w/other", "io"), seat("/w/ynw", "marr"), seat("/w/ynw", "page"), seat("/w/ynw", "desk"),
            seat("/w/ynw", "eno"),
        ]
        let ordered = WheelhouseStore.stripOrder(cards, wheelhouses: [ynw, other]).map(\.title)
        XCTAssertEqual(ordered, ["desk", "eno", "page", "marr", "io"])
    }

    func testNonSeatCardsAreLeftOut() {
        let plain = TerminalCard(title: "plain", columnId: UUID(), workingDirectory: "/w/ynw")
        XCTAssertTrue(WheelhouseStore.stripOrder([plain], wheelhouses: [ynw]).isEmpty)
    }

    func testScopeIsThePickedWheelhouseElseFirstInFocusModeElseAll() {
        let all = [ynw, other]
        XCTAssertEqual(WheelhouseStage.scopeRoot(selected: "/w/other", focusMode: false, wheelhouses: all), "/w/other")
        XCTAssertEqual(WheelhouseStage.scopeRoot(selected: "", focusMode: true, wheelhouses: all), "/w/ynw")
        XCTAssertNil(WheelhouseStage.scopeRoot(selected: "", focusMode: false, wheelhouses: all))
        XCTAssertNil(WheelhouseStage.scopeRoot(selected: "/w/gone", focusMode: false, wheelhouses: all))
    }

    func testPickedWheelhousePersists() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WheelhouseStripOrderTests-\(UUID().uuidString)"))
        WheelhouseStage(defaults: defaults).selectedRoot = "/w/ynw"
        XCTAssertEqual(WheelhouseStage(defaults: defaults).selectedRoot, "/w/ynw")
        XCTAssertEqual(defaults.string(forKey: WheelhouseStage.selectedRootKey), "/w/ynw")
    }

    func testStageMenuListsTheFirstNineSeatsByName() {
        let roster = (1...12).map { WheelhouseSeat(name: "Seat \($0)", group: .workers, command: "s\($0)") }
        let big = Wheelhouse(root: "/w/big", roster: WheelhouseRoster(seats: roster))
        let cards = (1...12).map { seat("/w/big", "s\($0)") }
        let items = WheelhouseStore.stageMenuItems(cards, wheelhouses: [big])
        XCTAssertEqual(items.count, 9)
        XCTAssertEqual(items.first?.title, "Seat 1")
        XCTAssertEqual(items.last?.title, "Seat 9")
        XCTAssertEqual(items.map(\.id), cards.prefix(9).map(\.id))
    }

    func testStageMenuFallsBackToTheCardTitle() {
        let unknown = seat("/w/gone", "ghost")
        XCTAssertEqual(WheelhouseStore.stageMenuItems([unknown], wheelhouses: [ynw]).first?.title, "ghost")
    }
}
