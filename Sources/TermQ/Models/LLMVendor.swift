import Foundation

/// Supported LLM CLI tools for init command generation
enum LLMVendor: String, CaseIterable {
    case claudeCode = "Claude Code"
    case cursor = "Cursor"
    case aider = "Aider"
    case copilot = "GitHub Copilot"
    case custom = "Custom"

    /// Generate command template based on interactive mode
    /// Note: Tokens are placed inside double quotes to show users the expected structure
    /// Values are escaped for double-quote context during injection
    func commandTemplate(interactive: Bool) -> String {
        switch self {
        case .claudeCode:
            if interactive {
                return "claude \"{{LLM_PROMPT}} {{LLM_NEXT_ACTION}}\""
            } else {
                return "claude -p \"{{LLM_PROMPT}} {{LLM_NEXT_ACTION}}\""
            }
        case .cursor:
            if interactive {
                return "agent \"{{LLM_PROMPT}} {{LLM_NEXT_ACTION}}\""
            } else {
                return "agent -p \"{{LLM_PROMPT}} {{LLM_NEXT_ACTION}}\""
            }
        case .aider:
            // Aider is inherently non-interactive with --message
            return "aider --message \"{{LLM_PROMPT}} {{LLM_NEXT_ACTION}}\""
        case .copilot:
            return "gh copilot suggest \"{{LLM_PROMPT}} {{LLM_NEXT_ACTION}}\""
        case .custom:
            return "\"{{LLM_PROMPT}} {{LLM_NEXT_ACTION}}\""
        }
    }

    /// Whether this tool's template includes persistent context
    var includesPrompt: Bool {
        switch self {
        case .claudeCode, .cursor, .custom, .aider, .copilot:
            return true
        }
    }

    /// Whether this tool supports interactive mode toggle
    var supportsInteractiveToggle: Bool {
        switch self {
        case .claudeCode, .cursor:
            return true
        case .aider, .copilot, .custom:
            return false
        }
    }
}
