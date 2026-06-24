import Foundation
import SwiftUI

/// Actions available for keyboard shortcuts
struct TerminalActions {
    /// Create a new terminal quickly (same column and CWD as current, if any)
    let quickNewTerminal: () -> Void
    /// Open the new terminal dialog
    let newTerminalWithDialog: () -> Void
    /// Add a new column
    let newColumn: () -> Void
    /// Close/go back from current view
    let goBack: () -> Void
    /// Toggle favourite status on current terminal
    let toggleFavourite: () -> Void
    /// Switch to next tab
    let nextTab: () -> Void
    /// Switch to previous tab
    let previousTab: () -> Void
    /// Open current directory in native Terminal.app
    let openInTerminalApp: () -> Void
    /// Close current tab (without deleting the terminal)
    let closeTab: () -> Void
    /// Delete the current terminal
    let deleteTerminal: () -> Void
    /// Toggle zoom mode (hide tabs, maximize terminal)
    let toggleZoom: () -> Void
    /// Toggle search bar
    let toggleSearch: () -> Void
    /// Export terminal session to file
    let exportSession: () -> Void
    /// Show command palette
    let showCommandPalette: () -> Void
    /// Show the bin (deleted terminals)
    let showBin: () -> Void
    /// Toggle the worktree sidebar open/closed
    let toggleSidebar: () -> Void
    /// Increase the active terminal's font size by one step
    let increaseFontSize: () -> Void
    /// Decrease the active terminal's font size by one step
    let decreaseFontSize: () -> Void
    /// Reset the active terminal's font size to the global default
    let resetFontSize: () -> Void
}

struct TerminalActionsKey: FocusedValueKey {
    typealias Value = TerminalActions
}

extension FocusedValues {
    var terminalActions: TerminalActions? {
        get { self[TerminalActionsKey.self] }
        set { self[TerminalActionsKey.self] = newValue }
    }
}

/// One open terminal as shown in the Window menu's jump list.
struct OpenTerminalItem: Identifiable {
    let id: UUID
    let title: String
    let isFavourite: Bool
}

/// Snapshot of open terminals for the Window menu, plus the jump action.
/// Republished by ContentView whenever the board changes.
struct WindowMenuModel {
    /// Up to five terminals — most-recently-active first — each assigned
    /// ⌘1–⌘5 in the menu.
    let openTerminals: [OpenTerminalItem]
    /// Total number of open terminals, so the menu shows "All Terminals…"
    /// only when the list is actually capped.
    let totalOpen: Int
    /// Jump to (select) the terminal with the given id.
    let jumpToTerminal: (UUID) -> Void
}

struct WindowMenuModelKey: FocusedValueKey {
    typealias Value = WindowMenuModel
}

extension FocusedValues {
    var windowMenu: WindowMenuModel? {
        get { self[WindowMenuModelKey.self] }
        set { self[WindowMenuModelKey.self] = newValue }
    }
}
