import AppKit
import TermQCore

/// NSView that draws pane separator lines and the active-pane focus rect.
///
/// Uses actual pane frame coordinates (not tmux column/row counts) so that the
/// separator positions always align exactly with the pane boundaries, regardless
/// of tmux's 1-unit border-character gaps in its coordinate system.
///
/// `isFlipped = true` — y=0 at top, matching the container's coordinate system.
class TmuxSeparatorOverlayNSView: NSView {
    /// Pane frames in the overlay's coordinate space (same origin as the container).
    var paneFrames: [(id: String, frame: CGRect)] = []
    var activePaneId: String?
    /// Used only to skip all drawing when there is a single pane.
    var paneCount: Int = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// Transparent to mouse — all events pass through to the terminal views below.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard paneCount > 1 else { return }

        // Floating-point tolerance for "are these two edges at the same position?"
        let epsilon: CGFloat = 0.5

        // 1. Gray separator lines.
        //    For each ordered pair (A, B), check if A's right/bottom edge touches B's
        //    left/top edge — meaning they are adjacent panes sharing that boundary.
        //    Drawing only once per pair is guaranteed because the reverse pair (B, A)
        //    has A's edge > B's edge in the relevant dimension, so the guard fails.

        NSColor(white: 0.3, alpha: 1.0).setStroke()

        for i in 0..<paneFrames.count {
            for j in 0..<paneFrames.count where j != i {
                let fa = paneFrames[i].frame
                let fb = paneFrames[j].frame

                // Vertical separator: A is to the left of B.
                if abs(fa.maxX - fb.minX) < epsilon && fb.minX >= fa.maxX - epsilon {
                    let x = (fa.maxX + fb.minX) / 2
                    let startY = max(fa.minY, fb.minY)
                    let endY = min(fa.maxY, fb.maxY)
                    guard startY < endY else { continue }
                    let path = NSBezierPath()
                    path.lineWidth = 1.0
                    path.move(to: NSPoint(x: x, y: startY))
                    path.line(to: NSPoint(x: x, y: endY))
                    path.stroke()
                }

                // Horizontal separator: A is above B (isFlipped — smaller y = higher on screen).
                if abs(fa.maxY - fb.minY) < epsilon && fb.minY >= fa.maxY - epsilon {
                    let y = (fa.maxY + fb.minY) / 2
                    let startX = max(fa.minX, fb.minX)
                    let endX = min(fa.maxX, fb.maxX)
                    guard startX < endX else { continue }
                    let path = NSBezierPath()
                    path.lineWidth = 1.0
                    path.move(to: NSPoint(x: startX, y: y))
                    path.line(to: NSPoint(x: endX, y: y))
                    path.stroke()
                }
            }
        }

        // 2. Focus rect — drawn after separators so the accent colour paints over
        //    the gray line on any shared edges.
        guard let activeId = activePaneId,
            let entry = paneFrames.first(where: { $0.id == activeId })
        else { return }

        NSColor.controlAccentColor.setStroke()
        let focusPath = NSBezierPath(rect: entry.frame)
        focusPath.lineWidth = 1.0
        focusPath.stroke()
    }
}
