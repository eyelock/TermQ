import AppKit
import Foundation
import SwiftTerm

/// Manages terminal themes and applies them to terminal views
@MainActor
public final class TerminalThemeManager: ObservableObject {
    private static let themeIdKey = "terminalTheme"
    private static let defaultThemeId = "default-dark"

    private let store: any KeyValueStore

    /// Current theme ID (persisted via the injected `KeyValueStore`)
    @Published var themeId: String {
        didSet {
            store.set(themeId, forKey: Self.themeIdKey)
            onThemeChanged?()
        }
    }

    /// Callback when theme changes (for applying to all sessions)
    var onThemeChanged: (() -> Void)?

    /// Current theme
    var currentTheme: TerminalTheme {
        TerminalTheme.theme(for: themeId)
    }

    init(store: any KeyValueStore = UserDefaults.standard) {
        self.store = store
        self.themeId = store.string(forKey: Self.themeIdKey) ?? Self.defaultThemeId
    }

    /// Apply theme to a terminal view
    func applyTheme(to terminal: TermQTerminalView, theme: TerminalTheme? = nil) {
        let theme = theme ?? currentTheme

        terminal.nativeForegroundColor = theme.foreground
        terminal.nativeBackgroundColor = theme.background
        terminal.caretColor = theme.cursor
        terminal.installColors(theme.swiftTermColors)

        if let container = terminal.superview as? TerminalContainerView {
            container.layer?.backgroundColor = theme.background.cgColor
        }

        terminal.setNeedsDisplay(terminal.bounds)
    }

    /// Get the effective theme ID for a card (per-terminal or global)
    func effectiveThemeId(for cardThemeId: String) -> String {
        cardThemeId.isEmpty ? themeId : cardThemeId
    }

    /// Get the theme for a card (per-terminal or global)
    func theme(for cardThemeId: String) -> TerminalTheme {
        TerminalTheme.theme(for: effectiveThemeId(for: cardThemeId))
    }
}
