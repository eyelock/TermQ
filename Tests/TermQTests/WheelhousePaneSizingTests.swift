import Foundation
import XCTest

@testable import TermQCore

final class WheelhousePaneSizingTests: XCTestCase {
    func testWidthsShareByWeight() {
        XCTAssertEqual(WheelhousePaneSizing.widths(weights: [1, 1], available: 1000), [500, 500])
        XCTAssertEqual(WheelhousePaneSizing.widths(weights: [3, 1], available: 1000), [750, 250])
        XCTAssertEqual(WheelhousePaneSizing.widths(weights: [1], available: 800), [800])
    }

    func testWidthsWithZeroWeightsSplitEvenly() {
        XCTAssertEqual(WheelhousePaneSizing.widths(weights: [0, 0], available: 600), [300, 300])
        XCTAssertEqual(WheelhousePaneSizing.widths(weights: [], available: 600), [])
    }

    func testDragMovesWeightBetweenThePair() {
        // Two panes of 500 points: dragging 100 right makes them 600 and 400.
        let resized = WheelhousePaneSizing.resized(
            left: 1, right: 1, weightPerPoint: 2.0 / 1000, delta: 100, minWidth: 240)
        let widths = WheelhousePaneSizing.widths(weights: [resized.left, resized.right], available: 1000)
        XCTAssertEqual(widths[0], 600, accuracy: 0.001)
        XCTAssertEqual(widths[1], 400, accuracy: 0.001)
    }

    func testDragStopsAtMinimumWidth() {
        let resized = WheelhousePaneSizing.resized(
            left: 1, right: 1, weightPerPoint: 2.0 / 1000, delta: 900, minWidth: 240)
        let widths = WheelhousePaneSizing.widths(weights: [resized.left, resized.right], available: 1000)
        XCTAssertEqual(widths[1], 240, accuracy: 0.001)
        XCTAssertEqual(widths[0], 760, accuracy: 0.001)
    }

    func testDragLeavesOtherPanesAlone() {
        // Three panes; dragging the first divider keeps the third at a third.
        let resized = WheelhousePaneSizing.resized(
            left: 1, right: 1, weightPerPoint: 3.0 / 900, delta: -50, minWidth: 100)
        let widths = WheelhousePaneSizing.widths(weights: [resized.left, resized.right, 1], available: 900)
        XCTAssertEqual(widths[0], 250, accuracy: 0.001)
        XCTAssertEqual(widths[1], 350, accuracy: 0.001)
        XCTAssertEqual(widths[2], 300, accuracy: 0.001)
    }
}
