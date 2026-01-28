import AppKit
import Foundation
import SwiftTerm
import TermQCore

/// Manages persistent terminal sessions across view navigations
@MainActor
class TerminalSessionManager: ObservableObject {
    static let shared = TerminalSessionManager()

    // MARK: - Theme Management (delegated)

    let themeManager = TerminalThemeManager()

    /// Reference to the tmux manager for tmux-backed sessions
    let tmuxManager = TmuxManager.shared

    /// Current theme ID - proxied to theme manager
    var themeId: String {
        get { themeManager.themeId }
        set { themeManager.themeId = newValue }
    }

    /// Current theme - proxied to theme manager
    var currentTheme: TerminalTheme {
        themeManager.currentTheme
    }

    // MARK: - Bell Handling

    /// Centralized bell handler - called when ANY terminal receives a bell
    /// This ensures bells work even when terminals are running in background
    var onBellForCard: ((UUID) -> Void)?

    // MARK: - Selection Protection

    /// Flag to prevent focus stealing during mouse drag/selection operations
    /// Set by terminal views during drag, checked before any focus changes
    var isMouseDragInProgress: Bool = false

    // MARK: - Session Storage

    /// Active terminal sessions keyed by card ID
    internal var sessions: [UUID: TerminalSession] = [:]

    /// Per-pane terminal emulators for tmux sessions (cardId -> paneId -> TermQTerminalView)
    internal var paneTerminals: [UUID: [String: TermQTerminalView]] = [:]

    struct TerminalSession {
        let terminal: TermQTerminalView
        let container: TerminalContainerView
        let backend: TerminalBackend
        var isRunning: Bool = true
        var currentDirectory: String?
        var lastActivityTime: Date = Date()
        var pendingRestart: Bool = false
        var controlModeSession: TmuxControlModeSession?  // Control mode for tmux panes
        var activePaneId: String?  // Currently active pane ID for input routing
    }

    private init() {
        // Set up theme change callback
        themeManager.onThemeChanged = { [weak self] in
            self?.applyThemeToAllSessions()
        }
    }

    /// Determine the effective backend for a card (handles fallback if tmux unavailable)
    func effectiveBackend(for card: TerminalCard) -> TerminalBackend {
        switch card.backend {
        case .direct:
            return .direct
        case .tmuxAttach, .tmuxControl:
            // Fall back to direct if tmux is not available
            return tmuxManager.isAvailable ? card.backend : .direct
        }
    }

    /// Get or create a terminal session for a card
    func getOrCreateSession(
        for card: TerminalCard,
        onExit: @escaping @Sendable @MainActor () -> Void,
        onBell: @escaping () -> Void,
        onActivity: @escaping () -> Void
    ) -> TerminalContainerView {
        let cardId = card.id

        // Check for pending restart - clean up old session before creating new
        if let session = sessions[cardId], session.pendingRestart {
            // Disconnect control mode if exists
            if let controlSession = session.controlModeSession {
                controlSession.disconnect()
            }
            // Clean up pane terminals
            paneTerminals.removeValue(forKey: cardId)
            // Clean up event monitors
            session.terminal.cleanupAutoScrollDuringSelection()
            session.terminal.cleanupCopyOnSelect()
            session.terminal.cleanupKeyInputMonitor()
            // Terminate the old process
            if session.isRunning {
                switch session.backend {
                case .direct:
                    session.terminal.send(txt: "exit\n")
                case .tmuxAttach, .tmuxControl:
                    let sessionName = tmuxManager.sessionName(for: cardId)
                    Task {
                        try? await tmuxManager.killSession(name: sessionName)
                    }
                }
            }
            // Remove from dictionary so new session can be created
            sessions.removeValue(forKey: cardId)
        }

        // Return existing session if available
        if let session = sessions[cardId], session.isRunning {
            // Update activity callback (views may be recreated)
            session.terminal.onActivity = { [weak self] in
                self?.updateActivityTime(cardId: cardId)
                onActivity()
            }
            // Bell uses centralized handler - no need to update
            // Re-focus the terminal (but not during mouse drag to protect selection)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard self?.isMouseDragInProgress != true else { return }
                session.container.window?.makeFirstResponder(session.terminal)
            }
            return session.container
        }

        // Determine effective backend (with fallback)
        let backend = effectiveBackend(for: card)

        // Create new terminal (using our subclass that fixes copy/paste)
        let terminal = TermQTerminalView(frame: .zero)
        terminal.cardId = cardId
        terminal.terminalTitle = card.title
        terminal.safePasteEnabled = card.safePasteEnabled
        terminal.onDisableSafePaste = {
            // Persist the change to the card model
            card.safePasteEnabled = false
        }
        // Use centralized bell handler to ensure bells work even for background terminals
        terminal.onBell = { [weak self] in
            self?.onBellForCard?(cardId)
            onBell()  // Also call view-specific callback for immediate visual feedback
        }
        terminal.onActivity = { [weak self] in
            self?.updateActivityTime(cardId: cardId)
            onActivity()
        }

        // Configure terminal appearance with custom font if specified
        let terminalFont: NSFont
        let size = card.fontSize > 0 ? card.fontSize : 13
        if !card.fontName.isEmpty, let customFont = NSFont(name: card.fontName, size: size) {
            terminalFont = customFont
        } else {
            terminalFont = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        terminal.font = terminalFont

        // Apply theme (per-terminal or global default)
        let theme = themeManager.theme(for: card.themeId)
        themeManager.applyTheme(to: terminal, theme: theme)

        // Set up OSC handlers for clipboard, notifications, etc.
        terminal.setupOscHandlers()

        // Set up copy-on-select event monitor
        terminal.setupCopyOnSelect()

        // Set up auto-scroll during selection drag
        terminal.setupAutoScrollDuringSelection()

        // Set up key input monitor to track user typing (for spinner logic)
        terminal.setupKeyInputMonitor()

        // Get current environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = Constants.Terminal.termType
        env["COLORTERM"] = Constants.Terminal.colorTerm
        env["LANG"] = env["LANG"] ?? Constants.Terminal.defaultLang

        // Add TermQ-specific environment variables
        env["TERMQ_TERMINAL_ID"] = card.id.uuidString
        env["TERMQ_BACKEND"] = backend.rawValue

        // Add tag environment variables (TERMQ_TERMINAL_TAG_<KEY>=value)
        for tag in card.tags {
            let sanitizedKey = sanitizeEnvVarName(tag.key)
            if !sanitizedKey.isEmpty {
                env["TERMQ_TERMINAL_TAG_\(sanitizedKey)"] = tag.value
            }
        }

        // Add user-defined environment variables (global + terminal, no prefix)
        let userEnvVars = buildUserEnvironmentVariables(card)
        for (key, value) in userEnvVars {
            env[key] = value
        }

        // Start the terminal process based on backend
        switch backend {
        case .direct:
            startDirectProcess(terminal: terminal, card: card, environment: env)

        case .tmuxAttach:
            startTmuxAttachProcess(terminal: terminal, card: card, environment: env)

        case .tmuxControl:
            startTmuxControlProcess(terminal: terminal, card: card, environment: env)
        }

        // Create container with padding
        let container = TerminalContainerView(terminal: terminal)

        // Set up exit handler
        let delegate = SessionDelegate(cardId: card.id, manager: self, onExit: onExit)
        terminal.processDelegate = delegate

        // Store the delegate to prevent deallocation
        objc_setAssociatedObject(terminal, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

        // Store session with backend info
        sessions[card.id] = TerminalSession(
            terminal: terminal,
            container: container,
            backend: backend
        )

        // Run init command if specified (after a short delay to let shell initialize)
        runInitCommand(terminal: terminal, card: card)

        return container
    }

    // MARK: - Process Startup Methods

    /// Start a direct shell process
    internal func startDirectProcess(
        terminal: TermQTerminalView,
        card: TerminalCard,
        environment env: [String: String]
    ) {
        // Start shell in the correct working directory using exec
        // This avoids the visible "cd" command flash by:
        // 1. Starting command shell (non-interactive)
        // 2. cd to the working directory
        // 3. exec the user's shell as a login shell (replaces the process)
        let startCommand = "cd \(escapeShellArg(card.workingDirectory)) && exec \(escapeShellArg(card.shellPath)) -l"
        terminal.startProcess(
            executable: Constants.Shell.commandShell,
            args: ["-c", startCommand],
            environment: Array(env.map { "\($0.key)=\($0.value)" }),
            execName: nil
        )
    }

    /// Start a tmux-backed session with regular attach (persistent mode without pane features)
    private func startTmuxAttachProcess(
        terminal: TermQTerminalView,
        card: TerminalCard,
        environment env: [String: String]
    ) {
        let sessionName = card.tmuxSessionName

        // Build tmux environment args for the new session
        var tmuxEnvArgs: [String] = []
        for (key, value) in env {
            // Skip some vars that tmux handles itself
            if key == "TERM" || key == "COLORTERM" { continue }
            tmuxEnvArgs.append("-e")
            tmuxEnvArgs.append("\(key)=\(value)")
        }

        guard let tmuxPath = tmuxManager.tmuxPath else {
            // Fallback to direct if somehow tmux disappeared
            startDirectProcess(terminal: terminal, card: card, environment: env)
            return
        }

        // Create and attach to tmux session (traditional mode)
        let script = """
            # Create session if it doesn't exist
            if ! \(escapeShellArg(tmuxPath)) has-session -t \(escapeShellArg(sessionName)) 2>/dev/null; then
                \(escapeShellArg(tmuxPath)) new-session -d -s \(escapeShellArg(sessionName)) -c \(escapeShellArg(card.workingDirectory)) \(tmuxEnvArgs.map { escapeShellArg($0) }.joined(separator: " ")) \(escapeShellArg(card.shellPath)) -l
            fi
            # Configure session for TermQ
            \(escapeShellArg(tmuxPath)) set-option -t \(escapeShellArg(sessionName)) status off 2>/dev/null || true
            \(escapeShellArg(tmuxPath)) set-option -t \(escapeShellArg(sessionName)) mouse on 2>/dev/null || true
            \(escapeShellArg(tmuxPath)) set-option -t \(escapeShellArg(sessionName)) default-terminal 'xterm-256color' 2>/dev/null || true
            \(escapeShellArg(tmuxPath)) set-option -t \(escapeShellArg(sessionName)) escape-time 10 2>/dev/null || true
            \(escapeShellArg(tmuxPath)) set-option -t \(escapeShellArg(sessionName)) allow-passthrough off 2>/dev/null || true
            # Attach to the session
            exec \(escapeShellArg(tmuxPath)) attach-session -t \(escapeShellArg(sessionName))
            """

        terminal.startProcess(
            executable: "/bin/sh",
            args: ["-c", script],
            environment: Array(env.map { "\($0.key)=\($0.value)" }),
            execName: nil
        )

        // Sync metadata to tmux session
        Task {
            let metadata = TerminalCardMetadata.from(card)
            await tmuxManager.syncMetadataToSession(sessionName: sessionName, card: metadata)
        }
    }

    // MARK: - Metadata Sync

    /// Sync card metadata to its tmux session (call when card is updated)
    func syncMetadataToTmuxSession(card: TerminalCard) {
        guard effectiveBackend(for: card) == .tmuxAttach else { return }

        let sessionName = card.tmuxSessionName
        Task {
            let metadata = TerminalCardMetadata.from(card)
            await tmuxManager.syncMetadataToSession(sessionName: sessionName, card: metadata)
        }
    }

    /// Update specific metadata fields in the tmux session
    func updateTmuxSessionMetadata(
        cardId: UUID,
        title: String? = nil,
        description: String? = nil,
        tags: [Tag]? = nil,
        llmPrompt: String? = nil,
        llmNextAction: String? = nil,
        badge: String? = nil,
        columnId: UUID? = nil,
        isFavourite: Bool? = nil
    ) {
        guard let session = sessions[cardId], session.backend == .tmuxAttach else { return }

        let sessionName = tmuxManager.sessionName(for: cardId)
        Task {
            await tmuxManager.updateSessionMetadata(
                sessionName: sessionName,
                title: title,
                description: description,
                tags: tags,
                llmPrompt: llmPrompt,
                llmNextAction: llmNextAction,
                badge: badge,
                columnId: columnId,
                isFavourite: isFavourite
            )
        }
    }

    /// Run init command after shell starts (supports token replacement)
    private func runInitCommand(terminal: TermQTerminalView, card: TerminalCard) {
        guard !card.initCommand.isEmpty else { return }

        let hasNextActionToken = card.initCommand.contains("{{LLM_NEXT_ACTION}}")
        let hadNextAction = !card.llmNextAction.isEmpty

        // Check if autorun is enabled (global AND per-terminal)
        let globalAutorunEnabled = UserDefaults.standard.bool(forKey: "enableTerminalAutorun")
        let autorunAllowed = globalAutorunEnabled && card.allowAutorun

        // Perform token replacement based on autorun settings
        var initCmd = card.initCommand

        if autorunAllowed {
            // Inject LLM values with escaping for double-quote context
            // Note: Values are escaped to prevent shell injection while allowing variable expansion
            // Templates should include quotes: claude "{{LLM_PROMPT}} {{LLM_NEXT_ACTION}}"
            let escapedPrompt = escapeForDoubleQuotes(card.llmPrompt)
            let escapedNextAction = escapeForDoubleQuotes(card.llmNextAction)

            initCmd = initCmd.replacingOccurrences(of: "{{LLM_PROMPT}}", with: escapedPrompt)
            initCmd = initCmd.replacingOccurrences(of: "{{LLM_NEXT_ACTION}}", with: escapedNextAction)

            // Clear llmNextAction after use (if token was present and had a value)
            if hasNextActionToken && hadNextAction {
                card.llmNextAction = ""
                BoardViewModel.shared.updateCard(card)
            }
        } else {
            // Replace both tokens with empty string (don't inject anything)
            initCmd = initCmd.replacingOccurrences(of: "{{LLM_PROMPT}}", with: "")
            initCmd = initCmd.replacingOccurrences(of: "{{LLM_NEXT_ACTION}}", with: "")
        }

        // Slightly longer delay for tmux sessions (they take a moment to attach)
        let delay = effectiveBackend(for: card) == .tmuxAttach ? 0.8 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            terminal.send(txt: initCmd + "\n")
        }
    }

    /// Check if a session exists and is running
    func hasActiveSession(for cardId: UUID) -> Bool {
        return sessions[cardId]?.isRunning ?? false
    }

    /// Check if a session exists at all (regardless of running state)
    func sessionExists(for cardId: UUID) -> Bool {
        return sessions[cardId] != nil
    }

    /// Check if a session has a pending restart
    func hasPendingRestart(for cardId: UUID) -> Bool {
        return sessions[cardId]?.pendingRestart ?? false
    }

    /// Mark a session as terminated
    func markSessionTerminated(cardId: UUID) {
        sessions[cardId]?.isRunning = false
    }

    /// Update the current directory for a session
    func updateCurrentDirectory(cardId: UUID, directory: String?) {
        sessions[cardId]?.currentDirectory = directory
    }

    /// Get the current directory for a session (falls back to nil if not tracked)
    func getCurrentDirectory(for cardId: UUID) -> String? {
        return sessions[cardId]?.currentDirectory
    }

    /// Get the terminal view for a session (for searching, etc.)
    func getTerminalView(for cardId: UUID) -> TermQTerminalView? {
        return sessions[cardId]?.terminal
    }

    /// Update the last activity time for a session
    func updateActivityTime(cardId: UUID) {
        sessions[cardId]?.lastActivityTime = Date()
    }

    /// Check if a session has had recent activity (is "processing")
    /// Returns true if activity within the last `threshold` seconds
    func isProcessing(cardId: UUID, threshold: TimeInterval = Constants.Activity.processingThreshold) -> Bool {
        guard let session = sessions[cardId], session.isRunning else { return false }
        return Date().timeIntervalSince(session.lastActivityTime) < threshold
    }

    /// Get all card IDs that are currently processing
    func processingCardIds(threshold: TimeInterval = Constants.Activity.processingThreshold) -> Set<UUID> {
        let now = Date()
        return Set(
            sessions.filter { _, session in
                session.isRunning && now.timeIntervalSince(session.lastActivityTime) < threshold
            }.keys
        )
    }

    /// Get all card IDs that have active (running) sessions
    func activeSessionCardIds() -> Set<UUID> {
        return Set(
            sessions.filter { _, session in
                session.isRunning
            }.keys
        )
    }

    /// Close a terminal session (graceful exit)
    /// For direct: sends exit command
    /// For tmux: detaches the session (keeps running in background)
    func closeSession(for cardId: UUID) {
        guard let session = sessions[cardId], session.isRunning else { return }
        switch session.backend {
        case .direct:
            session.terminal.send(txt: "exit\n")
        case .tmuxAttach:
            session.terminal.send(txt: "\u{02}d")  // Ctrl+B, d to detach
        case .tmuxControl:
            // Control mode sessions don't need detach command
            break
        }
    }

    /// Restart a terminal session (terminate and remove, will be recreated on next access)
    func restartSession(for cardId: UUID) {
        guard sessions[cardId] != nil else { return }
        // Mark session for restart - actual cleanup happens in getOrCreateSession
        // when the view is recreated. This avoids race conditions between
        // session removal and SwiftUI view lifecycle.
        sessions[cardId]?.pendingRestart = true
    }

    /// Remove a session (when card is deleted or tab closed)
    /// For tmux sessions: detaches by default (session continues running)
    /// For direct sessions: terminates the process
    /// Set killTmuxSession=true to fully terminate tmux sessions
    func removeSession(for cardId: UUID, killTmuxSession: Bool = false) {
        guard let session = sessions.removeValue(forKey: cardId) else { return }

        // Disconnect control mode first if it exists
        if let controlSession = session.controlModeSession {
            controlSession.disconnect()
        }

        // Clean up pane terminals
        paneTerminals.removeValue(forKey: cardId)

        // Clean up event monitors before destroying terminal to prevent EV_VANISHED errors
        // This must happen before the session is fully removed to avoid race conditions
        session.terminal.cleanupAutoScrollDuringSelection()
        session.terminal.cleanupCopyOnSelect()
        session.terminal.cleanupKeyInputMonitor()

        if session.isRunning {
            switch session.backend {
            case .direct:
                // Direct mode: terminate the shell
                session.terminal.send(txt: "exit\n")

            case .tmuxAttach:
                if killTmuxSession {
                    // User explicitly wants to kill the tmux session
                    let sessionName = tmuxManager.sessionName(for: cardId)
                    Task {
                        try? await tmuxManager.killSession(name: sessionName)
                    }
                }
                // Otherwise just detach - the tmux session keeps running
                // When user closes the tab, they're just detaching, not killing
                session.terminal.send(txt: "\u{02}d")  // Ctrl+B, d to detach

            case .tmuxControl:
                if killTmuxSession {
                    // User explicitly wants to kill the tmux session
                    let sessionName = tmuxManager.sessionName(for: cardId)
                    Task {
                        try? await tmuxManager.killSession(name: sessionName)
                    }
                }
                // No detach command needed for control mode
            }
        }
    }

    /// Forcefully kill a terminal session (SIGKILL)
    /// Use this for stuck/unresponsive terminals that won't respond to graceful exit
    func killSession(for cardId: UUID) {
        guard let session = sessions.removeValue(forKey: cardId) else { return }

        // Disconnect control mode first if it exists
        if let controlSession = session.controlModeSession {
            controlSession.disconnect()
        }

        // Clean up pane terminals
        paneTerminals.removeValue(forKey: cardId)

        // Clean up event monitors before destroying terminal to prevent EV_VANISHED errors
        session.terminal.cleanupAutoScrollDuringSelection()
        session.terminal.cleanupCopyOnSelect()
        session.terminal.cleanupKeyInputMonitor()

        if session.isRunning {
            switch session.backend {
            case .direct:
                // Send SIGKILL to forcefully terminate the process
                let pid = session.terminal.process.shellPid
                if pid != 0 {
                    kill(pid, SIGKILL)
                }
            case .tmuxAttach, .tmuxControl:
                // For tmux: kill the tmux session entirely
                let sessionName = tmuxManager.sessionName(for: cardId)
                Task {
                    try? await tmuxManager.killSession(name: sessionName)
                }
            }
        }
    }

    /// Clean up all sessions on app quit
    /// tmux sessions are detached (persist), direct sessions are terminated
    func removeAllSessions() {
        let allSessions = sessions
        sessions.removeAll()

        // Clean up all pane terminals
        paneTerminals.removeAll()

        for (_, session) in allSessions {
            // Disconnect control mode if exists
            if let controlSession = session.controlModeSession {
                controlSession.disconnect()
            }

            if session.isRunning {
                switch session.backend {
                case .direct:
                    session.terminal.send(txt: "exit\n")
                case .tmuxAttach:
                    // Just detach - tmux sessions persist across app restarts
                    session.terminal.send(txt: "\u{02}d")
                case .tmuxControl:
                    // Control mode sessions persist automatically, no detach command needed
                    break
                }
            }
        }
    }

    /// Fully terminate a tmux session (kill, not just detach)
    func killTmuxSession(for cardId: UUID) {
        removeSession(for: cardId, killTmuxSession: true)
    }

    /// Get the backend type for an active session
    func getBackend(for cardId: UUID) -> TerminalBackend? {
        return sessions[cardId]?.backend
    }

    // MARK: - TMUX Pane Operations

    /// Send a tmux command to the session (for pane operations, etc.)
    func sendTmuxCommand(_ command: String, to cardId: UUID) {
        guard let session = sessions[cardId],
            session.backend == .tmuxAttach,
            session.isRunning
        else { return }

        // tmux commands are sent via the prefix key (Ctrl+B by default)
        // For programmatic control, we use tmux CLI
        let sessionName = tmuxManager.sessionName(for: cardId)
        guard let tmuxPath = tmuxManager.tmuxPath else { return }

        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmuxPath)
            process.arguments = [command] + ["-t", sessionName]
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// Split the current pane horizontally (top/bottom)
    func splitPaneHorizontally(cardId: UUID) {
        guard let session = sessions[cardId],
            session.backend == .tmuxControl,
            let controlSession = session.controlModeSession
        else { return }

        // Use control mode to split pane
        // This will automatically trigger %layout-change event which updates UI
        controlSession.splitHorizontal()

        // Trigger immediate UI update
        objectWillChange.send()
    }

    /// Split the current pane vertically (left/right)
    func splitPaneVertically(cardId: UUID) {
        guard let session = sessions[cardId],
            session.backend == .tmuxControl,
            let controlSession = session.controlModeSession
        else { return }

        // Use control mode to split pane
        // This will automatically trigger %layout-change event which updates UI
        controlSession.splitVertical()

        // Trigger immediate UI update
        objectWillChange.send()
    }

    /// Navigate to adjacent pane
    func selectPane(direction: PaneDirection, cardId: UUID) {
        guard let session = sessions[cardId],
            session.backend == .tmuxControl,
            let controlSession = session.controlModeSession
        else { return }

        // Use control mode to select pane
        // This will automatically trigger pane mode change events
        controlSession.selectPane(direction: direction)

        // Trigger immediate UI update
        objectWillChange.send()
    }

    // MARK: - Private Helpers

    /// Escape string for use as a shell argument (single-quote style)
    /// Used for paths, shell names, and other non-LLM values
    internal func escapeShellArg(_ arg: String) -> String {
        return "'" + arg.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// Escape string for use inside double quotes (for LLM values)
    /// Escapes: " $ ` \ (prevents injection while templates contain the quotes)
    private func escapeForDoubleQuotes(_ str: String) -> String {
        return
            str
            .replacingOccurrences(of: "\\", with: "\\\\")  // Backslash first
            .replacingOccurrences(of: "\"", with: "\\\"")  // Double quotes
            .replacingOccurrences(of: "$", with: "\\$")  // Dollar signs (prevents variable expansion)
            .replacingOccurrences(of: "`", with: "\\`")  // Backticks (prevents command substitution)
    }

    /// Sanitize a string to be a valid environment variable name suffix
    /// - Converts to uppercase
    /// - Replaces invalid characters with underscores
    /// - Removes leading digits
    private func sanitizeEnvVarName(_ name: String) -> String {
        var result = name.uppercased()

        // Replace any character that isn't A-Z, 0-9, or underscore with underscore
        result = result.map { char -> Character in
            if char.isLetter || char.isNumber || char == "_" {
                return char
            }
            return "_"
        }.reduce("") { String($0) + String($1) }

        // Remove leading digits/underscores
        while let first = result.first, first.isNumber || first == "_" {
            result.removeFirst()
        }

        return result
    }

    // MARK: - Theme Support

    /// Apply theme to a terminal view (delegates to theme manager)
    func applyTheme(to terminal: TermQTerminalView, theme: TerminalTheme? = nil) {
        themeManager.applyTheme(to: terminal, theme: theme)
    }

    /// Apply theme to all active sessions
    func applyThemeToAllSessions() {
        let theme = currentTheme
        for (_, session) in sessions {
            themeManager.applyTheme(to: session.terminal, theme: theme)
            session.container.layer?.backgroundColor = theme.background.cgColor
        }
    }
}

/// Direction for pane navigation
public enum PaneDirection: Sendable {
    case up, down, left, right
}

/// Delegate to handle terminal process events
class SessionDelegate: NSObject, LocalProcessTerminalViewDelegate {
    let cardId: UUID
    weak var manager: TerminalSessionManager?
    let onExit: @Sendable @MainActor () -> Void

    init(cardId: UUID, manager: TerminalSessionManager, onExit: @escaping @Sendable @MainActor () -> Void) {
        self.cardId = cardId
        self.manager = manager
        self.onExit = onExit
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Track the current directory when the shell reports it via OSC 7
        // Capture values before Task to avoid Swift 6 Sendable issues
        let cardId = self.cardId
        let manager = self.manager
        Task { @MainActor in
            if let dir = directory {
                // Parse file:// URL if present
                if let url = URL(string: dir), url.scheme == "file" {
                    manager?.updateCurrentDirectory(cardId: cardId, directory: url.path)
                } else {
                    manager?.updateCurrentDirectory(cardId: cardId, directory: dir)
                }
            }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Capture values before Task to avoid Swift 6 Sendable issues
        let cardId = self.cardId
        let manager = self.manager
        let onExit = self.onExit
        Task { @MainActor in
            // Only call onExit if the session still exists in the manager.
            // If it was intentionally removed (via removeSession), we skip the callback
            // to avoid showing "Terminal session ended" on a different tab.
            guard manager?.sessionExists(for: cardId) == true else { return }

            manager?.markSessionTerminated(cardId: cardId)
            onExit()
        }
    }
}
