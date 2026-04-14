import XCTest

@testable import TermQ

/// Tests for TmuxControlModeParser — the actual parsing logic.
///
/// The parser is @MainActor, so all test methods must run on the main actor.
/// These tests exercise parse(_:String) dispatch, callback firing, state
/// mutation, and reset behaviour.
@MainActor
final class TmuxControlModeParserTests: XCTestCase {

    var parser: TmuxControlModeParser!

    override func setUp() async throws {
        parser = TmuxControlModeParser()
    }

    override func tearDown() async throws {
        parser = nil
    }

    // MARK: - Initial state

    func testInitialState_isConnectedFalse() {
        XCTAssertFalse(parser.isConnected)
    }

    func testInitialState_panesEmpty() {
        XCTAssertTrue(parser.panes.isEmpty)
    }

    func testInitialState_windowsEmpty() {
        XCTAssertTrue(parser.windows.isEmpty)
    }

    func testInitialState_currentLayoutEmpty() {
        XCTAssertEqual(parser.currentLayout, "")
    }

    func testInitialState_lastErrorNil() {
        XCTAssertNil(parser.lastError)
    }

    // MARK: - Line buffering

    func testParse_singleCompleteLineWithNewline_dispatched() {
        var receivedId: String?
        parser.onWindowAdd = { id in receivedId = id }

        parser.parse("%window-add @5\n")

        XCTAssertEqual(receivedId, "5")
    }

    func testParse_lineWithoutTrailingNewline_bufferedNotDispatched() {
        var receivedId: String?
        parser.onWindowAdd = { id in receivedId = id }

        parser.parse("%window-add @5")  // no newline — stays in buffer

        XCTAssertNil(receivedId)
    }

    func testParse_splitAcrossTwoCalls_dispatched() {
        var receivedId: String?
        parser.onWindowAdd = { id in receivedId = id }

        parser.parse("%window-add ")   // partial
        XCTAssertNil(receivedId)
        parser.parse("@7\n")           // completes the line

        XCTAssertEqual(receivedId, "7")
    }

    func testParse_multipleLines_allDispatched() {
        var addedIds: [String] = []
        parser.onWindowAdd = { id in addedIds.append(id) }

        parser.parse("%window-add @1\n%window-add @2\n%window-add @3\n")

        XCTAssertEqual(addedIds, ["1", "2", "3"])
    }

    func testParse_emptyString_noCallbacks() {
        var called = false
        parser.onWindowAdd = { _ in called = true }

        parser.parse("")

        XCTAssertFalse(called)
    }

    // MARK: - %window-add

    func testWindowAdd_callsCallback() {
        var receivedId: String?
        parser.onWindowAdd = { id in receivedId = id }

        parser.parse("%window-add @42\n")

        XCTAssertEqual(receivedId, "42")
    }

    func testWindowAdd_addsToWindowsCollection() {
        parser.parse("%window-add @3\n")

        XCTAssertEqual(parser.windows.count, 1)
        XCTAssertEqual(parser.windows.first?.id, "3")
    }

    func testWindowAdd_duplicateId_notAddedTwice() {
        parser.parse("%window-add @3\n")
        parser.parse("%window-add @3\n")

        XCTAssertEqual(parser.windows.count, 1)
    }

    // MARK: - %window-close

    func testWindowClose_callsCallback() {
        var receivedId: String?
        parser.onWindowClose = { id in receivedId = id }

        parser.parse("%window-add @1\n")
        parser.parse("%window-close @1\n")

        XCTAssertEqual(receivedId, "1")
    }

    func testWindowClose_removesFromWindowsCollection() {
        parser.parse("%window-add @1\n")
        XCTAssertEqual(parser.windows.count, 1)

        parser.parse("%window-close @1\n")
        XCTAssertTrue(parser.windows.isEmpty)
    }

    // MARK: - %layout-change

    func testLayoutChange_callsCallbackWithWindowIdAndLayout() {
        var receivedWindowId: String?
        var receivedLayout: String?
        parser.onLayoutChange = { windowId, layout in
            receivedWindowId = windowId
            receivedLayout = layout
        }

        parser.parse("%layout-change @0 177x42,0,0,0\n")

        XCTAssertEqual(receivedWindowId, "0")
        XCTAssertEqual(receivedLayout, "177x42,0,0,0")
    }

    func testLayoutChange_updatesCurrentLayout() {
        let layout = "88x42,0,0{44x42,0,0,0,43x42,45,0,1}"
        parser.parse("%layout-change @0 \(layout)\n")

        XCTAssertEqual(parser.currentLayout, layout)
    }

    // MARK: - %session-changed

    func testSessionChanged_setsIsConnectedTrue() {
        XCTAssertFalse(parser.isConnected)
        parser.parse("%session-changed $1 main\n")
        XCTAssertTrue(parser.isConnected)
    }

    func testSessionChanged_callsCallbackWithSessionIdAndName() {
        var receivedSessionId: String?
        var receivedName: String?
        parser.onSessionChange = { sessionId, name in
            receivedSessionId = sessionId
            receivedName = name
        }

        parser.parse("%session-changed $1 main\n")

        XCTAssertEqual(receivedSessionId, "1")
        XCTAssertEqual(receivedName, "main")
    }

    // MARK: - %exit

    func testExit_setsIsConnectedFalse() {
        parser.parse("%session-changed $1 main\n")
        XCTAssertTrue(parser.isConnected)

        parser.parse("%exit\n")
        XCTAssertFalse(parser.isConnected)
    }

    func testExit_withoutReason_passesNilToCallback() {
        var capturedReason: String? = "sentinel"
        parser.onExit = { reason in capturedReason = reason }

        parser.parse("%exit\n")

        XCTAssertNil(capturedReason)
    }

    func testExit_withReason_passesReasonToCallback() {
        var capturedReason: String?
        parser.onExit = { reason in capturedReason = reason }

        parser.parse("%exit detached\n")

        XCTAssertEqual(capturedReason, "detached")
    }

    // MARK: - %output

    func testOutput_callsOnPaneOutputWithPaneId() {
        var receivedPaneId: String?
        parser.onPaneOutput = { paneId, _ in receivedPaneId = paneId }

        parser.parse("%output %2 Hello%20World\n")

        XCTAssertEqual(receivedPaneId, "2")
    }

    func testOutput_decodesBackslashOctalEscaping() {
        // tmux encodes pane output using backslash + 3-digit octal, not percent encoding.
        // Space = \040 (octal 32), newline = \012
        var receivedData: Data?
        parser.onPaneOutput = { _, data in receivedData = data }

        parser.parse("%output %0 Hello\\040World\n")

        XCTAssertNotNil(receivedData)
        let text = String(data: receivedData!, encoding: .utf8) ?? ""
        XCTAssertEqual(text, "Hello World")
    }

    func testOutput_emptyData_callsCallbackWithEmptyData() {
        var callbackFired = false
        parser.onPaneOutput = { _, _ in callbackFired = true }

        parser.parse("%output %0 \n")

        XCTAssertTrue(callbackFired)
    }

    // MARK: - %pane-mode-changed

    func testPaneModeChanged_callsCallbackWithPaneId() {
        var receivedPaneId: String?
        parser.onPaneModeChanged = { paneId in receivedPaneId = paneId }

        parser.parse("%pane-mode-changed %3\n")

        XCTAssertEqual(receivedPaneId, "3")
    }

    // MARK: - %begin / %end command tracking

    func testBeginEnd_commandOutputAccumulated() async {
        parser.parse("%begin 1000 42 0\n")
        parser.parse("list-panes output line\n")
        parser.parse("%end 1000 42 0\n")

        let response = await parser.awaitResponse(for: 42, timeout: 0.1)
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.isComplete)
        XCTAssertTrue(response!.output.contains("list-panes output line"))
    }

    func testBeginEnd_responseStoredForCorrectCommandId() async {
        parser.parse("%begin 1000 7 0\n")
        parser.parse("output for command 7\n")
        parser.parse("%end 1000 7 0\n")

        let response = await parser.awaitResponse(for: 7, timeout: 0.1)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.id, 7)
    }

    func testBeginEnd_unknownCommandId_notStored() async {
        parser.parse("%begin 1000 99 0\n")
        parser.parse("%end 1000 99 0\n")

        // Awaiting a different ID should time out
        let response = await parser.awaitResponse(for: 55, timeout: 0.05)
        XCTAssertNil(response)
    }

    func testOutput_interleaved_withinCommandBlock_passedThrough() {
        var receivedPaneId: String?
        parser.onPaneOutput = { paneId, _ in receivedPaneId = paneId }

        // %output within a %begin/%end block must still fire the callback immediately
        parser.parse("%begin 1000 1 0\n")
        parser.parse("%output %0 hello\n")
        parser.parse("%end 1000 1 0\n")

        XCTAssertEqual(receivedPaneId, "0")
    }

    // MARK: - reset()

    func testReset_clearsAllState() {
        parser.parse("%window-add @1\n")
        parser.parse("%session-changed $1 main\n")
        parser.parse("%layout-change @1 80x24,0,0,0\n")

        parser.reset()

        XCTAssertFalse(parser.isConnected)
        XCTAssertTrue(parser.panes.isEmpty)
        XCTAssertTrue(parser.windows.isEmpty)
        XCTAssertEqual(parser.currentLayout, "")
        XCTAssertNil(parser.lastError)
    }

    func testReset_clearsLineBuffer_nextLineNotMisinterpreted() {
        // Feed a partial line before reset
        parser.parse("%window-add @")  // incomplete — stays in buffer
        parser.reset()

        // After reset, new line should be clean
        var receivedId: String?
        parser.onWindowAdd = { id in receivedId = id }
        parser.parse("%window-add @9\n")

        XCTAssertEqual(receivedId, "9")
    }

    // MARK: - Unknown control lines

    func testUnknownControlLine_noCallbacksFired_noError() {
        var anyCallbackFired = false
        parser.onWindowAdd = { _ in anyCallbackFired = true }
        parser.onWindowClose = { _ in anyCallbackFired = true }
        parser.onLayoutChange = { _, _ in anyCallbackFired = true }
        parser.onSessionChange = { _, _ in anyCallbackFired = true }
        parser.onExit = { _ in anyCallbackFired = true }
        parser.onPaneModeChanged = { _ in anyCallbackFired = true }
        parser.onPaneOutput = { _, _ in anyCallbackFired = true }

        parser.parse("%unknown-command argument\n")

        XCTAssertFalse(anyCallbackFired)
    }

    func testNonControlLine_ignored() {
        // Lines not starting with % are ignored when outside a command block
        var anyCallbackFired = false
        parser.onWindowAdd = { _ in anyCallbackFired = true }

        parser.parse("regular output line\n")

        XCTAssertFalse(anyCallbackFired)
    }
}
