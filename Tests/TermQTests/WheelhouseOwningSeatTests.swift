import Foundation
import TermQCore
import TermQShared
import XCTest

@testable import TermQ

/// Which seat a stage card belongs to, and the focused-pane actions built on it.
@MainActor
final class WheelhouseOwningSeatTests: XCTestCase {
    private let wheelhouse = Wheelhouse(
        root: "/w/ynw",
        roster: WheelhouseRoster(seats: [
            WheelhouseSeat(name: "Eno", group: .crew, command: "eno"),
            WheelhouseSeat(name: "May", group: .standing, command: "may"),
        ]))

    private func card(_ tags: [(key: String, value: String)]) -> TerminalCard {
        TerminalCard(
            title: "card", tags: tags.map { Tag(key: $0.key, value: $0.value) }, columnId: UUID(),
            workingDirectory: "/w/ynw")
    }

    func testSeatCardBelongsToItsSeat() {
        let seat = card(WheelhouseCardMatcher.tags(wheelhouseRoot: "/w/ynw", seatCommand: "may"))
        XCTAssertEqual(WheelhouseStore.owningSeat(of: seat, in: [wheelhouse])?.seat.command, "may")
    }

    func testQuickTerminalBelongsToItsParentSeat() {
        let quick = card(
            WheelhouseCardMatcher.quickTerminalTags(wheelhouseRoot: "/w/ynw", seatCommand: "eno", number: 1))
        XCTAssertEqual(WheelhouseStore.owningSeat(of: quick, in: [wheelhouse])?.seat.command, "eno")
    }

    func testCardFromAnUnknownWheelhouseHasNoSeat() {
        let other = card(WheelhouseCardMatcher.tags(wheelhouseRoot: "/w/other", seatCommand: "may"))
        XCTAssertNil(WheelhouseStore.owningSeat(of: other, in: [wheelhouse]))
    }

    func testFocusedIdResolvesThroughTheCards() {
        let seat = card(WheelhouseCardMatcher.tags(wheelhouseRoot: "/w/ynw", seatCommand: "eno"))
        let found = WheelhouseStore.owningSeat(ofCardId: seat.id, in: [seat], wheelhouses: [wheelhouse])
        XCTAssertEqual(found?.seat.command, "eno")
        XCTAssertNil(WheelhouseStore.owningSeat(ofCardId: nil, in: [seat], wheelhouses: [wheelhouse]))
        XCTAssertNil(
            WheelhouseStore.owningSeat(ofCardId: WheelhouseStage.inboxEntry, in: [seat], wheelhouses: [wheelhouse]))
        seat.deletedAt = Date()
        XCTAssertNil(WheelhouseStore.owningSeat(ofCardId: seat.id, in: [seat], wheelhouses: [wheelhouse]))
    }

    func testPinningTheFocusedPaneSkipsTheInbox() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WheelhouseOwningSeatTests-\(UUID().uuidString)"))
        let stage = WheelhouseStage(defaults: defaults)
        stage.show(WheelhouseStage.inboxEntry)
        stage.focus(WheelhouseStage.inboxEntry)
        let inboxPinned = stage.isPinned(WheelhouseStage.inboxEntry)
        stage.togglePinFocused()
        XCTAssertEqual(stage.isPinned(WheelhouseStage.inboxEntry), inboxPinned)

        let seat = UUID()
        stage.show(seat)
        stage.focus(seat)
        stage.togglePinFocused()
        XCTAssertTrue(stage.isPinned(seat))
        stage.togglePinFocused()
        XCTAssertFalse(stage.isPinned(seat))
    }
}

/// Which issues a seat shows.
final class WheelhouseSeatIssuesTests: XCTestCase {
    func testIssuesCombineInstallDelegatesAndTheLastLaunch() {
        XCTAssertEqual(
            WheelhouseStore.issues(installed: false, delegates: [], launchFailure: nil), [.notInstalled])
        XCTAssertEqual(WheelhouseStore.issues(installed: nil, delegates: [], launchFailure: nil), [])
        XCTAssertEqual(
            WheelhouseStore.issues(
                installed: true, delegates: [.delegatesNotCommitted(["harnesses/io"])], launchFailure: "boom"),
            [.delegatesNotCommitted(["harnesses/io"]), .launchFailed("boom")])
    }
}
