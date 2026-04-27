import Foundation
import XCTest

@testable import MCPServerLib

final class GUIDetectorTests: XCTestCase {

    override func tearDown() {
        GUIDetector.testModeOverride = nil
        super.tearDown()
    }

    // MARK: - isGUIRunning

    func testIsGUIRunning_whenOverrideTrue_returnsTrue() {
        GUIDetector.testModeOverride = true
        XCTAssertTrue(GUIDetector.isGUIRunning())
    }

    func testIsGUIRunning_whenOverrideFalse_returnsFalse() {
        GUIDetector.testModeOverride = false
        XCTAssertFalse(GUIDetector.isGUIRunning())
    }

    func testIsGUIRunning_whenOverrideNil_queriesWorkspace() {
        GUIDetector.testModeOverride = nil
        // Exercise the real NSWorkspace query path — the result depends on whether
        // TermQ.app or TermQDebug.app happens to be running on the host (e.g. the
        // developer's IDE). We only assert the call completes without crashing.
        _ = GUIDetector.isGUIRunning()
    }

    // MARK: - waitForGUI

    func testWaitForGUI_whenOverrideTrue_returnsTrueImmediately() async {
        GUIDetector.testModeOverride = true
        let start = Date()
        let result = await GUIDetector.waitForGUI(timeout: 1.0)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(result)
        XCTAssertLessThan(elapsed, 0.2, "waitForGUI should return quickly when GUI is available")
    }

    func testWaitForGUI_whenOverrideFalse_returnsFalseAfterTimeout() async {
        GUIDetector.testModeOverride = false
        let start = Date()
        let result = await GUIDetector.waitForGUI(timeout: 0.1)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertFalse(result)
        XCTAssertGreaterThanOrEqual(elapsed, 0.1)
    }

    func testWaitForGUI_overrideChanges_detectedMidWait() async {
        GUIDetector.testModeOverride = false

        // Flip the override to true after a short delay; waitForGUI should observe this
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000)  // 60ms
            GUIDetector.testModeOverride = true
        }

        let result = await GUIDetector.waitForGUI(timeout: 1.0)
        XCTAssertTrue(result)
    }
}
