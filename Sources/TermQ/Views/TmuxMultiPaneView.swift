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

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Black background
                Color.black

                // Render each pane
                ForEach(panes) { pane in
                    PaneTerminalView(
                        cardId: card.id,
                        paneId: pane.id,
                        isActive: pane.isActive,
                        onFocus: {
                            // Focus this pane
                            sessionManager.setActivePane(cardId: card.id, paneId: pane.id)
                        }
                    )
                    .frame(
                        width: paneWidth(pane: pane, totalWidth: geometry.size.width),
                        height: paneHeight(pane: pane, totalHeight: geometry.size.height)
                    )
                    .position(
                        x: paneX(pane: pane, totalWidth: geometry.size.width),
                        y: paneY(pane: pane, totalHeight: geometry.size.height)
                    )
                }
            }
        }
    }

    // MARK: - Pane Layout Calculations

    /// Calculate pane width based on pane geometry and parent width
    private func paneWidth(pane: TmuxPane, totalWidth: CGFloat) -> CGFloat {
        let charWidth = totalWidth / 80.0  // Assume 80 columns default
        return CGFloat(pane.width) * charWidth
    }

    /// Calculate pane height based on pane geometry and parent height
    private func paneHeight(pane: TmuxPane, totalHeight: CGFloat) -> CGFloat {
        let charHeight = totalHeight / 24.0  // Assume 24 rows default
        return CGFloat(pane.height) * charHeight
    }

    /// Calculate pane X position (center of pane)
    private func paneX(pane: TmuxPane, totalWidth: CGFloat) -> CGFloat {
        let charWidth = totalWidth / 80.0
        let leftEdge = CGFloat(pane.x) * charWidth
        let width = CGFloat(pane.width) * charWidth
        return leftEdge + (width / 2.0)
    }

    /// Calculate pane Y position (center of pane)
    private func paneY(pane: TmuxPane, totalHeight: CGFloat) -> CGFloat {
        let charHeight = totalHeight / 24.0
        let topEdge = CGFloat(pane.y) * charHeight
        let height = CGFloat(pane.height) * charHeight
        return topEdge + (height / 2.0)
    }
}
