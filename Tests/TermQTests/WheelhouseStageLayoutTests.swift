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

    func testShowCardAlreadyOnStageOnlyFocuses() {
        var stage = WheelhouseStageLayout(pinned: [a], visitor: b, focused: b)
        stage.show(a)
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

    func testUnpinKeepsCardInPlace() {
        var stage = WheelhouseStageLayout(pinned: [a, b], visitor: c)
        stage.unpin(a)
        XCTAssertEqual(stage.visible, [a, b, c])
        XCTAssertFalse(stage.isPinned(a))
    }

    func testShowReplacesLastUnpinnedInPlace() {
        var stage = WheelhouseStageLayout(pinned: [a, b], visitor: c)
        stage.unpin(a)
        stage.show(d)
        // c is the last unpinned card: d takes its place, a stays put.
        XCTAssertEqual(stage.visible, [a, b, d])
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
        XCTAssertEqual(stage.visible, [c, a, b])
        stage.move(d, before: a)
        // Full: the last unpinned card other than d (b) leaves.
        XCTAssertEqual(stage.visible, [c, d, a])
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
}
