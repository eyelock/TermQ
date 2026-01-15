import AppKit
import SwiftUI

/// Centralized constants for the TermQ application
/// Consolidates magic strings and values that were previously scattered across the codebase
enum Constants {
    // MARK: - Shell Configuration

    enum Shell {
        /// Default shell path for new terminals
        static let defaultPath = "/bin/zsh"

        /// Shell used for command execution (non-interactive wrapper)
        static let commandShell = "/bin/sh"

        /// Supported shell paths
        static let supportedShells = ["/bin/zsh", "/bin/bash", "/bin/sh", "/bin/fish"]
    }

    // MARK: - Terminal Environment

    enum Terminal {
        /// TERM environment variable value
        static let termType = "xterm-256color"

        /// COLORTERM environment variable value
        static let colorTerm = "truecolor"

        /// Default LANG if not set
        static let defaultLang = "en_US.UTF-8"

        /// Default font size for terminals
        static let defaultFontSize: CGFloat = 13
    }

    // MARK: - Default Columns

    enum Columns {
        /// Default column configuration for new boards
        struct ColumnConfig: Sendable {
            let name: String
            let color: String
        }

        static let defaults: [ColumnConfig] = [
            ColumnConfig(name: "To Do", color: "#6B7280"),
            ColumnConfig(name: "In Progress", color: "#3B82F6"),
            ColumnConfig(name: "Blocked", color: "#EF4444"),
            ColumnConfig(name: "Done", color: "#10B981"),
        ]

        /// Default column name when none specified
        static let fallbackName = "To Do"

        /// Default color for columns
        static let defaultColor = "#6B7280"
    }

    // MARK: - Column Color Palette

    enum ColorPalette {
        /// Available colors for column customization
        static let columnColors: [(hex: String, name: String)] = [
            ("#6B7280", "Gray"),
            ("#3B82F6", "Blue"),
            ("#10B981", "Green"),
            ("#EF4444", "Red"),
            ("#F59E0B", "Yellow"),
            ("#8B5CF6", "Purple"),
            ("#EC4899", "Pink"),
            ("#06B6D4", "Cyan"),
        ]
    }

    // MARK: - LLM Token Patterns

    enum LLMTokens {
        /// Token for persistent LLM context in init commands
        static let prompt = "{{LLM_PROMPT}}"

        /// Token for one-time LLM action in init commands
        static let nextAction = "{{LLM_NEXT_ACTION}}"
    }

    // MARK: - Activity Detection

    enum Activity {
        /// Threshold for throttling activity callbacks (seconds)
        static let callbackThrottle: TimeInterval = 0.3

        /// Time after user input before showing activity spinner (seconds)
        static let inputDelay: TimeInterval = 0.5

        /// Default threshold for "processing" detection (seconds)
        static let processingThreshold: TimeInterval = 2.0
    }
}
