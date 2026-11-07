import Foundation
import XCTest

@testable import TermQCore

final class WheelhouseCardMatcherTests: XCTestCase {

    private func card(_ tags: [(String, String)], deleted: Bool = false) -> TerminalCard {
        let card = TerminalCard(
            title: "seat",
            tags: tags.map { Tag(key: $0.0, value: $0.1) },
            columnId: UUID(),
            workingDirectory: "/w/ynw"
        )
        if deleted { card.deletedAt = Date() }
        return card
    }

    func testTagsNameTheWheelhouseAndSeat() {
        let tags = WheelhouseCardMatcher.tags(wheelhouseRoot: "/w/ynw", seatCommand: "may")
        XCTAssertEqual(tags.map(\.key), ["wheelhouse", "seat"])
        XCTAssertEqual(tags.map(\.value), ["/w/ynw", "may"])
    }

    func testMatchesNeedsBothTags() {
        let both = card([("wheelhouse", "/w/ynw"), ("seat", "may"), ("harness", "local/may")])
        XCTAssertTrue(WheelhouseCardMatcher.matches(both, wheelhouseRoot: "/w/ynw", seatCommand: "may"))

        let seatOnly = card([("seat", "may")])
        XCTAssertFalse(WheelhouseCardMatcher.matches(seatOnly, wheelhouseRoot: "/w/ynw", seatCommand: "may"))

        let wheelhouseOnly = card([("wheelhouse", "/w/ynw")])
        XCTAssertFalse(WheelhouseCardMatcher.matches(wheelhouseOnly, wheelhouseRoot: "/w/ynw", seatCommand: "may"))
    }

    func testSameSeatNameInAnotherWheelhouseDoesNotMatch() {
        let other = card([("wheelhouse", "/w/other"), ("seat", "may")])
        XCTAssertFalse(WheelhouseCardMatcher.matches(other, wheelhouseRoot: "/w/ynw", seatCommand: "may"))
    }

    func testDeletedCardDoesNotMatch() {
        let binned = card([("wheelhouse", "/w/ynw"), ("seat", "may")], deleted: true)
        XCTAssertFalse(WheelhouseCardMatcher.matches(binned, wheelhouseRoot: "/w/ynw", seatCommand: "may"))
    }

    func testIsSeatCardNeedsBothTags() {
        XCTAssertTrue(WheelhouseCardMatcher.isSeatCard(card([("wheelhouse", "/w/ynw"), ("seat", "may")])))
        XCTAssertFalse(WheelhouseCardMatcher.isSeatCard(card([("seat", "may")])))
        XCTAssertFalse(WheelhouseCardMatcher.isSeatCard(card([("harness", "local/may")])))
    }

    func testCardFindsTheSeatsCard() {
        let eno = card([("wheelhouse", "/w/ynw"), ("seat", "eno")])
        let may = card([("wheelhouse", "/w/ynw"), ("seat", "may")])
        let found = WheelhouseCardMatcher.card(in: [eno, may], wheelhouseRoot: "/w/ynw", seatCommand: "may")
        XCTAssertEqual(found?.id, may.id)
        XCTAssertNil(WheelhouseCardMatcher.card(in: [eno], wheelhouseRoot: "/w/ynw", seatCommand: "may"))
    }
}

final class WheelhouseGeneralTabCardsTests: XCTestCase {
    private func card(_ tags: [(String, String)]) -> TerminalCard {
        TerminalCard(
            title: "c", tags: tags.map { Tag(key: $0.0, value: $0.1) }, columnId: UUID(), workingDirectory: "/w")
    }

    func testSeatCardsLeaveTheGeneralTabsWhileTheFeatureIsOn() {
        let seat = card([("wheelhouse", "/w/ynw"), ("seat", "may")])
        let plain = card([("harness", "local/x")])
        XCTAssertEqual(
            WheelhouseCardMatcher.generalTabCards([seat, plain], wheelhouseEnabled: true).map(\.id), [plain.id])
    }

    func testSeatCardsStayWhenTheFeatureIsOff() {
        let seat = card([("wheelhouse", "/w/ynw"), ("seat", "may")])
        let plain = card([])
        XCTAssertEqual(
            WheelhouseCardMatcher.generalTabCards([seat, plain], wheelhouseEnabled: false).map(\.id),
            [seat.id, plain.id])
    }
}
