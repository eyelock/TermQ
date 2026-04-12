import AppKit
import SwiftUI
import TermQCore

/// SwiftUI wrapper for the tmux multi-pane AppKit container.
///
/// A single NSViewRepresentable owns all pane NSViews plus the separator/focus overlay.
/// Because the overlay is added last via `addSubview(_:positioned:relativeTo:)`, AppKit
/// guarantees it composites above all terminal views — no SwiftUI ZStack z-order ambiguity.
struct TmuxMultiPaneContainerView: NSViewRepresentable {
    let cardId: UUID
    let panes: [TmuxPane]
    let activePaneId: String?
    let totalColumns: Int
    let totalRows: Int
    let onFocus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TmuxMultiPaneContainerNSView {
        TmuxMultiPaneContainerNSView(cardId: cardId)
    }

    func updateNSView(_ nsView: TmuxMultiPaneContainerNSView, context: Context) {
        nsView.onFocus = onFocus
        nsView.update(
            panes: panes,
            activePaneId: activePaneId,
            totalColumns: totalColumns,
            totalRows: totalRows,
            theme: TerminalSessionManager.shared.currentTheme
        )

        // Give keyboard focus to the newly active pane. Only fire on transition
        // to avoid calling makeFirstResponder on every SwiftUI render pass.
        if activePaneId != context.coordinator.lastActivePaneId,
            let activeId = activePaneId
        {
            TermQLogger.focus.debug("makeFirstResponder scheduled pane=\(activeId)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak nsView] in
                guard let paneView = nsView?.paneViews[activeId],
                    let terminal = paneView.terminalView
                else { return }
                terminal.window?.makeFirstResponder(terminal)
                TermQLogger.focus.debug(
                    "makeFirstResponder applied pane=\(activeId) hasWindow=\(terminal.window != nil)"
                )
            }
        }
        context.coordinator.lastActivePaneId = activePaneId
    }

    class Coordinator {
        var lastActivePaneId: String?
    }
}

/// NSView that owns all pane subviews and the separator/focus overlay.
///
/// Pane views are always inserted below the overlay (`positioned: .below, relativeTo: overlay`),
/// so the overlay's AppKit z-order is guaranteed to be above all terminal content.
///
/// Uses `isFlipped = true` so that pane (x, y) coordinates from tmux (y=0 at top) map
/// directly to view layout coordinates without manual axis flipping.
class TmuxMultiPaneContainerNSView: NSView {
    let cardId: UUID
    private(set) var paneViews: [String: PaneTerminalViewNSView] = [:]
    private let overlay: TmuxSeparatorOverlayNSView
    var onFocus: ((String) -> Void)?

    private var currentPanes: [TmuxPane] = []

    init(cardId: UUID) {
        self.cardId = cardId
        overlay = TmuxSeparatorOverlayNSView()
        super.init(frame: .zero)
        wantsLayer = true
        // Overlay is the only subview at init time — any pane views added later
        // use .below to stay beneath it, keeping overlay as the topmost subview.
        addSubview(overlay)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// y=0 at top → pane.y coordinates map directly to frame origins. No axis flip needed.
    override var isFlipped: Bool { true }

    func update(
        panes: [TmuxPane],
        activePaneId: String?,
        totalColumns: Int,
        totalRows: Int,
        theme: TerminalTheme
    ) {
        currentPanes = panes
        layer?.backgroundColor = theme.background.cgColor

        // Remove views for panes that no longer exist
        let currentIds = Set(panes.map { $0.id })
        for id in Array(paneViews.keys) where !currentIds.contains(id) {
            paneViews[id]?.removeFromSuperview()
            paneViews.removeValue(forKey: id)
        }

        // Add views for new panes, always inserted BELOW the overlay
        for pane in panes where paneViews[pane.id] == nil {
            let paneView = PaneTerminalViewNSView(cardId: cardId, paneId: pane.id)
            let paneId = pane.id
            paneView.onFocus = { [weak self] in self?.onFocus?(paneId) }
            addSubview(paneView, positioned: .below, relativeTo: overlay)
            paneViews[pane.id] = paneView
        }

        // Bring the active pane to the front of the pane-view stack (just below
        // the overlay). This guarantees a zoomed pane composites above its siblings
        // regardless of the order in which pane views were originally inserted.
        if let activeId = activePaneId, let activePaneView = paneViews[activeId] {
            activePaneView.removeFromSuperview()
            addSubview(activePaneView, positioned: .below, relativeTo: overlay)
        }

        // Update active state on each pane (used by hitTest to decide when to call onFocus)
        for (paneId, paneView) in paneViews {
            paneView.isActivePan = paneId == activePaneId
        }

        // Overlay data is updated after layout() computes extended frames
        overlay.paneCount = panes.count
        overlay.activePaneId = activePaneId

        needsLayout = true
        overlay.needsDisplay = true
    }

    override func layout() {
        super.layout()

        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0, !currentPanes.isEmpty else { return }

        let totalCols = currentPanes.map { $0.x + $0.width }.max() ?? 80
        let totalRows = currentPanes.map { $0.y + $0.height }.max() ?? 24
        let colScale = w / CGFloat(totalCols)
        let rowScale = h / CGFloat(totalRows)

        // Tmux uses 1 column/row for border characters between panes, so adjacent
        // panes have a 1-unit gap in their coordinates. To tile frames edge-to-edge
        // (no dark gap between panes), each pane absorbs half the border gap on each
        // inner side. Window-edge sides are not extended.
        let halfCol = colScale / 2
        let halfRow = rowScale / 2

        var framesForOverlay: [(id: String, frame: CGRect)] = []

        for pane in currentPanes {
            guard let paneView = paneViews[pane.id] else { continue }

            let baseX = CGFloat(pane.x) * colScale
            let baseY = CGFloat(pane.y) * rowScale
            let baseW = CGFloat(pane.width) * colScale
            let baseH = CGFloat(pane.height) * rowScale

            let extL = pane.x > 0 ? halfCol : 0
            let extR = (pane.x + pane.width) < totalCols ? halfCol : 0
            let extT = pane.y > 0 ? halfRow : 0
            let extB = (pane.y + pane.height) < totalRows ? halfRow : 0

            let frame = CGRect(
                x: baseX - extL,
                y: baseY - extT,
                width: baseW + extL + extR,
                height: baseH + extT + extB
            )
            paneView.frame = frame
            framesForOverlay.append((id: pane.id, frame: frame))
        }

        overlay.frame = bounds

        // Zoom detection: when a pane is zoomed its tmux-reported dimensions fill the
        // entire window, producing a frame that equals the container bounds exactly
        // (no half-gap extensions apply at the window edges).
        let isZoomed = framesForOverlay.contains { abs($0.frame.width - w) < 1 && abs($0.frame.height - h) < 1 }
        let activeId = overlay.activePaneId

        // When zoomed, pass only the zoomed pane's frame to the overlay. The separator
        // drawing loop requires ≥2 frames to find an adjacent pair, so with a single
        // frame no separators are drawn — removing the phantom lines at the pre-zoom
        // sibling positions that would otherwise bleed through the zoomed view.
        if isZoomed, let zoomedFrame = framesForOverlay.first(where: { $0.id == activeId }) {
            overlay.paneFrames = [zoomedFrame]
        } else {
            overlay.paneFrames = framesForOverlay
        }
        overlay.needsDisplay = true

        // Hide non-active pane views so their terminal content doesn't show through.
        for (paneId, paneView) in paneViews {
            paneView.isHidden = isZoomed && paneId != activeId
        }
    }
}
