import AppKit
import SwiftTerm
import SwiftUI
import TermQCore
import TermQShared
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

    /// Callback to launch a harness at a path resolved from the current terminal
    /// selection. Threaded down from `ContentView` because harness-launch card
    /// creation lives in `HarnessLaunchCoordinator`, which isn't a singleton.
    var onLaunchHarnessAtPath: ((String) -> Void)?

    /// Path resolved from the selection at the time the context menu was built —
    /// read by the path-action selectors below.
    private var pendingSelectionPath: ResolvedSelectionPath?

    /// Flash overlay for visual bell
    private var flashOverlay: NSView?

    /// Throttle activity callbacks to avoid excessive updates
    private var lastActivityCallback: Date = .distantPast

    /// Track when user last sent input (typing) - used to distinguish user input from process output
    private var lastUserInputTime: Date = .distantPast

    /// Event monitor for tracking key input
    private var keyInputMonitor: Any?

    /// Keeps the OSC observation (notifications, theme protection) alive for the
    /// view's lifetime. The token cancels itself when released.
    private var oscObservation: TerminalOscObservation?

    /// Theme most recently applied by `TerminalThemeManager`. Re-applied when a
    /// child process tries to override the colours through OSC 10/11/12.
    var appliedTheme: TerminalTheme?

    /// Drag-to-select controller — manages NSEvent monitors, allowMouseReporting
    /// toggle, and auto-scroll during selection. Created lazily so the `self`
    /// reference is valid.
    private lazy var dragController = TerminalSelectionDragController(view: self)

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
            cleanupAutoScrollDuringSelection()
            cleanupCopyOnSelect()
            cleanupKeyInputMonitor()
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
                if TermQLogger.fileLoggingEnabled {
                    TermQLogger.io.debug("keyDown allowMouseReporting=\(self.allowMouseReporting)")
                }
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
            if TermQLogger.fileLoggingEnabled {
                let sinceInput = Date().timeIntervalSince(lastUserInputTime)
                if sinceInput < 2.0 {
                    let sinceFmt = String(format: "%.2f", sinceInput)
                    TermQLogger.io.debug(
                        "setNeedsDisplay sinceUserInput=\(sinceFmt)s allowMouseReporting=\(self.allowMouseReporting)"
                    )
                }
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

    /// Observe the OSC sequences SwiftTerm does not surface through its delegate.
    ///
    /// SwiftTerm 2.x owns the parser, so TermQ no longer registers handlers that
    /// replace built-in behaviour. OSC 52 (clipboard) is gated in
    /// `TermQLinkDelegate.clipboardCopy`. OSC 10/11/12 colour *queries* are
    /// answered by SwiftTerm from the installed theme colours. What remains is
    /// passive observation: desktop notifications (OSC 777, OSC 9) and undoing
    /// colour *set* requests, see `handleColorOsc`.
    ///
    /// Events arrive on a private serial queue; every handler hops to the main
    /// actor before touching the view.
    func setupOscHandlers() {
        oscObservation = observeOscEvents { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleOscEvent(event)
            }
        }
    }

    private func handleOscEvent(_ event: TerminalOscEvent) {
        switch event.code {
        case 777:
            handleNotificationOsc(event.payload[...])
        case 9:
            handleSimpleNotificationOsc(event.payload[...])
        case 10, 11, 12:
            handleColorOsc(event.payload[...])
        default:
            break
        }
    }

    /// Re-applies the theme after a child process issued an OSC 10/11/12 *set*.
    ///
    /// Some CLIs (GitHub Copilot CLI emits one on startup) set the background
    /// colour and would otherwise override TermQ's theme for the rest of the
    /// session. Queries ("?") are answered by SwiftTerm and need nothing from
    /// us. SwiftTerm applies the requested colour on the main queue from the
    /// parse thread; the observation reaches us through one more queue hop, and
    /// the short delay guarantees the theme is re-applied after that, so the
    /// theme wins.
    private func handleColorOsc(_ data: ArraySlice<UInt8>) {
        guard data.first != UInt8(ascii: "?"), let theme = appliedTheme else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self else { return }
            TerminalSessionManager.shared.themeManager.applyTheme(to: self, theme: theme)
        }
    }

    /// Bell delivered by SwiftTerm through `TerminalViewDelegate`, see
    /// `TermQLinkDelegate.bell`. Audible beep (what SwiftTerm's default delegate
    /// does), card callback, visual flash.
    fileprivate func handleBell() {
        NSSound.beep()
        onBell?()
        showVisualBell()
    }

    // MARK: - Drag-to-Select (delegated to TerminalSelectionDragController)

    /// Install the drag-to-select event monitors. Called by `TerminalSessionManager`
    /// when a session is set up.
    func setupAutoScrollDuringSelection() {
        dragController.start()
    }

    /// Tear down the drag-to-select event monitors. Called on session teardown
    /// and from `deinit`.
    func cleanupAutoScrollDuringSelection() {
        dragController.stop()
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
        menu.addItem(
            NSMenuItem(
                title: "Copy without Line Breaks",
                action: #selector(copyWithoutLineBreaks(_:)),
                keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(
                title: "Copy without Indentation",
                action: #selector(copyWithoutIndentation(_:)),
                keyEquivalent: ""))

        menu.addItem(.separator())

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(pasteItem)

        if let resolved = resolvedSelectionPath() {
            pendingSelectionPath = resolved
            appendPathActionItems(to: menu, resolved: resolved)
        } else {
            pendingSelectionPath = nil
        }

        return menu
    }

    /// Resolve the current selection (if any) against the terminal's working
    /// directory into an existing filesystem path.
    private func resolvedSelectionPath() -> ResolvedSelectionPath? {
        guard selectionActive, let selection = getSelection(), !selection.isEmpty else { return nil }
        let cwd = cardId.flatMap { TerminalSessionManager.shared.getCurrentDirectory(for: $0) }
        return TerminalSelectionPathResolver.resolveOnDisk(selection: selection, cwd: cwd)
    }

    /// Append the Launch / Terminal / Open groups — mirrors the worktree sidebar's
    /// context menu (`WorktreeSidebarView.worktreeContextMenu`) but operating on a
    /// plain resolved path rather than a `GitWorktree`.
    private func appendPathActionItems(to menu: NSMenu, resolved: ResolvedSelectionPath) {
        menu.addItem(.separator())

        if let harnessName = YNHPersistence.shared.harness(for: resolved.directory) {
            menu.addItem(
                NSMenuItem(
                    title: Strings.Sidebar.launchHarness(harnessName),
                    action: #selector(launchHarnessAtSelection(_:)),
                    keyEquivalent: ""))
        }

        menu.addItem(
            NSMenuItem(
                title: Strings.Sidebar.newTerminal, action: #selector(quickTerminalAtSelection(_:)),
                keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(
                title: Strings.Sidebar.createTerminal, action: #selector(createTerminalAtSelection(_:)),
                keyEquivalent: ""))

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(
                title: Strings.Sidebar.revealInFinder, action: #selector(revealSelectionInFinder(_:)),
                keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(
                title: Strings.Sidebar.openInTerminal, action: #selector(openSelectionInTerminal(_:)),
                keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(
                title: Strings.Sidebar.copyPathname, action: #selector(copySelectionPathname(_:)),
                keyEquivalent: ""))

        let editors = EditorRegistry.shared.available
        if !editors.isEmpty {
            let openInItem = NSMenuItem(title: Strings.Sidebar.openIn, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for editor in editors {
                let item = NSMenuItem(
                    title: editor.displayName, action: #selector(openSelectionInEditor(_:)), keyEquivalent: "")
                item.representedObject = editor
                submenu.addItem(item)
            }
            openInItem.submenu = submenu
            menu.addItem(openInItem)
        }
    }

    @objc private func launchHarnessAtSelection(_ sender: Any) {
        guard let resolved = pendingSelectionPath else { return }
        onLaunchHarnessAtPath?(resolved.directory)
    }

    @objc private func quickTerminalAtSelection(_ sender: Any) {
        guard let resolved = pendingSelectionPath else { return }
        BoardViewModel.shared.newTerminal(at: resolved.directory)
    }

    @objc private func createTerminalAtSelection(_ sender: Any) {
        guard let resolved = pendingSelectionPath else { return }
        BoardViewModel.shared.addTerminal(workingDirectory: resolved.directory)
    }

    @objc private func revealSelectionInFinder(_ sender: Any) {
        guard let resolved = pendingSelectionPath else { return }
        PathActions.revealInFinder(path: resolved.directory)
    }

    @objc private func openSelectionInTerminal(_ sender: Any) {
        guard let resolved = pendingSelectionPath else { return }
        PathActions.openInTerminal(path: resolved.directory)
    }

    @objc private func copySelectionPathname(_ sender: Any) {
        guard let resolved = pendingSelectionPath else { return }
        PathActions.copyPathname(resolved.exactPath)
    }

    @objc private func openSelectionInEditor(_ sender: NSMenuItem) {
        guard let resolved = pendingSelectionPath, let editor = sender.representedObject as? ExternalEditor else {
            return
        }
        PathActions.openIn(editor: editor, path: resolved.exactPath)
    }

    /// SwiftTerm's implementation returns `false` for any selector it doesn't
    /// recognize, which would leave our custom menu items permanently disabled.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copyWithoutLineBreaks(_:)), #selector(copyWithoutIndentation(_:)):
            return selectionActive
        case #selector(launchHarnessAtSelection(_:)),
            #selector(quickTerminalAtSelection(_:)),
            #selector(createTerminalAtSelection(_:)),
            #selector(revealSelectionInFinder(_:)),
            #selector(openSelectionInTerminal(_:)),
            #selector(copySelectionPathname(_:)),
            #selector(openSelectionInEditor(_:)):
            return pendingSelectionPath != nil
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    /// Copy the selection as a single line — newlines collapsed to single spaces —
    /// so multi-line commands wrapped by a TUI can be pasted straight into a shell.
    @objc private func copyWithoutLineBreaks(_ sender: Any) {
        copyTransformingSelection(sender, with: TerminalSelectionFormatter.collapsingLineBreaks)
    }

    /// Copy the selection with the shared leading indentation removed but line
    /// breaks preserved — so a multi-line command a TUI rendered with a display
    /// indent (e.g. a quoted heredoc) pastes into a shell as literal, runnable text.
    @objc private func copyWithoutIndentation(_ sender: Any) {
        copyTransformingSelection(sender, with: TerminalSelectionFormatter.strippingIndentation)
    }

    /// Run the standard copy, then rewrite the pasteboard with `transform` applied
    /// to the copied text. `copy(_:)` writes the pasteboard synchronously today;
    /// the deferred read guards against SwiftTerm ever making it asynchronous
    /// (same pattern as `selectAll` above).
    private func copyTransformingSelection(_ sender: Any, with transform: @escaping (String) -> String) {
        guard selectionActive else { return }
        copy(sender)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transform(text), forType: .string)
        }
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
            // `pasteText` goes through SwiftTerm's paste path (bracketed paste,
            // control-byte filtering) rather than pretending the text was typed.
            switch decision {
            case .paste:
                pasteText(text)
            case .disableAndPaste:
                safePasteEnabled = false
                onDisableSafePaste?()
                pasteText(text)
            case .cancel:
                break
            }
        }
    }

    // MARK: - OSC Handlers

    /// Handle OSC 777 notification command
    private func handleNotificationOsc(_ data: ArraySlice<UInt8>) {
        // Format: notify;<title>;<body>
        guard let text = String(bytes: data, encoding: .utf8) else { return }

        let parts = text.components(separatedBy: ";")
        guard parts.count >= 3, parts[0] == "notify" else { return }

        let title = parts[1]
        let body = parts[2...].joined(separator: ";")
        showDesktopNotification(title: title, body: body)
    }

    /// Handle OSC 9 simple notification (Windows Terminal format)
    private func handleSimpleNotificationOsc(_ data: ArraySlice<UInt8>) {
        // Format: just the message text. "9;4;…" is the ConEmu progress-bar
        // sub-command, which SwiftTerm renders itself and which is not a
        // notification.
        guard let message = String(bytes: data, encoding: .utf8),
            !message.hasPrefix("4;")
        else { return }
        showDesktopNotification(title: terminalTitle, body: message)
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

// MARK: - Buffer Search

/// Thin wrappers over SwiftTerm's search API so SwiftUI views can drive terminal
/// search without importing SwiftTerm (its `Color` type collides with SwiftUI's).
extension TermQTerminalView {
    /// Select and scroll to the next match. Returns `true` if a match was found.
    @discardableResult
    func bufferSearchNext(_ term: String) -> Bool {
        findNext(term)
    }

    /// Select and scroll to the previous match. Returns `true` if a match was found.
    @discardableResult
    func bufferSearchPrevious(_ term: String) -> Bool {
        findPrevious(term)
    }

    /// 1-based index of the current match and total match count for `term`.
    func bufferSearchSummary(_ term: String) -> (index: Int, total: Int) {
        searchMatchSummary(term)
    }

    /// Clear search state and the match selection.
    func bufferSearchClear() {
        clearSearch()
    }
}

/// Full-proxy `TerminalViewDelegate` that intercepts `requestOpenLink`, `bell` and
/// `clipboardCopy`, and forwards every other method to `LocalProcessTerminalView`'s
/// own implementations.
///
/// `TerminalViewDelegate` is `@MainActor` in SwiftTerm 2.x: parsing happens on the
/// IO thread, and the view marshals these callbacks onto the main actor before
/// calling them.
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

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        let cwd = view?.cardId.flatMap { TerminalSessionManager.shared.getCurrentDirectory(for: $0) }
        TermQTerminalLink.open(link: link, cwd: cwd)
    }

    func bell(source: TerminalView) {
        view?.handleBell()
    }

    /// OSC 52 clipboard writes reach the pasteboard only when the user allowed
    /// it in Settings → Data & Security. The runtime gate reads through
    /// `SettingsStore.shared` so it matches what Settings displays. Reads
    /// (`clipboardRead`) are not forwarded, so SwiftTerm's default denies them.
    func clipboardCopy(source: TerminalView, content: Data) {
        guard SettingsStore.shared.allowOscClipboard else { return }
        view?.clipboardCopy(source: source, content: content)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        view?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }
    func setTerminalTitle(source: TerminalView, title: String) {
        view?.setTerminalTitle(source: source, title: title)
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        view?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        view?.send(source: source, data: data)
    }
    func scrolled(source: TerminalView, position: Double) {
        view?.scrolled(source: source, position: position)
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        view?.rangeChanged(source: source, startY: startY, endY: endY)
    }
}

/// Container view that adds padding around the terminal
class TerminalContainerView: NSView {
    private(set) var terminal: TermQTerminalView
    let padding: CGFloat = 12

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

        // Alternate Scroll Mode (wheel → cursor keys on the alternate screen) is
        // handled by SwiftTerm's scrollWheel: it honours DECSET/DECRST 1007, the
        // application-cursor variant, and mouse tracking, with line-accurate deltas.
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    var onLaunchHarnessAtPath: ((String) -> Void)?
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
        container.terminal.onLaunchHarnessAtPath = onLaunchHarnessAtPath
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        nsView.terminal.onLaunchHarnessAtPath = onLaunchHarnessAtPath

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
