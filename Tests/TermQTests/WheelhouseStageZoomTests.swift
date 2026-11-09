import Foundation
import XCTest

@testable import TermQ

/// Zooming a stage pane to fill the window, and coming back.
@MainActor
final class WheelhouseStageZoomTests: XCTestCase {
    private func makeStage() throws -> WheelhouseStage {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WheelhouseStageZoomTests-\(UUID().uuidString)"))
        return WheelhouseStage(defaults: defaults)
    }

    func testToggleZoomsTheFocusedPaneAndBack() throws {
        let stage = try makeStage()
        let card = UUID()
        stage.show(card)
        stage.toggleZoom()
        XCTAssertEqual(stage.zoomed, card)
        stage.toggleZoom()
        XCTAssertNil(stage.zoomed)
    }

    func testTheInboxIsNotZoomed() throws {
        let stage = try makeStage()
        stage.show(WheelhouseStage.inboxEntry)
        stage.toggleZoom()
        XCTAssertNil(stage.zoomed)
        stage.zoom(WheelhouseStage.inboxEntry)
        XCTAssertNil(stage.zoomed)
    }

    func testZoomingAPaneFocusesIt() throws {
        let stage = try makeStage()
        let card = UUID()
        stage.zoom(card)
        XCTAssertEqual(stage.focused, card)
        XCTAssertTrue(stage.isOnStage(card))
    }

    func testShowingAnotherPaneComesBackToTheStage() throws {
        let stage = try makeStage()
        let card = UUID()
        stage.zoom(card)
        stage.show(card)
        XCTAssertEqual(stage.zoomed, card, "showing the zoomed pane keeps the zoom")
        stage.show(UUID())
        XCTAssertNil(stage.zoomed)
    }

    func testTakingTheZoomedPaneOffComesBack() throws {
        let stage = try makeStage()
        let card = UUID()
        stage.zoom(card)
        stage.remove(card)
        XCTAssertNil(stage.zoomed)
    }

    func testPruningTheZoomedPaneComesBack() throws {
        let stage = try makeStage()
        let card = UUID()
        stage.zoom(card)
        stage.prune(keeping: [])
        XCTAssertNil(stage.zoomed)
    }

    func testFocusingAnotherPaneComesBackButRefocusingKeepsIt() throws {
        let stage = try makeStage()
        let card = UUID()
        stage.zoom(card)
        stage.focus(card)
        XCTAssertEqual(stage.zoomed, card)
        stage.focus(UUID())
        XCTAssertNil(stage.zoomed)
    }

    func testNothingFocusedMeansNothingToZoom() throws {
        let stage = try makeStage()
        stage.toggleZoom()
        XCTAssertNil(stage.zoomed)
    }

    func testPinningAndRemovingOthersKeepTheZoom() throws {
        let stage = try makeStage()
        let other = UUID()
        stage.show(other)
        stage.pin(other)
        let card = UUID()
        stage.zoom(card)
        stage.pin(card)
        XCTAssertEqual(stage.zoomed, card)
        stage.unpin(card)
        XCTAssertEqual(stage.zoomed, card)
        stage.remove(other)
        XCTAssertEqual(stage.zoomed, card)
    }

    func testHealingDropsAZoomWhosePaneIsNotVisible() throws {
        let stage = try makeStage()
        let card = UUID()
        stage.zoom(card)
        stage.healZoom(visible: [card])
        XCTAssertEqual(stage.zoomed, card)
        stage.healZoom(visible: [])
        XCTAssertNil(stage.zoomed)
    }
}
