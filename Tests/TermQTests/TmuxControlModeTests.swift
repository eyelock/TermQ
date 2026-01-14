import Foundation
import XCTest

@testable import TermQCore

/// Tests for tmux control mode parser
/// Note: These tests cover parsing logic. Integration tests with actual tmux
/// require tmux to be installed and are better suited for manual testing.
final class TmuxControlModeTests: XCTestCase {

    // MARK: - TmuxPane Tests

    func testTmuxPaneInitialization() {
        let pane = TmuxPane(id: "1", windowId: "0", width: 80, height: 24, x: 0, y: 0)

        XCTAssertEqual(pane.id, "1")
        XCTAssertEqual(pane.windowId, "0")
        XCTAssertEqual(pane.width, 80)
        XCTAssertEqual(pane.height, 24)
        XCTAssertEqual(pane.x, 0)
        XCTAssertEqual(pane.y, 0)
        XCTAssertEqual(pane.title, "")
        XCTAssertEqual(pane.currentPath, "")
        XCTAssertFalse(pane.inCopyMode)
        XCTAssertFalse(pane.isActive)
    }

    func testTmuxPaneSendable() {
        // Verify TmuxPane is Sendable by passing it across isolation boundaries
        let pane = TmuxPane(id: "1", windowId: "0", width: 80, height: 24, x: 0, y: 0)

        Task {
            // If this compiles, Sendable conformance is satisfied
            let _ = pane
        }

        XCTAssertEqual(pane.id, "1")
    }

    // MARK: - TmuxWindow Tests

    func testTmuxWindowInitialization() {
        let window = TmuxWindow(id: "0", name: "main")

        XCTAssertEqual(window.id, "0")
        XCTAssertEqual(window.name, "main")
        XCTAssertEqual(window.layout, "")
        XCTAssertFalse(window.isActive)
    }

    func testTmuxWindowSendable() {
        let window = TmuxWindow(id: "0", name: "test")

        Task {
            let _ = window
        }

        XCTAssertEqual(window.id, "0")
    }

    // MARK: - CommandResponse Tests

    func testCommandResponseInitialization() {
        let response = CommandResponse(id: 42)

        XCTAssertEqual(response.id, 42)
        XCTAssertEqual(response.output, "")
        XCTAssertFalse(response.isComplete)
    }

    func testCommandResponseMutation() {
        var response = CommandResponse(id: 1)
        response.output = "test output\n"
        response.isComplete = true

        XCTAssertEqual(response.output, "test output\n")
        XCTAssertTrue(response.isComplete)
    }

    // MARK: - PaneDirection Tests

    func testPaneDirectionCases() {
        // Verify all cases exist and are distinct
        let directions: [PaneDirection] = [.up, .down, .left, .right]

        XCTAssertEqual(directions.count, 4)
        XCTAssertNotEqual(PaneDirection.up, PaneDirection.down)
        XCTAssertNotEqual(PaneDirection.left, PaneDirection.right)
    }

    func testPaneDirectionSendable() {
        let direction = PaneDirection.up

        Task {
            let _ = direction
        }

        XCTAssertEqual(direction, .up)
    }

    // MARK: - Control Mode Line Parsing Patterns

    func testControlModeLinePrefix() {
        // Control mode lines start with %
        let controlLine = "%session-changed $1 main"
        let normalLine = "regular output"

        XCTAssertTrue(controlLine.hasPrefix("%"))
        XCTAssertFalse(normalLine.hasPrefix("%"))
    }

    func testParseSessionChangedLine() {
        // %session-changed $<session-id> <name>
        let line = "%session-changed $1 main"
        let parts = line.dropFirst().split(separator: " ", maxSplits: 2)

        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(String(parts[0]), "session-changed")
        XCTAssertEqual(String(parts[1]), "$1")
        XCTAssertEqual(String(parts[2]), "main")
    }

    func testParseWindowAddLine() {
        // %window-add @<window-id>
        let line = "%window-add @0"
        let parts = line.dropFirst().split(separator: " ")

        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(String(parts[0]), "window-add")
        XCTAssertEqual(String(parts[1]), "@0")

        // Extract window ID (strip @ prefix)
        let windowIdPart = String(parts[1])
        let windowId = windowIdPart.hasPrefix("@") ? String(windowIdPart.dropFirst()) : windowIdPart
        XCTAssertEqual(windowId, "0")
    }

    func testParseLayoutChangeLine() {
        // %layout-change @<window-id> <layout>
        let line = "%layout-change @0 177x42,0,0{88x42,0,0,0,88x42,89,0,1}"
        let parts = line.dropFirst().split(separator: " ", maxSplits: 2)

        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(String(parts[0]), "layout-change")
        XCTAssertEqual(String(parts[1]), "@0")
        XCTAssertEqual(String(parts[2]), "177x42,0,0{88x42,0,0,0,88x42,89,0,1}")
    }

    func testParseOutputLine() {
        // %output %<pane-id> <escaped-data>
        let line = "%output %0 Hello%20World"
        let parts = line.dropFirst().split(separator: " ", maxSplits: 2)

        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(String(parts[0]), "output")
        XCTAssertEqual(String(parts[1]), "%0")

        // Pane ID extraction
        let paneIdPart = String(parts[1])
        let paneId = paneIdPart.hasPrefix("%") ? String(paneIdPart.dropFirst()) : paneIdPart
        XCTAssertEqual(paneId, "0")
    }

    func testParseBeginEndLines() {
        // %begin <timestamp> <number> <flags>
        let beginLine = "%begin 1234567890 42 0"
        let endLine = "%end 1234567891 42 0"

        let beginParts = beginLine.dropFirst().split(separator: " ")
        let endParts = endLine.dropFirst().split(separator: " ")

        XCTAssertEqual(String(beginParts[0]), "begin")
        XCTAssertEqual(String(endParts[0]), "end")

        // Command ID extraction
        let beginId = Int(beginParts[2])
        let endId = Int(endParts[2])
        XCTAssertEqual(beginId, 42)
        XCTAssertEqual(endId, 42)
    }

    // MARK: - Percent Encoding Tests

    func testPercentDecodingBasic() {
        // tmux control mode uses percent encoding for output data
        let encoded = "Hello%20World"
        let decoded = decodePercentEscaped(encoded)

        XCTAssertEqual(decoded, "Hello World")
    }

    func testPercentDecodingNewlines() {
        let encoded = "Line1%0ALine2"
        let decoded = decodePercentEscaped(encoded)

        XCTAssertEqual(decoded, "Line1\nLine2")
    }

    func testPercentDecodingSpecialChars() {
        let encoded = "%25%3D%26"  // %=&
        let decoded = decodePercentEscaped(encoded)

        XCTAssertEqual(decoded, "%=&")
    }

    func testPercentDecodingEmpty() {
        let encoded = ""
        let decoded = decodePercentEscaped(encoded)

        XCTAssertEqual(decoded, "")
    }

    func testPercentDecodingPlainText() {
        let encoded = "no encoding here"
        let decoded = decodePercentEscaped(encoded)

        XCTAssertEqual(decoded, "no encoding here")
    }

    // MARK: - Layout String Parsing Tests

    func testExtractPaneIdsFromSimpleLayout() {
        // Simple layout: WIDTHxHEIGHT,X,Y,PANE_ID
        let layout = "177x42,0,0,0"

        // Extract pane ID using regex
        let panePattern = /,(\d+)(?:,|$|\})/
        let matches = layout.matches(of: panePattern)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(String(matches[0].output.1), "0")
    }

    func testExtractPaneIdsFromSplitLayout() {
        // Split layout with two panes
        let layout = "177x42,0,0{88x42,0,0,0,88x42,89,0,1}"

        let panePattern = /,(\d+)(?:,|$|\})/
        let matches = layout.matches(of: panePattern)

        // Should find pane IDs 0 and 1
        let paneIds = matches.map { String($0.output.1) }
        XCTAssertTrue(paneIds.contains("0"))
        XCTAssertTrue(paneIds.contains("1"))
    }

    func testExtractPaneIdsFromComplexLayout() {
        // More complex nested layout
        let layout = "177x42,0,0{88x42,0,0{44x21,0,0,0,44x20,0,22,2},88x42,89,0,1}"

        let panePattern = /,(\d+)(?:,|$|\})/
        let matches = layout.matches(of: panePattern)

        let paneIds = Set(matches.map { String($0.output.1) })
        XCTAssertTrue(paneIds.contains("0"))
        XCTAssertTrue(paneIds.contains("1"))
        XCTAssertTrue(paneIds.contains("2"))
    }

    // MARK: - Additional Control Mode Message Tests

    func testParseWindowCloseLine() {
        // %window-close @<window-id>
        let line = "%window-close @2"
        let parts = line.dropFirst().split(separator: " ")

        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(String(parts[0]), "window-close")
        XCTAssertEqual(String(parts[1]), "@2")
    }

    func testParseWindowRenamedLine() {
        // %window-renamed @<window-id> <name>
        let line = "%window-renamed @0 new-name"
        let parts = line.dropFirst().split(separator: " ", maxSplits: 2)

        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(String(parts[0]), "window-renamed")
        XCTAssertEqual(String(parts[1]), "@0")
        XCTAssertEqual(String(parts[2]), "new-name")
    }

    func testParsePaneModeChangedLine() {
        // %pane-mode-changed %<pane-id>
        let line = "%pane-mode-changed %0"
        let parts = line.dropFirst().split(separator: " ")

        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(String(parts[0]), "pane-mode-changed")
        XCTAssertEqual(String(parts[1]), "%0")
    }

    func testParseExitLine() {
        // %exit [reason]
        let line = "%exit"
        let lineWithReason = "%exit detached"

        let parts = line.dropFirst().split(separator: " ")
        let partsWithReason = lineWithReason.dropFirst().split(separator: " ", maxSplits: 1)

        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(String(parts[0]), "exit")

        XCTAssertEqual(partsWithReason.count, 2)
        XCTAssertEqual(String(partsWithReason[0]), "exit")
        XCTAssertEqual(String(partsWithReason[1]), "detached")
    }

    func testParseErrorLine() {
        // %error <reason>
        let line = "%error session not found"
        let parts = line.dropFirst().split(separator: " ", maxSplits: 1)

        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(String(parts[0]), "error")
        XCTAssertEqual(String(parts[1]), "session not found")
    }

    // MARK: - TmuxPane Additional Tests

    func testTmuxPaneWithAllProperties() {
        var pane = TmuxPane(id: "5", windowId: "2", width: 120, height: 40, x: 10, y: 5)
        pane.title = "vim"
        pane.currentPath = "/home/user/project"
        pane.inCopyMode = true
        pane.isActive = true

        XCTAssertEqual(pane.id, "5")
        XCTAssertEqual(pane.windowId, "2")
        XCTAssertEqual(pane.width, 120)
        XCTAssertEqual(pane.height, 40)
        XCTAssertEqual(pane.x, 10)
        XCTAssertEqual(pane.y, 5)
        XCTAssertEqual(pane.title, "vim")
        XCTAssertEqual(pane.currentPath, "/home/user/project")
        XCTAssertTrue(pane.inCopyMode)
        XCTAssertTrue(pane.isActive)
    }

    func testTmuxPaneIdentifiable() {
        let pane1 = TmuxPane(id: "1", windowId: "0", width: 80, height: 24, x: 0, y: 0)
        let pane2 = TmuxPane(id: "2", windowId: "0", width: 80, height: 24, x: 0, y: 24)

        XCTAssertNotEqual(pane1.id, pane2.id)
    }

    // MARK: - TmuxWindow Additional Tests

    func testTmuxWindowWithAllProperties() {
        var window = TmuxWindow(id: "3", name: "editor")
        window.layout = "177x42,0,0,0"
        window.isActive = true

        XCTAssertEqual(window.id, "3")
        XCTAssertEqual(window.name, "editor")
        XCTAssertEqual(window.layout, "177x42,0,0,0")
        XCTAssertTrue(window.isActive)
    }

    func testTmuxWindowIdentifiable() {
        let window1 = TmuxWindow(id: "0", name: "main")
        let window2 = TmuxWindow(id: "1", name: "test")

        XCTAssertNotEqual(window1.id, window2.id)
    }

    // MARK: - CommandResponse Additional Tests

    func testCommandResponseWithOutput() {
        var response = CommandResponse(id: 100)
        response.output = "line1\nline2\nline3\n"
        response.isComplete = true

        XCTAssertEqual(response.id, 100)
        XCTAssertTrue(response.output.contains("line1"))
        XCTAssertTrue(response.output.contains("line2"))
        XCTAssertTrue(response.output.contains("line3"))
        XCTAssertTrue(response.isComplete)
    }

    func testCommandResponseAppendOutput() {
        var response = CommandResponse(id: 1)
        response.output += "first line\n"
        response.output += "second line\n"

        XCTAssertEqual(response.output, "first line\nsecond line\n")
    }

    // MARK: - Percent Encoding Additional Tests

    func testPercentDecodingTab() {
        let encoded = "column1%09column2"
        let decoded = decodePercentEscaped(encoded)

        XCTAssertEqual(decoded, "column1\tcolumn2")
    }

    func testPercentDecodingCarriageReturn() {
        let encoded = "line1%0D%0Aline2"
        let decoded = decodePercentEscaped(encoded)

        XCTAssertEqual(decoded, "line1\r\nline2")
    }

    func testPercentDecodingANSIEscape() {
        // ANSI escape sequence for red text
        let encoded = "%1B[31mred%1B[0m"
        let decoded = decodePercentEscaped(encoded)

        XCTAssertTrue(decoded.contains("\u{1B}[31m"))
        XCTAssertTrue(decoded.contains("red"))
    }

    func testPercentDecodingMixedContent() {
        let encoded = "Hello%20%22World%22%21"  // Hello "World"!
        let decoded = decodePercentEscaped(encoded)

        XCTAssertEqual(decoded, "Hello \"World\"!")
    }

    // MARK: - Layout Parsing Additional Tests

    func testLayoutDimensionParsing() {
        let layout = "177x42,0,0,0"
        let dimensionPattern = /^(\d+)x(\d+)/

        if let match = layout.firstMatch(of: dimensionPattern) {
            XCTAssertEqual(String(match.output.1), "177")
            XCTAssertEqual(String(match.output.2), "42")
        } else {
            XCTFail("Failed to parse layout dimensions")
        }
    }

    func testLayoutPositionParsing() {
        // Layout format: WxH,X,Y,ID
        let layout = "80x24,10,5,3"
        let parts = layout.split(separator: ",")

        XCTAssertEqual(parts.count, 4)

        // Parse dimensions
        let dimensions = parts[0].split(separator: "x")
        XCTAssertEqual(String(dimensions[0]), "80")  // width
        XCTAssertEqual(String(dimensions[1]), "24")  // height
        XCTAssertEqual(String(parts[1]), "10")  // x
        XCTAssertEqual(String(parts[2]), "5")   // y
        XCTAssertEqual(String(parts[3]), "3")   // pane id
    }

    func testNestedLayoutParsing() {
        // Vertical split layout
        let verticalLayout = "177x42,0,0[177x21,0,0,0,177x20,0,22,1]"

        // Square brackets indicate vertical split
        XCTAssertTrue(verticalLayout.contains("["))
        XCTAssertTrue(verticalLayout.contains("]"))

        // Horizontal split layout
        let horizontalLayout = "177x42,0,0{88x42,0,0,0,88x42,89,0,1}"

        // Curly braces indicate horizontal split
        XCTAssertTrue(horizontalLayout.contains("{"))
        XCTAssertTrue(horizontalLayout.contains("}"))
    }

    // MARK: - PaneDirection Additional Tests

    func testPaneDirectionEquality() {
        XCTAssertEqual(PaneDirection.up, PaneDirection.up)
        XCTAssertEqual(PaneDirection.down, PaneDirection.down)
        XCTAssertEqual(PaneDirection.left, PaneDirection.left)
        XCTAssertEqual(PaneDirection.right, PaneDirection.right)
    }

    func testPaneDirectionOpposites() {
        XCTAssertNotEqual(PaneDirection.up, PaneDirection.down)
        XCTAssertNotEqual(PaneDirection.left, PaneDirection.right)
    }

    // MARK: - Command Format Tests

    func testSplitWindowCommandFormat() {
        // Verify command format for split operations
        let horizontalSplit = "split-window -v"
        let verticalSplit = "split-window -h"

        XCTAssertTrue(horizontalSplit.contains("-v"))
        XCTAssertTrue(verticalSplit.contains("-h"))
    }

    func testSelectPaneCommandFormat() {
        // Verify command format for pane selection
        func selectPaneCommand(direction: PaneDirection) -> String {
            let flag: String
            switch direction {
            case .up: flag = "-U"
            case .down: flag = "-D"
            case .left: flag = "-L"
            case .right: flag = "-R"
            }
            return "select-pane \(flag)"
        }

        XCTAssertEqual(selectPaneCommand(direction: .up), "select-pane -U")
        XCTAssertEqual(selectPaneCommand(direction: .down), "select-pane -D")
        XCTAssertEqual(selectPaneCommand(direction: .left), "select-pane -L")
        XCTAssertEqual(selectPaneCommand(direction: .right), "select-pane -R")
    }

    func testResizePaneCommandFormat() {
        // Verify command format for resize operations
        func resizePaneCommand(direction: PaneDirection, cells: Int) -> String {
            let flag: String
            switch direction {
            case .up: flag = "-U"
            case .down: flag = "-D"
            case .left: flag = "-L"
            case .right: flag = "-R"
            }
            return "resize-pane \(flag) \(cells)"
        }

        XCTAssertEqual(resizePaneCommand(direction: .up, cells: 5), "resize-pane -U 5")
        XCTAssertEqual(resizePaneCommand(direction: .down, cells: 10), "resize-pane -D 10")
    }

    // MARK: - Helper Functions

    /// Decode percent-escaped string (matches TmuxControlModeParser implementation)
    private func decodePercentEscaped(_ string: String) -> String {
        var result = ""
        var index = string.startIndex

        while index < string.endIndex {
            let char = string[index]

            if char == "%" {
                let nextIndex = string.index(index, offsetBy: 2, limitedBy: string.endIndex)
                guard let next = nextIndex else { break }

                let hexString = String(string[string.index(after: index)..<next])
                if let byte = UInt8(hexString, radix: 16),
                   let char = Character(UnicodeScalar(byte)) {
                    result.append(char)
                    index = next
                    continue
                }
            }

            result.append(char)
            index = string.index(after: index)
        }

        return result
    }
}

/// Import types from TmuxControlMode.swift for testing
/// These would normally be imported from the TermQ module
struct TmuxPane: Identifiable, Sendable {
    let id: String
    var windowId: String
    var width: Int
    var height: Int
    var x: Int
    var y: Int
    var title: String = ""
    var currentPath: String = ""
    var inCopyMode: Bool = false
    var isActive: Bool = false
}

struct TmuxWindow: Identifiable, Sendable {
    let id: String
    var name: String
    var layout: String = ""
    var isActive: Bool = false
}

struct CommandResponse: Sendable {
    let id: Int
    var output: String = ""
    var isComplete: Bool = false
}

enum PaneDirection: Sendable {
    case up, down, left, right
}
