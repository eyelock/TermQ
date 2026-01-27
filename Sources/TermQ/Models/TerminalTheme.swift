import AppKit
import SwiftTerm

/// Represents a terminal color theme with ANSI colors
struct TerminalTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let foreground: NSColor
    let background: NSColor
    let cursor: NSColor
    let selection: NSColor
    let ansiColors: [NSColor]  // 16 ANSI colors (0-7 normal, 8-15 bright)

    /// Convert ANSI colors to SwiftTerm Color format
    var swiftTermColors: [Color] {
        ansiColors.map { nsColor in
            let rgb = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
            return Color(
                red: UInt16(rgb.redComponent * 65535),
                green: UInt16(rgb.greenComponent * 65535),
                blue: UInt16(rgb.blueComponent * 65535)
            )
        }
    }

    static func == (lhs: TerminalTheme, rhs: TerminalTheme) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Built-in Themes

extension TerminalTheme {
    /// Default dark theme (similar to Terminal.app)
    static let defaultDark = TerminalTheme(
        id: "default-dark",
        name: "Default Dark",
        foreground: NSColor.hex("#FFFFFF"),
        background: NSColor.hex("#000000"),
        cursor: NSColor.hex("#FFFFFF"),
        selection: NSColor.hex("#4D4D4D"),
        ansiColors: [
            // Normal colors (0-7)
            NSColor.hex("#000000"),  // Black
            NSColor.hex("#C91B00"),  // Red
            NSColor.hex("#00C200"),  // Green
            NSColor.hex("#C7C400"),  // Yellow
            NSColor.hex("#0225C7"),  // Blue
            NSColor.hex("#C930C7"),  // Magenta
            NSColor.hex("#00C5C7"),  // Cyan
            NSColor.hex("#C7C7C7"),  // White
            // Bright colors (8-15)
            NSColor.hex("#686868"),  // Bright Black
            NSColor.hex("#FF6E67"),  // Bright Red
            NSColor.hex("#5FFA68"),  // Bright Green
            NSColor.hex("#FFFC67"),  // Bright Yellow
            NSColor.hex("#6871FF"),  // Bright Blue
            NSColor.hex("#FF76FF"),  // Bright Magenta
            NSColor.hex("#5FFDFF"),  // Bright Cyan
            NSColor.hex("#FFFFFF"),  // Bright White
        ]
    )

    /// Dracula theme
    static let dracula = TerminalTheme(
        id: "dracula",
        name: "Dracula",
        foreground: NSColor.hex("#F8F8F2"),
        background: NSColor.hex("#282A36"),
        cursor: NSColor.hex("#F8F8F2"),
        selection: NSColor.hex("#44475A"),
        ansiColors: [
            // Normal colors (0-7)
            NSColor.hex("#21222C"),  // Black
            NSColor.hex("#FF5555"),  // Red
            NSColor.hex("#50FA7B"),  // Green
            NSColor.hex("#F1FA8C"),  // Yellow
            NSColor.hex("#BD93F9"),  // Blue
            NSColor.hex("#FF79C6"),  // Magenta
            NSColor.hex("#8BE9FD"),  // Cyan
            NSColor.hex("#F8F8F2"),  // White
            // Bright colors (8-15)
            NSColor.hex("#6272A4"),  // Bright Black
            NSColor.hex("#FF6E6E"),  // Bright Red
            NSColor.hex("#69FF94"),  // Bright Green
            NSColor.hex("#FFFFA5"),  // Bright Yellow
            NSColor.hex("#D6ACFF"),  // Bright Blue
            NSColor.hex("#FF92DF"),  // Bright Magenta
            NSColor.hex("#A4FFFF"),  // Bright Cyan
            NSColor.hex("#FFFFFF"),  // Bright White
        ]
    )

    /// One Dark theme
    static let oneDark = TerminalTheme(
        id: "one-dark",
        name: "One Dark",
        foreground: NSColor.hex("#ABB2BF"),
        background: NSColor.hex("#282C34"),
        cursor: NSColor.hex("#528BFF"),
        selection: NSColor.hex("#3E4451"),
        ansiColors: [
            // Normal colors (0-7)
            NSColor.hex("#282C34"),  // Black
            NSColor.hex("#E06C75"),  // Red
            NSColor.hex("#98C379"),  // Green
            NSColor.hex("#E5C07B"),  // Yellow
            NSColor.hex("#61AFEF"),  // Blue
            NSColor.hex("#C678DD"),  // Magenta
            NSColor.hex("#56B6C2"),  // Cyan
            NSColor.hex("#ABB2BF"),  // White
            // Bright colors (8-15)
            NSColor.hex("#5C6370"),  // Bright Black
            NSColor.hex("#E06C75"),  // Bright Red
            NSColor.hex("#98C379"),  // Bright Green
            NSColor.hex("#E5C07B"),  // Bright Yellow
            NSColor.hex("#61AFEF"),  // Bright Blue
            NSColor.hex("#C678DD"),  // Bright Magenta
            NSColor.hex("#56B6C2"),  // Bright Cyan
            NSColor.hex("#FFFFFF"),  // Bright White
        ]
    )

    /// Nord theme
    static let nord = TerminalTheme(
        id: "nord",
        name: "Nord",
        foreground: NSColor.hex("#D8DEE9"),
        background: NSColor.hex("#2E3440"),
        cursor: NSColor.hex("#D8DEE9"),
        selection: NSColor.hex("#434C5E"),
        ansiColors: [
            // Normal colors (0-7)
            NSColor.hex("#3B4252"),  // Black
            NSColor.hex("#BF616A"),  // Red
            NSColor.hex("#A3BE8C"),  // Green
            NSColor.hex("#EBCB8B"),  // Yellow
            NSColor.hex("#81A1C1"),  // Blue
            NSColor.hex("#B48EAD"),  // Magenta
            NSColor.hex("#88C0D0"),  // Cyan
            NSColor.hex("#E5E9F0"),  // White
            // Bright colors (8-15)
            NSColor.hex("#4C566A"),  // Bright Black
            NSColor.hex("#BF616A"),  // Bright Red
            NSColor.hex("#A3BE8C"),  // Bright Green
            NSColor.hex("#EBCB8B"),  // Bright Yellow
            NSColor.hex("#81A1C1"),  // Bright Blue
            NSColor.hex("#B48EAD"),  // Bright Magenta
            NSColor.hex("#8FBCBB"),  // Bright Cyan
            NSColor.hex("#ECEFF4"),  // Bright White
        ]
    )

    /// Solarized Dark theme
    static let solarizedDark = TerminalTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        foreground: NSColor.hex("#839496"),
        background: NSColor.hex("#002B36"),
        cursor: NSColor.hex("#839496"),
        selection: NSColor.hex("#073642"),
        ansiColors: [
            // Normal colors (0-7)
            NSColor.hex("#073642"),  // Black
            NSColor.hex("#DC322F"),  // Red
            NSColor.hex("#859900"),  // Green
            NSColor.hex("#B58900"),  // Yellow
            NSColor.hex("#268BD2"),  // Blue
            NSColor.hex("#D33682"),  // Magenta
            NSColor.hex("#2AA198"),  // Cyan
            NSColor.hex("#EEE8D5"),  // White
            // Bright colors (8-15)
            NSColor.hex("#002B36"),  // Bright Black
            NSColor.hex("#CB4B16"),  // Bright Red
            NSColor.hex("#586E75"),  // Bright Green
            NSColor.hex("#657B83"),  // Bright Yellow
            NSColor.hex("#839496"),  // Bright Blue
            NSColor.hex("#6C71C4"),  // Bright Magenta
            NSColor.hex("#93A1A1"),  // Bright Cyan
            NSColor.hex("#FDF6E3"),  // Bright White
        ]
    )

    /// Solarized Light theme
    static let solarizedLight = TerminalTheme(
        id: "solarized-light",
        name: "Solarized Light",
        foreground: NSColor.hex("#657B83"),
        background: NSColor.hex("#FDF6E3"),
        cursor: NSColor.hex("#657B83"),
        selection: NSColor.hex("#EEE8D5"),
        ansiColors: [
            // Normal colors (0-7)
            NSColor.hex("#073642"),  // Black
            NSColor.hex("#DC322F"),  // Red
            NSColor.hex("#859900"),  // Green
            NSColor.hex("#B58900"),  // Yellow
            NSColor.hex("#268BD2"),  // Blue
            NSColor.hex("#D33682"),  // Magenta
            NSColor.hex("#2AA198"),  // Cyan
            NSColor.hex("#EEE8D5"),  // White
            // Bright colors (8-15)
            NSColor.hex("#002B36"),  // Bright Black
            NSColor.hex("#CB4B16"),  // Bright Red
            NSColor.hex("#586E75"),  // Bright Green
            NSColor.hex("#657B83"),  // Bright Yellow
            NSColor.hex("#839496"),  // Bright Blue
            NSColor.hex("#6C71C4"),  // Bright Magenta
            NSColor.hex("#93A1A1"),  // Bright Cyan
            NSColor.hex("#FDF6E3"),  // Bright White
        ]
    )

    /// GitHub Dark theme
    static let githubDark = TerminalTheme(
        id: "github-dark",
        name: "GitHub Dark",
        foreground: NSColor.hex("#C9D1D9"),
        background: NSColor.hex("#0D1117"),
        cursor: NSColor.hex("#58A6FF"),
        selection: NSColor.hex("#264F78"),
        ansiColors: [
            // Normal colors (0-7)
            NSColor.hex("#484F58"),  // Black
            NSColor.hex("#FF7B72"),  // Red
            NSColor.hex("#3FB950"),  // Green
            NSColor.hex("#D29922"),  // Yellow
            NSColor.hex("#58A6FF"),  // Blue
            NSColor.hex("#BC8CFF"),  // Magenta
            NSColor.hex("#39C5CF"),  // Cyan
            NSColor.hex("#B1BAC4"),  // White
            // Bright colors (8-15)
            NSColor.hex("#6E7681"),  // Bright Black
            NSColor.hex("#FFA198"),  // Bright Red
            NSColor.hex("#56D364"),  // Bright Green
            NSColor.hex("#E3B341"),  // Bright Yellow
            NSColor.hex("#79C0FF"),  // Bright Blue
            NSColor.hex("#D2A8FF"),  // Bright Magenta
            NSColor.hex("#56D4DD"),  // Bright Cyan
            NSColor.hex("#FFFFFF"),  // Bright White
        ]
    )

    /// Monokai theme
    static let monokai = TerminalTheme(
        id: "monokai",
        name: "Monokai",
        foreground: NSColor.hex("#F8F8F2"),
        background: NSColor.hex("#272822"),
        cursor: NSColor.hex("#F8F8F2"),
        selection: NSColor.hex("#49483E"),
        ansiColors: [
            // Normal colors (0-7)
            NSColor.hex("#272822"),  // Black
            NSColor.hex("#F92672"),  // Red
            NSColor.hex("#A6E22E"),  // Green
            NSColor.hex("#F4BF75"),  // Yellow
            NSColor.hex("#66D9EF"),  // Blue
            NSColor.hex("#AE81FF"),  // Magenta
            NSColor.hex("#A1EFE4"),  // Cyan
            NSColor.hex("#F8F8F2"),  // White
            // Bright colors (8-15)
            NSColor.hex("#75715E"),  // Bright Black
            NSColor.hex("#F92672"),  // Bright Red
            NSColor.hex("#A6E22E"),  // Bright Green
            NSColor.hex("#F4BF75"),  // Bright Yellow
            NSColor.hex("#66D9EF"),  // Bright Blue
            NSColor.hex("#AE81FF"),  // Bright Magenta
            NSColor.hex("#A1EFE4"),  // Bright Cyan
            NSColor.hex("#F9F8F5"),  // Bright White
        ]
    )

    /// All available themes
    static let allThemes: [TerminalTheme] = [
        .defaultDark,
        .dracula,
        .oneDark,
        .nord,
        .solarizedDark,
        .solarizedLight,
        .githubDark,
        .monokai,
    ]

    /// Get theme by ID
    static func theme(for id: String) -> TerminalTheme {
        allThemes.first { $0.id == id } ?? .defaultDark
    }
}

// MARK: - NSColor Hex Extension

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// Non-failable hex initializer for compile-time constant colors
    /// - Parameter hex: Valid hex color string (e.g., "#FFFFFF")
    /// - Returns: NSColor - will crash if hex is invalid (use only for hardcoded theme colors)
    static func hex(_ hex: String) -> NSColor {
        guard let color = NSColor(hex: hex) else {
            preconditionFailure("Invalid hex color: \(hex)")
        }
        return color
    }
}
