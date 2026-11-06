import AppKit
import XCTest

@testable import TermQ

@MainActor
final class HarnessClipboardTests: XCTestCase {
    private func makeFocus(profile: String? = "review") -> CopiedFocus {
        CopiedFocus(name: "triage", prompt: "Triage the open issues", profile: profile, sourceHarnessID: "a")
    }

    func testCopyStoresFocusAndPutsPromptOnPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("termq.test.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let clipboard = HarnessClipboard(pasteboard: pasteboard)

        clipboard.copy(makeFocus())

        XCTAssertEqual(clipboard.focus, makeFocus())
        XCTAssertEqual(pasteboard.string(forType: .string), "Triage the open issues")
    }

    func testCopyWithoutPasteboardStillStoresFocus() {
        let clipboard = HarnessClipboard(pasteboard: nil)
        XCTAssertNil(clipboard.focus)

        clipboard.copy(makeFocus())

        XCTAssertEqual(clipboard.focus?.name, "triage")
    }

    func testPastingKeepsProfileThatExistsOnTarget() {
        let target = FocusEditTarget.pasting(makeFocus(), availableProfiles: ["default", "review"])

        XCTAssertEqual(target, FocusEditTarget(name: "triage", prompt: "Triage the open issues", profile: "review"))
    }

    func testPastingDropsProfileMissingOnTarget() {
        let target = FocusEditTarget.pasting(makeFocus(), availableProfiles: ["default"])

        XCTAssertNil(target.profile)
        XCTAssertEqual(target.name, "triage")
        XCTAssertEqual(target.prompt, "Triage the open issues")
    }

    func testPastingFocusWithoutProfile() {
        let target = FocusEditTarget.pasting(makeFocus(profile: nil), availableProfiles: ["review"])

        XCTAssertNil(target.profile)
    }
}
