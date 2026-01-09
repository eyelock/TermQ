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
