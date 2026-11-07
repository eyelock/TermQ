import AppKit
import SwiftUI

/// One menu item for pinning: "Keep on Stage", its pin filled when the seat
/// stays on the stage however many others are brought in. The pane's ✕ takes
/// it off.
struct WheelhouseKeepOnStageToggle: View {
    let cardId: UUID
    @ObservedObject private var stage: WheelhouseStage = .shared

    var body: some View {
        // A plain item with an icon, not a Toggle: a checked Toggle adds a
        // checkmark column that knocks every other icon in the menu out of line.
        let pinned = stage.isPinned(cardId)
        Button {
            if pinned { stage.unpin(cardId) } else { stage.pin(cardId) }
        } label: {
            Label(Strings.Wheelhouse.keepOnStage, systemImage: pinned ? "pin.fill" : "pin")
        }
    }
}

/// Watches mouse-downs so a click into a stage pane's terminal makes that pane
/// the focused one. The terminal takes the keyboard itself (AppKit); this
/// keeps the stage, and the selected card, in step with it.
@MainActor
final class StagePaneClickMonitor {
    /// `nonisolated(unsafe)` so `deinit` can remove it: the monitor is only
    /// ever touched on the main thread.
    nonisolated(unsafe) private var monitor: Any?

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func start(onClickInPane: @escaping @MainActor (UUID) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let window = event.window
            let hit = MainActor.assumeIsolated { Self.cardId(under: event) }
            // After AppKit has handled the click, whichever terminal holds the
            // keyboard is the truth; the hit-test is the fallback.
            // Only clicks that land in a terminal: a click on a chip or a
            // button must not refocus whichever terminal still has the keyboard.
            guard let hit else { return event }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    onClickInPane(Self.focusedCardId(in: window) ?? hit)
                }
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func cardId(under event: NSEvent) -> UUID? {
        guard let window = event.window, let contentView = window.contentView else { return nil }
        // hitTest takes a point in the receiver's superview's coordinates;
        // the hosting view is flipped, so its own coordinates would mirror y.
        let point = contentView.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        return terminalCardId(from: contentView.hitTest(point))
    }

    private static func focusedCardId(in window: NSWindow?) -> UUID? {
        terminalCardId(from: window?.firstResponder as? NSView)
    }

    private static func terminalCardId(from start: NSView?) -> UUID? {
        var view = start
        while let current = view {
            if let terminal = current as? TermQTerminalView { return terminal.cardId }
            view = current.superview
        }
        return nil
    }
}

/// The divider between two stage panes: a hairline with a wider grab area.
/// Reports each drag step as points moved right since the last step.
struct WheelhousePaneDivider: View {
    let width: CGFloat
    let onDrag: (CGFloat) -> Void
    let onReset: () -> Void

    @State private var lastTranslation: CGFloat = 0
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard inside != hovering else { return }
                        hovering = inside
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                onDrag(value.translation.width - lastTranslation)
                                lastTranslation = value.translation.width
                            }
                            .onEnded { _ in lastTranslation = 0 }
                    )
                    .onTapGesture(count: 2) { onReset() }
            }
            .onDisappear {
                if hovering { NSCursor.pop() }
            }
            .zIndex(1)
    }
}
