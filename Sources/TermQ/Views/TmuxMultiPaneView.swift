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
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black

                ForEach(panes) { pane in
                    PaneTerminalView(
                        cardId: card.id,
                        paneId: pane.id,
                        isActive: pane.isActive,
                        onFocus: {
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

    private func paneWidth(pane: TmuxPane, totalWidth: CGFloat) -> CGFloat {
        let scale = totalWidth / CGFloat(totalColumns)
        return CGFloat(pane.width) * scale
    }

    private func paneHeight(pane: TmuxPane, totalHeight: CGFloat) -> CGFloat {
        let scale = totalHeight / CGFloat(totalRows)
        return CGFloat(pane.height) * scale
    }

    /// Calculate pane X position (center of pane for .position() modifier)
    private func paneX(pane: TmuxPane, totalWidth: CGFloat) -> CGFloat {
        let scale = totalWidth / CGFloat(totalColumns)
        let leftEdge = CGFloat(pane.x) * scale
        let width = CGFloat(pane.width) * scale
        return leftEdge + (width / 2.0)
    }

    /// Calculate pane Y position (center of pane for .position() modifier)
    private func paneY(pane: TmuxPane, totalHeight: CGFloat) -> CGFloat {
        let scale = totalHeight / CGFloat(totalRows)
        let topEdge = CGFloat(pane.y) * scale
        let height = CGFloat(pane.height) * scale
        return topEdge + (height / 2.0)
    }
}
