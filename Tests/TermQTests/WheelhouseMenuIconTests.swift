import AppKit
import XCTest

@testable import TermQ

/// Every Wheelhouse menu icon is a real SF Symbol, and the stage shortcuts
/// don't collide.
final class WheelhouseMenuIconTests: XCTestCase {
    private let all = [
        WheelhouseMenuIcon.openTerminal, WheelhouseMenuIcon.showTerminal, WheelhouseMenuIcon.birth,
        WheelhouseMenuIcon.wakeFocus, WheelhouseMenuIcon.focus, WheelhouseMenuIcon.handoff,
        WheelhouseMenuIcon.closeTerminal, WheelhouseMenuIcon.quickTerminal, WheelhouseMenuIcon.harnessDetails,
        WheelhouseMenuIcon.pin, WheelhouseMenuIcon.pinned, WheelhouseMenuIcon.copy,
        WheelhouseMenuIcon.revealInFinder, WheelhouseMenuIcon.sendToSeat, WheelhouseMenuIcon.comment,
        WheelhouseMenuIcon.closeBead, WheelhouseMenuIcon.openLink, WheelhouseMenuIcon.wheelhouse,
        WheelhouseMenuIcon.allWheelhouses, WheelhouseMenuIcon.add, WheelhouseMenuIcon.openInTerminal,
        WheelhouseMenuIcon.openIn, WheelhouseMenuIcon.install, WheelhouseMenuIcon.actionRequired,
        WheelhouseMenuIcon.zoom, WheelhouseMenuIcon.exitZoom,
    ]

    func testEveryIconIsASystemSymbol() {
        for name in all {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    func testCommonFocusesHaveTheirOwnIconsAndOthersShareOne() {
        XCTAssertEqual(WheelhouseMenuIcon.focus(named: "wake"), WheelhouseMenuIcon.wakeFocus)
        XCTAssertEqual(WheelhouseMenuIcon.focus(named: "Retro"), "clock.arrow.circlepath")
        XCTAssertEqual(WheelhouseMenuIcon.focus(named: "plan-release"), "shippingbox")
        XCTAssertEqual(WheelhouseMenuIcon.focus(named: "something-new"), WheelhouseMenuIcon.focus)
        for (name, symbol) in WheelhouseMenuIcon.focusSymbols {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), name)
        }
    }

    func testStageShortcutsAreDistinctCommandKeys() {
        let shortcuts = [
            WheelhouseStageShortcut.quickTerminal, WheelhouseStageShortcut.harnessDetails,
            WheelhouseStageShortcut.keepOnStage,
        ]
        XCTAssertEqual(Set(shortcuts.map(\.key.character)).count, shortcuts.count)
        for shortcut in shortcuts {
            XCTAssertEqual(shortcut.modifiers, .command)
        }
    }
}
