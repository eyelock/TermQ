import AppKit
import SwiftTerm
import SwiftUI
import TermQCore

/// Custom terminal view - using default SwiftTerm behavior
/// Note: Copy/paste should work via Edit menu or right-click context menu
class TermQTerminalView: LocalProcessTerminalView {
    // Use SwiftTerm's built-in copy/paste - no customization needed
}

/// Container view that adds padding around the terminal and handles alternate scroll mode
class TerminalContainerView: NSView {
    let terminal: TermQTerminalView
    let padding: CGFloat = 12
    private var scrollEventMonitor: Any?

    init(terminal: TermQTerminalView) {
        self.terminal = terminal
        super.init(frame: .zero)

        // Set background color
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // Only add as subview if not already added
        if terminal.superview == nil {
            addSubview(terminal)
            terminal.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                terminal.topAnchor.constraint(equalTo: topAnchor, constant: padding),
                terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
                terminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
                terminal.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            ])
        }

        // Add local event monitor for scroll wheel to implement alternate scroll mode
        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            return self.handleScrollEvent(event)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = scrollEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Handle scroll events - implement alternate scroll mode
    /// When in alternate buffer (less, vim, git log), convert scroll to arrow keys
    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        // Only handle if the scroll is in our terminal view
        guard let eventWindow = event.window,
            eventWindow == self.window,
            let locationInWindow = event.window?.mouseLocationOutsideOfEventStream,
            let hitView = eventWindow.contentView?.hitTest(locationInWindow),
            hitView === terminal || hitView.isDescendant(of: terminal)
        else {
            return event  // Not our event, pass through
        }

        guard event.deltaY != 0 else { return event }

        // Check if terminal is in alternate buffer (fullscreen apps like less, vim)
        let term = terminal.getTerminal()
        if term.isCurrentBufferAlternate {
            // Send arrow key sequences instead of scrolling buffer
            let lines = calcScrollLines(delta: abs(event.deltaY))

            // Determine escape sequence based on application cursor mode
            let upSequence: String
            let downSequence: String
            if term.applicationCursor {
                upSequence = "\u{1b}OA"
                downSequence = "\u{1b}OB"
            } else {
                upSequence = "\u{1b}[A"
                downSequence = "\u{1b}[B"
            }

            let sequence = event.deltaY > 0 ? upSequence : downSequence
            for _ in 0..<lines {
                terminal.send(txt: sequence)
            }

            return nil  // Consume the event
        }

        // Normal buffer - let SwiftTerm handle it (scroll through history)
        return event
    }

    /// Calculate number of lines to scroll based on scroll wheel delta
    private func calcScrollLines(delta: CGFloat) -> Int {
        if delta > 9 {
            return 5
        } else if delta > 5 {
            return 3
        } else if delta > 1 {
            return 2
        }
        return 1
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Give focus to terminal when view appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.window?.makeFirstResponder(self.terminal)
        }
    }

    /// Re-focus the terminal
    func focusTerminal() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.window?.makeFirstResponder(self.terminal)
        }
    }
}

/// Wraps SwiftTerm's LocalProcessTerminalView for SwiftUI
/// Uses TerminalSessionManager to persist sessions across navigations
struct TerminalHostView: NSViewRepresentable {
    let card: TerminalCard
    let onExit: () -> Void

    func makeNSView(context: Context) -> TerminalContainerView {
        // Get or create session from the manager
        let container = TerminalSessionManager.shared.getOrCreateSession(for: card, onExit: onExit)
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        // Ensure terminal has focus when view updates
        nsView.focusTerminal()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        // Coordinator is now minimal since session management is handled by TerminalSessionManager
    }
}
