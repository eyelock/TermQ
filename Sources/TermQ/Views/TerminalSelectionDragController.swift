import AppKit
import SwiftTerm

/// Owns the drag-to-select workaround that lets users select text in panes whose
/// inner app has mouse reporting enabled (e.g. Claude Code TUI).
///
/// The technique: keep `allowMouseReporting = true` so single clicks reach the
/// inner app, then flip it to `false` on the first `leftMouseDragged` so SwiftTerm
/// stops intercepting drags and starts a selection. The flag stays `false` until
/// the next `leftMouseDown`, which keeps streaming output from clearing the
/// selection via `feedPrepare()` / `linefeed()`.
///
/// Composed into terminal view subclasses (`TermQTerminalView`,
/// `ControlModeTerminalView`) since they have different `TerminalView` ancestors
/// and can't share a Swift base class. Each subclass forwards its `linefeed`,
/// `scrolled`, and `selectionChanged` overrides into the controller.
@MainActor
final class TerminalSelectionDragController {

    // MARK: - State

    private weak var view: TerminalView?

    private var dragEventMonitor: Any?
    private var mouseDownMonitor: Any?

    private var autoScrollTimer: Timer?
    private var autoScrollDelta: Int = 0
    private var lastDragPosition: NSPoint?

    /// Target yDisp row for upward auto-scroll; nil when not active.
    /// Persists the intended viewport position across linefeed resets.
    private var selectionScrollTargetRow: Int?

    /// Whether the current drag started inside our terminal view.
    private(set) var dragStartedInTerminal: Bool = false

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

    // MARK: - View-side hooks

    /// True while a drag-to-select is live and SwiftTerm's default linefeed
    /// `selectNone()` should be suppressed to avoid flicker.
    var shouldSuppressLinefeed: Bool {
        guard let view else { return false }
        return !view.allowMouseReporting
    }

    /// Forward from the view's `scrolled(source:yDisp:)` override after `super`.
    /// Re-applies the upward auto-scroll target so streaming linefeeds don't
    /// undo it.
    func handleScrolled(yDisp: Int) {
        guard let view, let targetRow = selectionScrollTargetRow, yDisp > targetRow else { return }
        view.scrollUp(lines: yDisp - targetRow)
    }

    /// Forward from the view's `selectionChanged(source:)` override — pure
    /// diagnostic surface, no behavior.
    func handleSelectionChanged() {
        #if TERMQ_DEBUG_BUILD
            guard TermQLogger.fileLoggingEnabled, let view else { return }
            let active = view.selectionActive
            let reporting = view.allowMouseReporting
            TermQLogger.io.debug(
                "sel.changed active=\(active) reporting=\(reporting) dragInTerm=\(self.dragStartedInTerminal)"
            )
        #endif
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
            let mm = "\(view.getTerminal().mouseMode)"
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
            // Do NOT restore allowMouseReporting here — leaving it false keeps
            // SwiftTerm from calling selectNone() on the next linefeed while
            // streaming continues. allowMouseReporting is restored in
            // handleMouseDown on the next click.
            return
        }

        if event.type == .leftMouseDragged {
            if dragStartedInTerminal && view.allowMouseReporting {
                #if TERMQ_DEBUG_BUILD
                    if TermQLogger.fileLoggingEnabled {
                        let mode = "\(view.getTerminal().mouseMode)"
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
        selectionScrollTargetRow = nil
    }

    private func autoScrollTimerFired() {
        guard let view, autoScrollDelta != 0 else { return }

        let currentYDisp = view.getTerminal().buffer.yDisp

        if autoScrollDelta < 0 {
            // Scrolling up into history. Accumulate the intended position from
            // the last known target (not from yDisp, which may have been reset
            // to yBase by a linefeed since the last timer fire).
            let currentEffective = selectionScrollTargetRow ?? currentYDisp
            let newTarget = max(currentEffective - abs(autoScrollDelta), 0)
            selectionScrollTargetRow = newTarget
            if currentYDisp > newTarget {
                view.scrollUp(lines: currentYDisp - newTarget)
            }
        } else {
            // Scrolling down toward live view — linefeeds help, no fight needed.
            selectionScrollTargetRow = nil
            view.scrollDown(lines: autoScrollDelta)
        }

        view.setNeedsDisplay(view.bounds)
    }
}
