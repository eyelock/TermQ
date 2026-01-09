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
    /// Toggle pin on current terminal
    let togglePin: () -> Void
    /// Switch to next pinned terminal
    let nextPinnedTerminal: () -> Void
    /// Switch to previous pinned terminal
    let previousPinnedTerminal: () -> Void
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
