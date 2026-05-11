import AppKit
import SwiftTerm
import SwiftUI
import TermQCore
@preconcurrency import UserNotifications

/// Custom terminal view - using default SwiftTerm behavior
/// Note: Copy/paste should work via Edit menu or right-click context menu
class TermQTerminalView: LocalProcessTerminalView {
    /// The card ID this terminal belongs to
    var cardId: UUID?

    /// Retains the proxy delegate installed in init. `terminalDelegate` is `weak`
    /// on `TerminalView`, so this strong reference keeps it alive.
    private var linkDelegate: TermQLinkDelegate?

    /// Terminal title for notifications
    var terminalTitle: String = "Terminal"

    /// Callback when bell is received
    var onBell: (() -> Void)?

    /// Callback when terminal has output activity (throttled)
    var onActivity: (() -> Void)?

    /// Whether safe paste warnings are enabled for this terminal
    var safePasteEnabled: Bool = true

    /// Callback when user wants to disable safe paste for this terminal
    var onDisableSafePaste: (() -> Void)?

    /// Flash overlay for visual bell
    private var flashOverlay: NSView?

    /// Throttle activity callbacks to avoid excessive updates
    private var lastActivityCallback: Date = .distantPast

    /// Track when user last sent input (typing) - used to distinguish user input from process output
    private var lastUserInputTime: Date = .distantPast

    /// Event monitor for tracking key input
    private var keyInputMonitor: Any?

    /// Timer for auto-scrolling during selection drag
    private var autoScrollTimer: Timer?

    /// Direction and speed of auto-scroll (-1 = up, 1 = down, magnitude = speed)
    private var autoScrollDelta: Int = 0

    /// Last known mouse position during drag (for extending selection after scroll)
    private var lastDragPosition: NSPoint?

    /// Target yDisp row for upward auto-scroll; nil when not active.
    /// Persists the intended viewport position across linefeed resets.
    private var selectionScrollTargetRow: Int?

    // MARK: - Init

    /// Install `TermQLinkDelegate` so link clicks route through `TermQTerminalLink.open`.
    ///
    /// SwiftTerm's `LocalProcessTerminalView.init` sets `terminalDelegate = self`. The
    /// `requestOpenLink` witness for that conformance was compiled into the SwiftTerm
    /// binary and maps to the protocol-extension default (`URL(string:)` + `NSWorkspace.open`
    /// → macOS "-50" dialog). Subclass overrides land in a separate vtable slot that the
    /// inherited witness never consults. SwiftTerm's own docs say: "If you must change the
    /// delegate make sure that you proxy the values." We follow that guidance here.
    override init(frame: CGRect) {
        super.init(frame: frame)
        installLinkDelegate()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installLinkDelegate()
    }

    private func installLinkDelegate() {
        let delegate = TermQLinkDelegate(view: self)
        linkDelegate = delegate
        terminalDelegate = delegate
    }

    deinit {
        // Use MainActor.assumeIsolated since deinit is nonisolated in Swift 6
        // but we're always deallocated on the main thread for NSView subclasses
        MainActor.assumeIsolated {
            autoScrollTimer?.invalidate()
            cleanupAutoScrollDuringSelection()
            cleanupCopyOnSelect()
            cleanupKeyInputMonitor()
        }
    }

    // MARK: - Size Change Fix

    /// Override to fix PTY size synchronization with Auto Layout.
    ///
    /// SwiftTerm's MacTerminalView handles PTY resizing in its `frame` property setter
    /// (which calls `processSizeChange`), but NOT in `setFrameSize`. When Auto Layout
    /// resolves constraints, it calls `setFrameSize` directly, bypassing the resize logic.
    ///
    /// This fix triggers the frame setter after size changes, ensuring the PTY gets
    /// the correct dimensions even when using Auto Layout constraints.
    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size

        // Call parent implementation first
        super.setFrameSize(newSize)

        // If size actually changed, trigger the frame property setter which
        // contains the resize logic (processSizeChange) that setFrameSize lacks.
        // The guard prevents infinite recursion: the frame setter will call
        // setFrameSize again, but then oldSize == newSize so we won't re-trigger.
        if oldSize != newSize {
            self.frame = NSRect(origin: frame.origin, size: newSize)
        }
    }

    /// Set up event monitor to track key input (to distinguish user typing from process output)
    func setupKeyInputMonitor() {
        cleanupKeyInputMonitor()

        keyInputMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check if the keystroke is going to our terminal
            guard let self = self,
                let window = event.window,
                window == self.window,
                window.firstResponder === self
            else { return event }

            self.lastUserInputTime = Date()
            #if TERMQ_DEBUG_BUILD
                TermQLogger.io.debug("keyDown allowMouseReporting=\(self.allowMouseReporting)")
            #endif

            // Intercept Cmd+C when a drag-selection is live (allowMouseReporting == false).
            // SwiftTerm's keyDown clears selection.active before calling copy: via interpretKeyEvents,
            // so a normal Cmd+C would copy an empty string. We call copy: here first, before keyDown
            // fires, then consume the event so keyDown never runs.
            let isCmdCOnly =
                event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
                && event.charactersIgnoringModifiers == "c"
            if isCmdCOnly && !self.allowMouseReporting {
                self.copy(self as Any)
                return nil
            }

            return event
        }
    }

    /// Clean up key input monitor
    func cleanupKeyInputMonitor() {
        if let monitor = keyInputMonitor {
            NSEvent.removeMonitor(monitor)
            keyInputMonitor = nil
        }
    }

    /// Called when terminal view needs redrawing (indicates new content)
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        #if TERMQ_DEBUG_BUILD
            let sinceInput = Date().timeIntervalSince(lastUserInputTime)
            if sinceInput < 2.0 {
                let sinceFmt = String(format: "%.2f", sinceInput)
                TermQLogger.io.debug(
                    "setNeedsDisplay sinceUserInput=\(sinceFmt)s allowMouseReporting=\(self.allowMouseReporting)"
                )
            }
        #endif
        super.setNeedsDisplay(invalidRect)

        // Only trigger activity if:
        // 1. Enough time since last callback (throttle)
        // 2. Enough time since user input (avoid spinner while typing)
        let now = Date()
        let timeSinceLastCallback = now.timeIntervalSince(lastActivityCallback)
        let timeSinceUserInput = now.timeIntervalSince(lastUserInputTime)

        // Only show spinner if it's been >0.5s since user typed (to catch command output after pressing enter)
        // AND the normal throttle interval has passed
        if timeSinceLastCallback > 0.3 && timeSinceUserInput > 0.5 {
            lastActivityCallback = now
            onActivity?()
        }
    }

    /// Set up custom OSC handlers after the terminal is initialized
    func setupOscHandlers() {
        let terminal = getTerminal()

        // OSC 52 - Clipboard: ESC ] 52 ; c ; <base64> BEL
        // Only register if user has allowed OSC 52 clipboard access.
        // The runtime gate now reads through `SettingsStore.shared` so it
        // matches what Settings → Data & Security displays. Previously
        // these two paths disagreed: the runtime defaulted to `true` on
        // unset, the Settings UI defaulted to `false`, so a never-touched
        // user saw "Off" in Settings while OSC 52 silently worked.
        if SettingsStore.shared.allowOscClipboard {
            terminal.registerOscHandler(code: 52) { [weak self] data in
                self?.handleClipboardOsc(data)
            }
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

    // MARK: - Auto-scroll During Selection

    /// Event monitor for mouse drag
    private var dragEventMonitor: Any?

    /// Event monitor for mouse down (to track drag origin)
    private var mouseDownMonitor: Any?

    /// Whether current drag started inside the terminal
    private var dragStartedInTerminal: Bool = false

    /// Set up auto-scroll during selection
    func setupAutoScrollDuringSelection() {
        cleanupAutoScrollDuringSelection()

        // Monitor for mouse down to track where drag starts
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseDownForAutoScroll(event)
            return event
        }

        // Monitor for mouse dragged events
        dragEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) {
            [weak self] event in
            self?.handleMouseEventForAutoScroll(event)
            return event
        }
    }

    /// Clean up auto-scroll event monitor
    func cleanupAutoScrollDuringSelection() {
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
        // Clear global drag flag in case terminal is destroyed during selection
        TerminalSessionManager.shared.isMouseDragInProgress = false
    }

    /// Handle mouse down to track if drag starts in terminal
    private func handleMouseDownForAutoScroll(_ event: NSEvent) {
        // Check if mouse down is in our terminal view
        guard let eventWindow = event.window,
            eventWindow == self.window
        else {
            dragStartedInTerminal = false
            return
        }

        // Restore mouse reporting so clicks are forwarded to the running app (e.g. Claude Code TUI).
        // This was disabled during a drag-to-select to prevent SwiftTerm from intercepting drags.
        allowMouseReporting = true

        let localPoint = convert(event.locationInWindow, from: nil)
        dragStartedInTerminal = bounds.contains(localPoint)

        // Set global drag flag to prevent focus stealing during selection
        if dragStartedInTerminal {
            TerminalSessionManager.shared.isMouseDragInProgress = true
        }
    }

    /// Handle mouse events for auto-scroll during selection
    private func handleMouseEventForAutoScroll(_ event: NSEvent) {
        // Check if event is in our window
        guard let eventWindow = event.window,
            eventWindow == self.window
        else { return }

        if event.type == .leftMouseUp {
            stopAutoScrollTimer()
            lastDragPosition = nil
            dragStartedInTerminal = false
            TerminalSessionManager.shared.isMouseDragInProgress = false
            // Do NOT restore allowMouseReporting here — leaving it false keeps SwiftTerm from
            // calling selectNone() on the next linefeed while streaming continues.
            // allowMouseReporting is restored in handleMouseDownForAutoScroll on the next click.
            return
        }

        if event.type == .leftMouseDragged {
            if dragStartedInTerminal && allowMouseReporting {
                allowMouseReporting = false
            }
        }

        // Only process drag if it started inside the terminal (not toolbar/titlebar)
        guard dragStartedInTerminal else { return }

        // It's a drag event
        lastDragPosition = event.locationInWindow

        // Calculate if mouse is above or below the visible area
        let localPoint = convert(event.locationInWindow, from: nil)

        // Only process if drag originated in our view (check if within x bounds)
        guard localPoint.x >= 0, localPoint.x <= bounds.width else {
            stopAutoScrollTimer()
            return
        }

        let viewHeight = bounds.height
        autoScrollDelta = 0

        if localPoint.y > viewHeight {
            // Mouse is above the view (NSView y=0 is at bottom)
            // We want to scroll up (show earlier content in history)
            let overshoot = localPoint.y - viewHeight
            autoScrollDelta = -calcScrollSpeed(overshoot: overshoot)
        } else if localPoint.y < 0 {
            // Mouse is below the view
            // We want to scroll down (show later content)
            let overshoot = -localPoint.y
            autoScrollDelta = calcScrollSpeed(overshoot: overshoot)
        }

        // Start or stop timer based on whether we need to scroll
        if autoScrollDelta != 0 {
            startAutoScrollTimer()
        } else {
            stopAutoScrollTimer()
        }
    }

    /// Calculate scroll speed based on how far outside the view the mouse is
    private func calcScrollSpeed(overshoot: CGFloat) -> Int {
        if overshoot > 100 {
            return 5
        } else if overshoot > 50 {
            return 3
        } else if overshoot > 20 {
            return 2
        }
        return 1
    }

    /// Start the auto-scroll timer if not already running
    private func startAutoScrollTimer() {
        guard autoScrollTimer == nil else { return }

        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            // Timer callbacks run on main thread but need MainActor annotation for Swift 6
            MainActor.assumeIsolated {
                self?.autoScrollTimerFired()
            }
        }
    }

    /// Stop the auto-scroll timer
    private func stopAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollDelta = 0
        selectionScrollTargetRow = nil
    }

    /// Called when auto-scroll timer fires
    private func autoScrollTimerFired() {
        guard autoScrollDelta != 0 else { return }

        let currentYDisp = getTerminal().buffer.yDisp

        if autoScrollDelta < 0 {
            // Scrolling up into history.
            // Accumulate the intended position from the last known target (not from yDisp,
            // which may have been reset to yBase by a linefeed since the last timer fire).
            let currentEffective = selectionScrollTargetRow ?? currentYDisp
            let newTarget = max(currentEffective - abs(autoScrollDelta), 0)
            selectionScrollTargetRow = newTarget
            if currentYDisp > newTarget {
                scrollUp(lines: currentYDisp - newTarget)
            }
        } else {
            // Scrolling down toward live view. No need to fight linefeeds — they help.
            selectionScrollTargetRow = nil
            scrollDown(lines: autoScrollDelta)
        }

        setNeedsDisplay(bounds)
    }

    /// Called by SwiftTerm when the terminal engine resets yDisp (e.g. on each linefeed).
    /// Re-applies our scroll target so upward auto-scroll is not undone by streaming output.
    override func scrolled(source: Terminal, yDisp: Int) {
        super.scrolled(source: source, yDisp: yDisp)
        guard let targetRow = selectionScrollTargetRow, yDisp > targetRow else { return }
        scrollUp(lines: yDisp - targetRow)
    }

    /// Override linefeed to avoid flickering the selection on each new output line.
    /// Position re-apply is handled in scrolled() which fires before linefeed().
    override func linefeed(source: Terminal) {
        // Only delegate to super (which calls selectNone()) when not in a drag-to-select.
        // During a drag, clearing the selection on each linefeed causes visible flicker —
        // the drag monitor re-extends it on the next event anyway.
        if allowMouseReporting {
            super.linefeed(source: source)
        }
    }

    // MARK: - Copy on Select

    /// Event monitor for copy-on-select feature
    private var copyOnSelectMonitor: Any?

    /// Set up copy-on-select event monitor
    func setupCopyOnSelect() {
        // Remove existing monitor if any
        if let monitor = copyOnSelectMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Add local event monitor for mouse up
        copyOnSelectMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUpForCopyOnSelect(event)
            return event
        }
    }

    /// Clean up copy-on-select monitor
    func cleanupCopyOnSelect() {
        if let monitor = copyOnSelectMonitor {
            NSEvent.removeMonitor(monitor)
            copyOnSelectMonitor = nil
        }
    }

    /// Handle mouse up for copy-on-select
    private func handleMouseUpForCopyOnSelect(_ event: NSEvent) {
        // Check if copy-on-select is enabled
        let copyOnSelect = SettingsStore.shared.copyOnSelect
        guard copyOnSelect else { return }

        // Check if the mouse up was in our view
        guard let eventWindow = event.window,
            eventWindow == self.window,
            let locationInWindow = event.window?.mouseLocationOutsideOfEventStream,
            let hitView = eventWindow.contentView?.hitTest(locationInWindow),
            hitView === self || hitView.isDescendant(of: self)
        else { return }

        // Small delay to let selection finalize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            // Use the public copy method which handles selection internally
            guard let self = self else { return }
            self.copy(self)
        }
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: ""))

        menu.addItem(.separator())

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(pasteItem)

        return menu
    }

    // MARK: - Smart Paste

    /// Override paste to warn about potentially dangerous content
    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }

        // Skip check if safe paste is disabled for this terminal
        guard safePasteEnabled else {
            super.paste(sender)
            return
        }

        // Check for potentially dangerous content using SafePasteAnalyzer
        let warnings = SafePasteAnalyzer.analyze(text)

        if warnings.isEmpty {
            // Safe to paste
            super.paste(sender)
        } else {
            // Show warning dialog
            let decision = SafePasteAnalyzer.showWarningDialog(text: text, warnings: warnings)
            switch decision {
            case .paste:
                insertText(text, replacementRange: NSRange(location: 0, length: 0))
            case .disableAndPaste:
                safePasteEnabled = false
                onDisableSafePaste?()
                insertText(text, replacementRange: NSRange(location: 0, length: 0))
            case .cancel:
                break
            }
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
                // Schedule cleanup on main actor
                Task { @MainActor in
                    overlay.removeFromSuperview()
                    self?.flashOverlay = nil
                }
            })
    }

    // MARK: - Desktop Notifications

    private func showDesktopNotification(title: String, body: String) {
        // Capture MainActor-isolated property before async work
        let notificationTitle = title.isEmpty ? terminalTitle : title

        Task {
            let center = UNUserNotificationCenter.current()

            // Request permission if needed
            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            guard granted == true else { return }

            let content = UNMutableNotificationContent()
            content.title = notificationTitle
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil  // Deliver immediately
            )

            try? await center.add(request)
        }
    }
}

/// Full-proxy `TerminalViewDelegate` that intercepts `requestOpenLink` and forwards
/// every other method to `LocalProcessTerminalView`'s own implementations.
///
/// `TerminalViewDelegate` isn't annotated `@MainActor`, but SwiftTerm only ever calls
/// it from `TerminalView` (NSView → `@MainActor`). The class is marked `@MainActor`
/// to reflect that reality; each protocol method is `nonisolated` to satisfy the
/// conformance and uses `assumeIsolated` to re-enter the main actor for forwarded calls.
///
/// Per SwiftTerm's docs: "If you must change the delegate make sure that you proxy
/// the values in your implementation to the values set after initializing this instance."
///
/// See `TerminalLinkRoutingTests` for the static guardrail that catches any future
/// `requestOpenLink` definition that doesn't route through `TermQTerminalLink.open`.
@MainActor
private final class TermQLinkDelegate: TerminalViewDelegate {
    private weak var view: TermQTerminalView?

    init(view: TermQTerminalView) { self.view = view }

    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        MainActor.assumeIsolated {
            let cwd = view?.cardId.flatMap { TerminalSessionManager.shared.getCurrentDirectory(for: $0) }
            TermQTerminalLink.open(link: link, cwd: cwd)
        }
    }

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        MainActor.assumeIsolated { view?.sizeChanged(source: source, newCols: newCols, newRows: newRows) }
    }
    nonisolated func setTerminalTitle(source: TerminalView, title: String) {
        MainActor.assumeIsolated { view?.setTerminalTitle(source: source, title: title) }
    }
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        MainActor.assumeIsolated { view?.hostCurrentDirectoryUpdate(source: source, directory: directory) }
    }
    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        MainActor.assumeIsolated { view?.send(source: source, data: data) }
    }
    nonisolated func scrolled(source: TerminalView, position: Double) {
        MainActor.assumeIsolated { view?.scrolled(source: source, position: position) }
    }
    nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        MainActor.assumeIsolated { view?.clipboardCopy(source: source, content: content) }
    }
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        MainActor.assumeIsolated { view?.rangeChanged(source: source, startY: startY, endY: endY) }
    }
}

/// Container view that adds padding around the terminal and handles alternate scroll mode
class TerminalContainerView: NSView {
    private(set) var terminal: TermQTerminalView
    let padding: CGFloat = 12
    private var scrollEventMonitor: Any?

    init(terminal: TermQTerminalView) {
        self.terminal = terminal
        super.init(frame: .zero)

        // Set background color from current theme
        wantsLayer = true
        let theme = TerminalSessionManager.shared.currentTheme
        layer?.backgroundColor = theme.background.cgColor

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
        // Use MainActor.assumeIsolated since deinit is nonisolated in Swift 6
        // but we're always deallocated on the main thread for NSView subclasses
        MainActor.assumeIsolated {
            if let monitor = scrollEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
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
        // Only convert scroll → arrow keys when:
        //   1. alternate buffer is active (vim, less, etc.)
        //   2. application cursor mode is set (the app requested arrow key sequences)
        //   3. mouse mode is off (app has NOT enabled its own mouse tracking)
        // If the app has enabled mouse tracking (e.g. Claude Code), let SwiftTerm pass the
        // scroll as a proper mouse event sequence — never inject extra arrow keys.
        if term.isCurrentBufferAlternate && term.applicationCursor && term.mouseMode == .off {
            let lines = calcScrollLines(delta: abs(event.deltaY))
            let sequence = event.deltaY > 0 ? "\u{1b}OA" : "\u{1b}OB"
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.window?.makeFirstResponder(self.terminal)
        }
    }

    /// Re-focus the terminal
    func focusTerminal() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard NSEvent.pressedMouseButtons == 0 else { return }
            guard !TerminalSessionManager.shared.isMouseDragInProgress else { return }
            self.window?.makeFirstResponder(self.terminal)
        }
    }

    /// Replace the current terminal with a new one (for restart scenarios)
    func replaceTerminal(with newTerminal: TermQTerminalView) {
        // Remove old terminal
        terminal.removeFromSuperview()

        // Update property
        terminal = newTerminal

        // Add new terminal with same constraints
        addSubview(newTerminal)
        newTerminal.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            newTerminal.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            newTerminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            newTerminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            newTerminal.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
        ])

        // Focus the new terminal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.window?.makeFirstResponder(newTerminal)
        }
    }
}

/// Wraps SwiftTerm's LocalProcessTerminalView for SwiftUI
/// Uses TerminalSessionManager to persist sessions across navigations
struct TerminalHostView: NSViewRepresentable {
    let card: TerminalCard
    let onExit: @Sendable @MainActor () -> Void
    var onBell: (() -> Void)?
    var onActivity: (() -> Void)?
    var isSearching: Bool = false
    /// Token that changes when session should be restarted - forces view recreation
    var restartToken: Int = 0

    func makeNSView(context: Context) -> TerminalContainerView {
        // Get or create session from the manager
        // The restartToken ensures this is called fresh after a restart
        let container = TerminalSessionManager.shared.getOrCreateSession(
            for: card,
            onExit: onExit,
            onBell: { onBell?() },
            onActivity: { onActivity?() }
        )
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        let mouseDown = NSEvent.pressedMouseButtons != 0
        let dragInProgress = TerminalSessionManager.shared.isMouseDragInProgress
        let alreadyFocused = nsView.window?.firstResponder === nsView.terminal
        if !isSearching && !dragInProgress && !mouseDown && !alreadyFocused {
            nsView.focusTerminal()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        // Coordinator is now minimal since session management is handled by TerminalSessionManager
    }
}
