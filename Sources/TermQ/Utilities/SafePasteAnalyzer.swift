import AppKit
import Foundation

/// Analyzes paste content for potentially dangerous commands and patterns
enum SafePasteAnalyzer {
    /// Potential warning about paste content
    struct Warning {
        let message: String
    }

    /// Analyze paste content for potential dangers
    /// Returns an array of warnings, empty if content is safe
    static func analyze(_ text: String) -> [Warning] {
        var warnings: [Warning] = []

        // Check for multiline content
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if lines.count > 1 {
            warnings.append(
                Warning(message: "Contains \(lines.count) lines - commands will execute automatically"))
        }

        // Check for sudo
        if text.contains("sudo ") || text.hasPrefix("sudo") {
            warnings.append(Warning(message: "Contains 'sudo' - will run with elevated privileges"))
        }

        // Check for potentially destructive commands
        let destructivePatterns = [
            "rm -rf", "rm -fr", "mkfs", "dd if=", "> /dev/",
            ":(){:|:&};:", "chmod -R 777", "chmod 777",
        ]
        for pattern in destructivePatterns {
            if text.contains(pattern) {
                warnings.append(Warning(message: "Contains potentially destructive command: \(pattern)"))
                break
            }
        }

        // Check for curl/wget piped to shell (common attack vector)
        if (text.contains("curl ") || text.contains("wget "))
            && (text.contains("| bash") || text.contains("| sh") || text.contains("|bash")
                || text.contains("|sh"))
        {
            warnings.append(Warning(message: "Downloads and executes remote script - verify source first"))
        }

        // Check for environment variable manipulation
        if text.contains("export ") && (text.contains("PATH=") || text.contains("LD_")) {
            warnings.append(Warning(message: "Modifies environment variables"))
        }

        return warnings
    }

    /// Show warning dialog for paste with dangerous content
    /// Returns the user's choice
    @MainActor
    static func showWarningDialog(text: String, warnings: [Warning]) -> PasteDecision {
        let alert = NSAlert()
        alert.messageText = "Paste Warning"
        alert.informativeText =
            """
            \(warnings.map(\.message).joined(separator: "\n"))

            Preview (first 200 chars):
            \(String(text.prefix(200)))\(text.count > 200 ? "..." : "")
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Paste Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Disable for Terminal")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .paste
        case .alertThirdButtonReturn:
            return .disableAndPaste
        default:
            return .cancel
        }
    }

    /// User's decision after seeing paste warning
    enum PasteDecision {
        case paste
        case cancel
        case disableAndPaste
    }
}
