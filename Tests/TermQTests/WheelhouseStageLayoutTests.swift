import Foundation
import XCTest

@testable import TermQCore

final class WheelhouseStageLayoutTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()

    func testShowPutsCardInVisitingSlotAndFocusesIt() {
        var stage = WheelhouseStageLayout(pinned: [a])
        stage.show(b)
        XCTAssertEqual(stage.visible, [a, b])
        XCTAssertEqual(stage.focused, b)
    }

    func testShowReplacesVisitorNotPinned() {
        var stage = WheelhouseStageLayout(pinned: [a, b])
        stage.show(c)
        stage.show(d)
        XCTAssertEqual(stage.visible, [a, b, d])
        XCTAssertEqual(stage.visitor, d)
    }

    func testShowWithNothingPinnedKeepsOneCard() {
        var stage = WheelhouseStageLayout()
        stage.show(a)
        stage.show(b)
        XCTAssertEqual(stage.visible, [b])
        XCTAssertEqual(stage.focused, b)
    }

    func testShowPinnedCardSendsVisitorAway() {
        var stage = WheelhouseStageLayout(pinned: [a], visitor: b, focused: b)
        stage.show(a)
        XCTAssertEqual(stage.visible, [a])
        XCTAssertEqual(stage.focused, a)
    }

    func testShowVisitorAgainOnlyFocuses() {
        var stage = WheelhouseStageLayout(pinned: [a], visitor: b, focused: a)
        stage.show(b)
        XCTAssertEqual(stage.visible, [a, b])
        XCTAssertEqual(stage.focused, b)
    }

    func testFocusPinnedPaneKeepsVisitor() {
        var stage = WheelhouseStageLayout(pinned: [a], visitor: b, focused: b)
        stage.focus(a)
        XCTAssertEqual(stage.visible, [a, b])
        XCTAssertEqual(stage.focused, a)
    }

    func testShowWhenAllSlotsPinnedDropsLastPinned() {
        var stage = WheelhouseStageLayout(pinned: [a, b, c])
        stage.show(d)
        XCTAssertEqual(stage.pinned, [a, b])
        XCTAssertEqual(stage.visible, [a, b, d])
    }

    func testPinVisitorMovesItToPinned() {
        var stage = WheelhouseStageLayout(pinned: [a], visitor: b)
        stage.pin(b)
        XCTAssertEqual(stage.pinned, [a, b])
        XCTAssertNil(stage.visitor)
        XCTAssertEqual(stage.visible, [a, b])
    }

    func testPinFillingAllSlotsClearsVisitor() {
        var stage = WheelhouseStageLayout(pinned: [a, b], visitor: c)
        stage.pin(d)
        XCTAssertEqual(stage.visible, [a, b, d])
        XCTAssertNil(stage.visitor)
    }

    func testUnpinKeepsCardAsVisitorWhenSlotFree() {
        var stage = WheelhouseStageLayout(pinned: [a, b])
        stage.unpin(b)
        XCTAssertEqual(stage.pinned, [a])
        XCTAssertEqual(stage.visible, [a, b])
    }

    func testUnpinKeepsCardInPlaceAndSendsOldVisitorAway() {
        var stage = WheelhouseStageLayout(pinned: [a, b], visitor: c, focused: c)
        stage.unpin(a)
        XCTAssertEqual(stage.visible, [a, b])
        XCTAssertEqual(stage.visitor, a)
        XCTAssertEqual(stage.focused, a)
    }

    func testShowReplacesVisitorInPlace() {
        var stage = WheelhouseStageLayout(pinned: [a, b], visitor: c)
        stage.unpin(a)
        stage.show(d)
        // a is now the unpinned card: d takes its place, b stays put.
        XCTAssertEqual(stage.visible, [d, b])
    }

    func testMoveReordersPanes() {
        var stage = WheelhouseStageLayout(pinned: [a, b], visitor: c)
        stage.move(c, before: a)
        XCTAssertEqual(stage.visible, [c, a, b])
        XCTAssertEqual(stage.focused, c)
        XCTAssertEqual(stage.pinned, [a, b])
        stage.move(a, before: b)
        XCTAssertEqual(stage.visible, [c, a, b])
    }

    func testMoveCardOntoStageFromOutside() {
        var stage = WheelhouseStageLayout(pinned: [a], visitor: b)
        stage.move(c, before: a)
        // c becomes the unpinned card, so b leaves.
        XCTAssertEqual(stage.visible, [c, a])
        stage.move(d, before: c)
        XCTAssertEqual(stage.visible, [d, a])
        XCTAssertEqual(stage.focused, d)
    }

    func testMovePinnedCardBeforeVisitor() {
        var stage = WheelhouseStageLayout(pinned: [a, b], visitor: c)
        stage.move(a, before: c)
        XCTAssertEqual(stage.visible, [b, a, c])
    }

    func testMoveOntoItselfOrOffStageTargetDoesNothing() {
        var stage = WheelhouseStageLayout(pinned: [a], visitor: b)
        stage.move(a, before: a)
        stage.move(a, before: d)
        XCTAssertEqual(stage.visible, [a, b])
    }

    func testRemoveRefocusesFirstCard() {
        var stage = WheelhouseStageLayout(pinned: [a], visitor: b, focused: b)
        stage.remove(b)
        XCTAssertEqual(stage.visible, [a])
        XCTAssertEqual(stage.focused, a)
    }

    func testPruneDropsMissingCards() {
        var stage = WheelhouseStageLayout(pinned: [a, b], visitor: c, focused: c)
        stage.prune(keeping: [a])
        XCTAssertEqual(stage.visible, [a])
        XCTAssertEqual(stage.focused, a)
    }

    func testInitClampsAndDropsVisitorAlreadyPinned() {
        let stage = WheelhouseStageLayout(pinned: [a, b, c, d], visitor: a)
        XCTAssertEqual(stage.pinned, [a, b, c])
        XCTAssertNil(stage.visitor)
    }

    func testFocusIgnoresCardsOffStage() {
        var stage = WheelhouseStageLayout(pinned: [a], focused: a)
        stage.focus(d)
        XCTAssertEqual(stage.focused, a)
    }

    // MARK: - Attention queue

    func testAttentionQueueIsOldestFirstAndSkipsExcluded() {
        let now = Date()
        let since: [UUID: Date] = [
            a: now.addingTimeInterval(-10), b: now.addingTimeInterval(-60), c: now, d: now.addingTimeInterval(-30),
        ]
        let queue = WheelhouseAttention.queue(candidates: [a, b, c, d], since: since, excluding: [d])
        XCTAssertEqual(queue, [b, a, c])
    }

    func testAttentionQueueIgnoresCardsThatNeverRang() {
        let queue = WheelhouseAttention.queue(candidates: [a, b], since: [b: Date()])
        XCTAssertEqual(queue, [b])
    }

    func testAttentionQueueTiesKeepCandidateOrder() {
        let time = Date()
        XCTAssertEqual(WheelhouseAttention.queue(candidates: [c, a], since: [a: time, c: time]), [c, a])
    }

    // MARK: - Anchor (the inbox)

    func testAnchorIsPinnedAndRightmostWhenShown() {
        let inbox = UUID()
        let a = UUID()
        var layout = WheelhouseStageLayout(anchor: inbox)
        layout.show(a)
        layout.show(inbox)
        XCTAssertEqual(layout.cards, [a, inbox])
        XCTAssertTrue(layout.isPinned(inbox))
        XCTAssertFalse(layout.isPinned(a))
    }

    func testAnchorStaysRightWhenOthersArePinnedOrShown() {
        let inbox = UUID()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        var layout = WheelhouseStageLayout(anchor: inbox)
        layout.show(inbox)
        layout.show(a)
        XCTAssertEqual(layout.cards, [a, inbox])
        layout.pin(a)
        layout.show(b)
        XCTAssertEqual(layout.cards, [a, b, inbox])
        layout.show(c)
        XCTAssertEqual(layout.cards, [a, c, inbox])
    }

    func testAnchorNeverGivesWayWhenFull() {
        let inbox = UUID()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        var layout = WheelhouseStageLayout(anchor: inbox)
        layout.show(inbox)
        layout.pin(a)
        layout.pin(b)
        layout.show(c)
        XCTAssertEqual(layout.cards, [a, c, inbox])
        XCTAssertTrue(layout.isOnStage(inbox))
    }

    func testAnchorCannotBeUnpinnedOrMovedLeft() {
        let inbox = UUID()
        let a = UUID()
        let b = UUID()
        var layout = WheelhouseStageLayout(anchor: inbox)
        layout.pin(a)
        layout.show(inbox)
        layout.unpin(inbox)
        XCTAssertTrue(layout.isPinned(inbox))
        layout.move(inbox, before: a)
        XCTAssertEqual(layout.cards, [a, inbox])
        layout.pin(b)
        layout.move(b, before: inbox)
        XCTAssertEqual(layout.cards.last, inbox)
    }

    func testShowingAnchorOnFullStageDropsAnUnpinnedCard() {
        let inbox = UUID()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        var layout = WheelhouseStageLayout(anchor: inbox)
        layout.pin(a)
        layout.pin(b)
        layout.show(c)
        layout.show(inbox)
        XCTAssertEqual(layout.cards, [a, b, inbox])
    }
}
