import XCTest

@testable import TermQ

/// Tests for the pure ControlModeLineParser — no MainActor, no callbacks.
final class ControlModeLineParserTests: XCTestCase {

    private let parser = ControlModeLineParser()

    // MARK: - %begin

    func testBegin_parsesCommandId() {
        guard case .begin(let id) = parser.parse("%begin 1748814148 5 0") else {
            return XCTFail("Expected .begin")
        }
        XCTAssertEqual(id, 5)
    }

    func testBegin_commandIdIsThirdField() {
        // %begin <timestamp> <commandId> <flags>
        guard case .begin(let id) = parser.parse("%begin 1234567890 42 0") else {
            return XCTFail("Expected .begin")
        }
        XCTAssertEqual(id, 42)
    }

    func testBegin_missingFields_returnsUnknown() {
        guard case .unknown = parser.parse("%begin 1234") else {
            return XCTFail("Expected .unknown for malformed begin")
        }
    }

    // MARK: - %end

    func testEnd_parsesCommandId() {
        guard case .end(let id) = parser.parse("%end 1748814148 5 0") else {
            return XCTFail("Expected .end")
        }
        XCTAssertEqual(id, 5)
    }

    // MARK: - %output

    func testOutput_parsesPane() {
        guard case .output(let paneId, _) = parser.parse("%output %0 Hello\\040World") else {
            return XCTFail("Expected .output")
        }
        XCTAssertEqual(paneId, "0")
    }

    func testOutput_stripsPercentSigil() {
        guard case .output(let paneId, _) = parser.parse("%output %3 data") else {
            return XCTFail("Expected .output")
        }
        XCTAssertEqual(paneId, "3")
    }

    func testOutput_preservesEscapedData() {
        guard case .output(_, let data) = parser.parse("%output %0 Hello\\040World") else {
            return XCTFail("Expected .output")
        }
        XCTAssertEqual(data, "Hello\\040World")
    }

    func testOutput_emptyData() {
        guard case .output(let paneId, let data) = parser.parse("%output %0 ") else {
            return XCTFail("Expected .output")
        }
        XCTAssertEqual(paneId, "0")
        XCTAssertEqual(data, "")
    }

    // MARK: - %extended-output

    func testExtendedOutput_parsesData() {
        guard
            case .extendedOutput(let paneId, let data) =
                parser.parse("%extended-output %0 100 : Hello\\040World")
        else {
            return XCTFail("Expected .extendedOutput")
        }
        XCTAssertEqual(paneId, "0")
        XCTAssertEqual(data, "Hello\\040World")
    }

    func testExtendedOutput_missingSeparator_returnsUnknown() {
        guard case .unknown = parser.parse("%extended-output %0 100 NoSeparatorHere") else {
            return XCTFail("Expected .unknown for missing separator")
        }
    }

    // MARK: - %pause / %continue

    func testPause_parsesPaneId() {
        guard case .pause(let paneId) = parser.parse("%pause %2") else {
            return XCTFail("Expected .pause")
        }
        XCTAssertEqual(paneId, "2")
    }

    func testContinue_parsesPaneId() {
        guard case .continue(let paneId) = parser.parse("%continue %1") else {
            return XCTFail("Expected .continue")
        }
        XCTAssertEqual(paneId, "1")
    }

    // MARK: - %layout-change

    func testLayoutChange_parsesWindowIdAndLayout() {
        guard
            case .layoutChange(let windowId, let layout) =
                parser.parse("%layout-change @0 177x42,0,0,0")
        else {
            return XCTFail("Expected .layoutChange")
        }
        XCTAssertEqual(windowId, "0")
        XCTAssertEqual(layout, "177x42,0,0,0")
    }

    func testLayoutChange_complexLayout() {
        let layout = "88x42,0,0{44x42,0,0,0,43x42,45,0,1}"
        guard
            case .layoutChange(_, let parsed) =
                parser.parse("%layout-change @0 \(layout)")
        else {
            return XCTFail("Expected .layoutChange")
        }
        XCTAssertEqual(parsed, layout)
    }

    // MARK: - %window-add / %window-close

    func testWindowAdd_parsesWindowId() {
        guard case .windowAdd(let windowId) = parser.parse("%window-add @42") else {
            return XCTFail("Expected .windowAdd")
        }
        XCTAssertEqual(windowId, "42")
    }

    func testWindowClose_parsesWindowId() {
        guard case .windowClose(let windowId) = parser.parse("%window-close @3") else {
            return XCTFail("Expected .windowClose")
        }
        XCTAssertEqual(windowId, "3")
    }

    // MARK: - %session-changed

    func testSessionChanged_parsesSessionIdAndName() {
        guard
            case .sessionChanged(let sessionId, let name) =
                parser.parse("%session-changed $1 main")
        else {
            return XCTFail("Expected .sessionChanged")
        }
        XCTAssertEqual(sessionId, "1")
        XCTAssertEqual(name, "main")
    }

    // MARK: - %pane-mode-changed

    func testPaneModeChanged_parsesPaneId() {
        guard case .paneModeChanged(let paneId) = parser.parse("%pane-mode-changed %3") else {
            return XCTFail("Expected .paneModeChanged")
        }
        XCTAssertEqual(paneId, "3")
    }

    // MARK: - %exit

    func testExit_noReason_nilReason() {
        guard case .exit(let reason) = parser.parse("%exit") else {
            return XCTFail("Expected .exit")
        }
        XCTAssertNil(reason)
    }

    func testExit_withReason() {
        guard case .exit(let reason) = parser.parse("%exit detached") else {
            return XCTFail("Expected .exit")
        }
        XCTAssertEqual(reason, "detached")
    }

    // MARK: - Unknown / edge cases

    func testUnknownCommand_returnsUnknown() {
        guard case .unknown = parser.parse("%unknown-command args") else {
            return XCTFail("Expected .unknown")
        }
    }

    func testNonPercentLine_returnsUnknown() {
        guard case .unknown = parser.parse("regular output") else {
            return XCTFail("Expected .unknown for non-% line")
        }
    }

    func testEmptyLine_returnsUnknown() {
        guard case .unknown = parser.parse("") else {
            return XCTFail("Expected .unknown for empty line")
        }
    }

    func testJustPercent_returnsUnknown() {
        guard case .unknown = parser.parse("%") else {
            return XCTFail("Expected .unknown for bare %")
        }
    }
}
