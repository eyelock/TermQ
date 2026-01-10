import AppKit
import SwiftTerm
import SwiftUI
import TermQCore
import UserNotifications

/// Custom terminal view - using default SwiftTerm behavior
/// Note: Copy/paste should work via Edit menu or right-click context menu
class TermQTerminalView: LocalProcessTerminalView {
    /// The card ID this terminal belongs to
    var cardId: UUID?

    /// Terminal title for notifications
    var terminalTitle: String = "Terminal"

    /// Callback when bell is received
    var onBell: (() -> Void)?

    /// Callback when terminal has output activity (throttled)
    var onActivity: (() -> Void)?

    /// Flash overlay for visual bell
    private var flashOverlay: NSView?

    /// Throttle activity callbacks to avoid excessive updates
    private var lastActivityCallback: Date = .distantPast

    /// Called when terminal view needs redrawing (indicates new content)
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)

        // Throttle activity callbacks to max once per 0.3 seconds
        let now = Date()
        if now.timeIntervalSince(lastActivityCallback) > 0.3 {
            lastActivityCallback = now
            onActivity?()
        }
    }

    /// Set up custom OSC handlers after the terminal is initialized
    func setupOscHandlers() {
        let terminal = getTerminal()

        // OSC 52 - Clipboard: ESC ] 52 ; c ; <base64> BEL
        // SwiftTerm already parses this, but we need to handle it via the terminal delegate
        // Since we can't override the delegate method, we'll register our own handler
        // Note: SwiftTerm's built-in OSC 52 handler calls clipboardCopy delegate,
        // but the delegate method isn't exposed for override. We register a replacement.
        terminal.registerOscHandler(code: 52) { [weak self] data in
            self?.handleClipboardOsc(data)
        }

        // OSC 777 - Notification: ESC ] 777 ; notify ; <title> ; <body> BEL
        terminal.registerOscHandler(code: 777) { [weak self] data in
            self?.handleNotificationOsc(data)
        }

        // OSC 9 - Windows Terminal notification: ESC ] 9 ; <message> BEL
        terminal.registerOscHandler(code: 9) { [weak self] data in
            self?.handleSimpleNotificationOsc(data)
        }
    }

    /// Called when the terminal receives a bell character (ASCII 7 / \a)
    override func bell(source: Terminal) {
        super.bell(source: source)
        onBell?()
        showVisualBell()
    }

    // MARK: - Smart Paste

    /// Override paste to warn about potentially dangerous content
    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }

        // Check for potentially dangerous content
        let warnings = analyzepasteContent(text)

        if warnings.isEmpty {
            // Safe to paste
            super.paste(sender)
        } else {
            // Show warning dialog
            showPasteWarning(text: text, warnings: warnings)
        }
    }

    /// Analyze paste content for potential dangers
    private func analyzepasteContent(_ text: String) -> [String] {
        var warnings: [String] = []

        // Check for multiline content
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if lines.count > 1 {
            warnings.append("Contains \(lines.count) lines - commands will execute automatically")
        }

        // Check for sudo
        if text.contains("sudo ") || text.hasPrefix("sudo") {
            warnings.append("Contains 'sudo' - will run with elevated privileges")
        }

        // Check for potentially destructive commands
        let destructivePatterns = [
            "rm -rf", "rm -fr", "mkfs", "dd if=", "> /dev/",
            ":(){:|:&};:", "chmod -R 777", "chmod 777",
        ]
        for pattern in destructivePatterns {
            if text.contains(pattern) {
                warnings.append("Contains potentially destructive command: \(pattern)")
                break
            }
        }

        // Check for curl/wget piped to shell (common attack vector)
        if (text.contains("curl ") || text.contains("wget "))
            && (text.contains("| bash") || text.contains("| sh") || text.contains("|bash") || text.contains("|sh"))
        {
            warnings.append("Downloads and executes remote script - verify source first")
        }

        // Check for environment variable manipulation
        if text.contains("export ") && (text.contains("PATH=") || text.contains("LD_")) {
            warnings.append("Modifies environment variables")
        }

        return warnings
    }

    /// Show warning dialog for paste
    private func showPasteWarning(text: String, warnings: [String]) {
        let alert = NSAlert()
        alert.messageText = "Paste Warning"
        alert.informativeText =
            """
            \(warnings.joined(separator: "\n"))

            Preview (first 200 chars):
            \(String(text.prefix(200)))\(text.count > 200 ? "..." : "")
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Paste Anyway")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // User confirmed - proceed with paste
            insertText(text, replacementRange: NSRange(location: 0, length: 0))
        }
    }

    // MARK: - OSC Handlers

    /// Handle OSC 52 clipboard command
    private func handleClipboardOsc(_ data: ArraySlice<UInt8>) {
        // Format: c;<base64-data> (c = clipboard target)
        guard data.count >= 2,
            data[data.startIndex] == UInt8(ascii: "c"),
            data[data.startIndex + 1] == UInt8(ascii: ";")
        else {
            return
        }

        let base64Data = Data(data[(data.startIndex + 2)...])
        guard let decoded = Data(base64Encoded: base64Data),
            let string = String(data: decoded, encoding: .utf8)
        else {
            return
        }

        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        }
    }

    /// Handle OSC 777 notification command
    private func handleNotificationOsc(_ data: ArraySlice<UInt8>) {
        // Format: notify;<title>;<body>
        guard let text = String(bytes: data, encoding: .utf8) else { return }

        let parts = text.components(separatedBy: ";")
        guard parts.count >= 3, parts[0] == "notify" else { return }

        let title = parts[1]
        let body = parts[2...].joined(separator: ";")

        DispatchQueue.main.async { [weak self] in
            self?.showDesktopNotification(title: title, body: body)
        }
    }

    /// Handle OSC 9 simple notification (Windows Terminal format)
    private func handleSimpleNotificationOsc(_ data: ArraySlice<UInt8>) {
        // Format: just the message text
        guard let message = String(bytes: data, encoding: .utf8) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.showDesktopNotification(title: self?.terminalTitle ?? "Terminal", body: message)
        }
    }

    // MARK: - Visual Bell

    private func showVisualBell() {
        guard flashOverlay == nil else { return }

        // Create a semi-transparent white overlay
        let overlay = NSView(frame: bounds)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        overlay.autoresizingMask = [.width, .height]

        addSubview(overlay)
        flashOverlay = overlay

        // Fade out and remove
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.15
                overlay.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                overlay.removeFromSuperview()
                self?.flashOverlay = nil
            })
    }

    // MARK: - Desktop Notifications

    private func showDesktopNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()

        // Request permission if needed
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = title.isEmpty ? self.terminalTitle : title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil  // Deliver immediately
            )

            center.add(request)
        }
    }
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
    var onBell: (() -> Void)?
    var onActivity: (() -> Void)?

    func makeNSView(context: Context) -> TerminalContainerView {
        // Get or create session from the manager
        let container = TerminalSessionManager.shared.getOrCreateSession(
            for: card,
            onExit: onExit,
            onBell: { onBell?() },
            onActivity: { onActivity?() }
        )
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
