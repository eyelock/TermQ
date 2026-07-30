import XCTest

@testable import TermQ

final class LLMVendorTests: XCTestCase {

    // MARK: - commandTemplate — Claude Code

    func testClaudeCode_interactive_containsClaudeAndPromptTokens() {
        let template = LLMVendor.claudeCode.commandTemplate(interactive: true)
        XCTAssertTrue(template.hasPrefix("claude "))
        XCTAssertTrue(template.contains("{{PROMPT}}"))
        XCTAssertTrue(template.contains("{{NEXT_ACTION}}"))
    }

    func testClaudeCode_nonInteractive_containsDashP() {
        let template = LLMVendor.claudeCode.commandTemplate(interactive: false)
        XCTAssertTrue(template.contains("-p "))
        XCTAssertTrue(template.contains("{{PROMPT}}"))
    }

    func testClaudeCode_interactive_doesNotContainDashP() {
        let template = LLMVendor.claudeCode.commandTemplate(interactive: true)
        XCTAssertFalse(template.contains("-p "))
    }

    // MARK: - commandTemplate — Cursor

    func testCursor_interactive_containsAgentAndTokens() {
        let template = LLMVendor.cursor.commandTemplate(interactive: true)
        XCTAssertTrue(template.hasPrefix("agent "))
        XCTAssertTrue(template.contains("{{PROMPT}}"))
        XCTAssertTrue(template.contains("{{NEXT_ACTION}}"))
    }

    func testCursor_nonInteractive_containsDashP() {
        let template = LLMVendor.cursor.commandTemplate(interactive: false)
        XCTAssertTrue(template.contains("-p "))
    }

    // MARK: - commandTemplate — Aider

    func testAider_sameTemplateRegardlessOfInteractive() {
        let interactive = LLMVendor.aider.commandTemplate(interactive: true)
        let nonInteractive = LLMVendor.aider.commandTemplate(interactive: false)
        XCTAssertEqual(interactive, nonInteractive)
    }

    func testAider_containsMessageFlag() {
        let template = LLMVendor.aider.commandTemplate(interactive: false)
        XCTAssertTrue(template.contains("--message "))
        XCTAssertTrue(template.contains("{{PROMPT}}"))
    }

    // MARK: - commandTemplate — GitHub Copilot

    func testCopilot_interactive_containsDashICapitalAndTokens() {
        let template = LLMVendor.copilot.commandTemplate(interactive: true)
        XCTAssertTrue(template.hasPrefix("copilot "))
        XCTAssertTrue(template.contains("-i "))
        XCTAssertTrue(template.contains("{{PROMPT}}"))
        XCTAssertTrue(template.contains("{{NEXT_ACTION}}"))
    }

    func testCopilot_nonInteractive_containsDashPAndAllowAllTools() {
        let template = LLMVendor.copilot.commandTemplate(interactive: false)
        XCTAssertTrue(template.contains("-p "))
        XCTAssertTrue(template.contains("--allow-all-tools"))
        XCTAssertTrue(template.contains("{{PROMPT}}"))
    }

    func testCopilot_interactive_doesNotContainDashP() {
        let template = LLMVendor.copilot.commandTemplate(interactive: true)
        XCTAssertFalse(template.contains("-p "))
    }

    // MARK: - commandTemplate — Custom

    func testCustom_containsOnlyTokens() {
        let template = LLMVendor.custom.commandTemplate(interactive: false)
        XCTAssertTrue(template.contains("{{PROMPT}}"))
        XCTAssertTrue(template.contains("{{NEXT_ACTION}}"))
    }

    // MARK: - supportsInteractiveToggle

    func testSupportsInteractiveToggle_trueForClaudeCodeCursorAndCopilot() {
        XCTAssertTrue(LLMVendor.claudeCode.supportsInteractiveToggle)
        XCTAssertTrue(LLMVendor.cursor.supportsInteractiveToggle)
        XCTAssertTrue(LLMVendor.copilot.supportsInteractiveToggle)
    }

    func testSupportsInteractiveToggle_falseForOthers() {
        XCTAssertFalse(LLMVendor.aider.supportsInteractiveToggle)
        XCTAssertFalse(LLMVendor.custom.supportsInteractiveToggle)
    }

    // MARK: - includesPrompt

    func testIncludesPrompt_trueForAllCases() {
        for vendor in LLMVendor.allCases {
            XCTAssertTrue(vendor.includesPrompt, "\(vendor.rawValue) should include prompt")
        }
    }

    // MARK: - Enum metadata

    func testAllCases_haveNonEmptyRawValues() {
        for vendor in LLMVendor.allCases {
            XCTAssertFalse(vendor.rawValue.isEmpty)
        }
    }

    func testAllCases_haveDistinctRawValues() {
        let rawValues = LLMVendor.allCases.map(\.rawValue)
        XCTAssertEqual(rawValues.count, Set(rawValues).count)
    }

    func testAllCases_fiveCases() {
        XCTAssertEqual(LLMVendor.allCases.count, 5)
    }

    // MARK: - Template token consistency

    func testAllCases_interactiveTemplatesContainBothTokens() {
        for vendor in LLMVendor.allCases {
            let template = vendor.commandTemplate(interactive: true)
            XCTAssertTrue(template.contains("{{PROMPT}}"), "\(vendor.rawValue) missing {{PROMPT}}")
            XCTAssertTrue(
                template.contains("{{NEXT_ACTION}}"), "\(vendor.rawValue) missing {{NEXT_ACTION}}")
        }
    }

    func testAllCases_nonInteractiveTemplatesContainBothTokens() {
        for vendor in LLMVendor.allCases {
            let template = vendor.commandTemplate(interactive: false)
            XCTAssertTrue(template.contains("{{PROMPT}}"), "\(vendor.rawValue) missing {{PROMPT}}")
            XCTAssertTrue(
                template.contains("{{NEXT_ACTION}}"), "\(vendor.rawValue) missing {{NEXT_ACTION}}")
        }
    }
}
