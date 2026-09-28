import AppKit
import SwiftTerm

/// Owns the drag-to-select workaround that lets users select text in panes whose
/// inner app has mouse reporting enabled (e.g. Claude Code TUI).
///
/// The technique: keep `allowMouseReporting = true` so single clicks reach the
/// inner app, then flip it to `false` on the first `leftMouseDragged` so SwiftTerm
/// stops forwarding the drag to the app and starts a selection instead. The flag
/// stays `false` until the next `leftMouseDown`, so the rest of the gesture is
/// never forwarded either. SwiftTerm 2.x preserves a valid selection while output
/// streams and keeps the viewport where the user scrolled it (`userScrolling`),
/// so no further protection is needed here.
///
/// Composed into terminal view subclasses (`TermQTerminalView`,
/// `ControlModeTerminalView`) since they have different `TerminalView` ancestors
/// and can't share a Swift base class.
@MainActor
final class TerminalSelectionDragController {

    // MARK: - State

    private weak var view: TerminalView?

    private var dragEventMonitor: Any?
    private var mouseDownMonitor: Any?

    private var autoScrollTimer: Timer?
    private var autoScrollDelta: Int = 0
    private var lastDragPosition: NSPoint?

    /// Whether the current drag started inside our terminal view.
    private(set) var dragStartedInTerminal: Bool = false

    // MARK: - Decision Logic

    /// Whether a mouse-down should clear the live selection before the click is
    /// forwarded to the inner app.
    ///
    /// SwiftTerm's `mouseDown` clears an active selection so the next drag starts
    /// a fresh one — but only on the branch it reaches when mouse reporting is
    /// off. When the inner app has mouse tracking on (GitHub Copilot CLI sets
    /// mode 1003 / `.anyEvent`), `mouseDown` returns early to forward the click
    /// and never clears it. The next drag then sees `selection.active == true`
    /// and calls `dragExtend`, growing the *previous* selection from its old
    /// anchor instead of starting at the new one.
    ///
    /// Shift-clicks are left alone: SwiftTerm bypasses mouse reporting for them
    /// and extends the selection, which is the intended behavior.
    nonisolated static func shouldClearSelection(
        selectionActive: Bool,
        startedInTerminal: Bool,
        shiftHeld: Bool
    ) -> Bool {
        selectionActive && startedInTerminal && !shiftHeld
    }

    // MARK: - Lifecycle

    init(view: TerminalView) {
        self.view = view
    }

    /// Install the NSEvent monitors. Idempotent — calling twice replaces them.
    func start() {
        stop()

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            self?.handleMouseDown(event)
            return event
        }

        dragEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    /// Remove monitors and reset all drag state.
    func stop() {
        if let monitor = dragEventMonitor {
            NSEvent.removeMonitor(monitor)
            dragEventMonitor = nil
        }
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
        stopAutoScrollTimer()
        dragStartedInTerminal = false
        TerminalSessionManager.shared.isMouseDragInProgress = false
    }

    // MARK: - Event Handlers

    private func handleMouseDown(_ event: NSEvent) {
        guard let view,
            let eventWindow = event.window,
            eventWindow == view.window
        else {
            dragStartedInTerminal = false
            return
        }

        #if TERMQ_DEBUG_BUILD
            let wasReporting = view.allowMouseReporting
            let mm = "\(view.currentMouseMode)"
        #endif

        // Restore mouse reporting so clicks are forwarded to the running app
        // (e.g. Claude Code TUI). This was disabled during a previous
        // drag-to-select to prevent SwiftTerm from intercepting drags.
        view.allowMouseReporting = true

        let localPoint = view.convert(event.locationInWindow, from: nil)
        dragStartedInTerminal = view.bounds.contains(localPoint)

        if dragStartedInTerminal {
            TerminalSessionManager.shared.isMouseDragInProgress = true
        }

        // Stand in for the selection reset SwiftTerm skips when it forwards the
        // click to a mouse-tracking app — see `shouldClearSelection`.
        if Self.shouldClearSelection(
            selectionActive: view.selectionActive,
            startedInTerminal: dragStartedInTerminal,
            shiftHeld: event.modifierFlags.contains(.shift)
        ) {
            view.selectNone()
            view.setNeedsDisplay(view.bounds)
        }

        #if TERMQ_DEBUG_BUILD
            if TermQLogger.fileLoggingEnabled {
                let inTerm = self.dragStartedInTerminal
                let loc = "(\(Int(localPoint.x)),\(Int(localPoint.y)))"
                TermQLogger.io.debug(
                    "sel.mouseDown inTerm=\(inTerm) reporting \(wasReporting)→true mouseMode=\(mm) loc=\(loc)"
                )
            }
        #endif
    }

    private func handleMouseEvent(_ event: NSEvent) {
        guard let view,
            let eventWindow = event.window,
            eventWindow == view.window
        else { return }

        if event.type == .leftMouseUp {
            #if TERMQ_DEBUG_BUILD
                if TermQLogger.fileLoggingEnabled {
                    TermQLogger.io.debug(
                        "sel.mouseUp reporting=\(view.allowMouseReporting) inTerm=\(self.dragStartedInTerminal)"
                    )
                }
            #endif
            stopAutoScrollTimer()
            lastDragPosition = nil
            dragStartedInTerminal = false
            TerminalSessionManager.shared.isMouseDragInProgress = false
            // Do NOT restore allowMouseReporting here — the mouse-up would
            // otherwise be forwarded to the inner app as the tail of a drag it
            // never saw begin. It is restored in handleMouseDown on the next click.
            return
        }

        if event.type == .leftMouseDragged {
            if dragStartedInTerminal && view.allowMouseReporting {
                #if TERMQ_DEBUG_BUILD
                    if TermQLogger.fileLoggingEnabled {
                        let mode = "\(view.currentMouseMode)"
                        TermQLogger.io.debug(
                            "sel.firstDrag flipping reporting true→false mouseMode=\(mode)"
                        )
                    }
                #endif
                view.allowMouseReporting = false
            }
        }

        guard dragStartedInTerminal else { return }

        lastDragPosition = event.locationInWindow

        let localPoint = view.convert(event.locationInWindow, from: nil)

        // Only process if drag is within our x bounds.
        guard localPoint.x >= 0, localPoint.x <= view.bounds.width else {
            stopAutoScrollTimer()
            return
        }

        let viewHeight = view.bounds.height
        autoScrollDelta = 0

        if localPoint.y > viewHeight {
            // Mouse above the view (NSView y=0 is at bottom) — scroll up into history.
            let overshoot = localPoint.y - viewHeight
            autoScrollDelta = -calcScrollSpeed(overshoot: overshoot)
        } else if localPoint.y < 0 {
            // Mouse below the view — scroll down toward live tail.
            let overshoot = -localPoint.y
            autoScrollDelta = calcScrollSpeed(overshoot: overshoot)
        }

        if autoScrollDelta != 0 {
            startAutoScrollTimer()
        } else {
            stopAutoScrollTimer()
        }
    }

    // MARK: - Auto-scroll Timer

    private func calcScrollSpeed(overshoot: CGFloat) -> Int {
        if overshoot > 100 { return 5 }
        if overshoot > 50 { return 3 }
        if overshoot > 20 { return 2 }
        return 1
    }

    private func startAutoScrollTimer() {
        guard autoScrollTimer == nil else { return }

        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.autoScrollTimerFired()
            }
        }
    }

    private func stopAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollDelta = 0
    }

    /// Scrolling up through the view marks the terminal as user-scrolled, so
    /// streaming output no longer drags the viewport back to the live tail
    /// between timer fires; each tick can simply move by the delta.
    private func autoScrollTimerFired() {
        guard let view, autoScrollDelta != 0 else { return }

        if autoScrollDelta < 0 {
            view.scrollUp(lines: -autoScrollDelta)
        } else {
            view.scrollDown(lines: autoScrollDelta)
        }
    }
}
