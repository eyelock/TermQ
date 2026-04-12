import AppKit
import SwiftUI
import TermQCore

/// Multi-pane view for tmux sessions with control mode
///
/// This view renders multiple terminal panes in a tmux session layout:
/// - Reads pane layout from control mode parser
/// - Positions PaneTerminalView for each pane
/// - Handles pane selection and input routing
struct TmuxMultiPaneView: View {
    let card: TerminalCard
    let onExit: () -> Void
    let onBell: () -> Void

    @ObservedObject private var sessionManager = TerminalSessionManager.shared

    /// Get control mode session for this card
    private var controlSession: TmuxControlModeSession? {
        sessionManager.getControlModeSession(for: card.id)
    }

    /// Get panes from control mode parser
    private var panes: [TmuxPane] {
        controlSession?.parser.panes ?? []
    }

    /// Total columns across all panes
    private var totalColumns: Int {
        panes.map { $0.x + $0.width }.max() ?? 80
    }

    /// Total rows across all panes
    private var totalRows: Int {
        panes.map { $0.y + $0.height }.max() ?? 24
    }

    var body: some View {
        // A single NSViewRepresentable owns all pane subviews and the overlay,
        // guaranteeing correct AppKit z-ordering without SwiftUI ZStack ambiguity.
        TmuxMultiPaneContainerView(
            cardId: card.id,
            panes: panes,
            activePaneId: sessionManager.getActivePaneId(for: card.id),
            totalColumns: totalColumns,
            totalRows: totalRows,
            onFocus: { paneId in
                sessionManager.setActivePane(cardId: card.id, paneId: paneId)
            }
        )
    }
}
