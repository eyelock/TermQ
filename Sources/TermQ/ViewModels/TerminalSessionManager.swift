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

    /// Current theme ID - proxied to theme manager
    var themeId: String {
        get { themeManager.themeId }
        set { themeManager.themeId = newValue }
    }

    /// Current theme - proxied to theme manager
    var currentTheme: TerminalTheme {
        themeManager.currentTheme
    }

    // MARK: - Session Storage

    /// Active terminal sessions keyed by card ID
    private var sessions: [UUID: TerminalSession] = [:]

    struct TerminalSession {
        let terminal: TermQTerminalView
        let container: TerminalContainerView
        var isRunning: Bool = true
        var currentDirectory: String?
        var lastActivityTime: Date = Date()
    }

    private init() {
        // Set up theme change callback
        themeManager.onThemeChanged = { [weak self] in
            self?.applyThemeToAllSessions()
        }
    }

    /// Get or create a terminal session for a card
    func getOrCreateSession(
        for card: TerminalCard,
        onExit: @escaping @Sendable @MainActor () -> Void,
        onBell: @escaping () -> Void,
        onActivity: @escaping () -> Void
    ) -> TerminalContainerView {
        // Return existing session if available
        if let session = sessions[card.id], session.isRunning {
            // Update callbacks (views may be recreated, especially in release builds)
            session.terminal.onBell = onBell
            session.terminal.onActivity = { [weak self] in
                self?.updateActivityTime(cardId: card.id)
                onActivity()
            }
            // Re-focus the terminal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                session.container.window?.makeFirstResponder(session.terminal)
            }
            return session.container
        }

        // Create new terminal (using our subclass that fixes copy/paste)
        let terminal = TermQTerminalView(frame: .zero)
        terminal.cardId = card.id
        terminal.terminalTitle = card.title
        terminal.safePasteEnabled = card.safePasteEnabled
        terminal.onDisableSafePaste = {
            // Persist the change to the card model
            card.safePasteEnabled = false
        }
        terminal.onBell = onBell
        terminal.onActivity = { [weak self] in
            self?.updateActivityTime(cardId: card.id)
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

        // Add tag environment variables (TERMQ_TERMINAL_TAG_<KEY>=value)
        for tag in card.tags {
            let sanitizedKey = sanitizeEnvVarName(tag.key)
            if !sanitizedKey.isEmpty {
                env["TERMQ_TERMINAL_TAG_\(sanitizedKey)"] = tag.value
            }
        }

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

        // Create container with padding
        let container = TerminalContainerView(terminal: terminal)

        // Set up exit handler
        let delegate = SessionDelegate(cardId: card.id, manager: self, onExit: onExit)
        terminal.processDelegate = delegate

        // Store the delegate to prevent deallocation
        objc_setAssociatedObject(terminal, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

        // Store session
        sessions[card.id] = TerminalSession(terminal: terminal, container: container)

        // Run init command if specified (after a short delay to let shell initialize)
        // Supports token replacement for LLM integration:
        //   {{LLM_PROMPT}} - replaced with persistent context
        //   {{LLM_NEXT_ACTION}} - replaced with one-time action (then cleared if autorun enabled)
        if !card.initCommand.isEmpty {
            let hasNextActionToken = card.initCommand.contains("{{LLM_NEXT_ACTION}}")
            let hadNextAction = !card.llmNextAction.isEmpty

            // Check if autorun is enabled (global AND per-terminal)
            let globalAutorunEnabled = UserDefaults.standard.bool(forKey: "enableTerminalAutorun")
            let autorunAllowed = globalAutorunEnabled && card.allowAutorun

            // Perform token replacement
            var initCmd = card.initCommand
            initCmd = initCmd.replacingOccurrences(of: "{{LLM_PROMPT}}", with: card.llmPrompt)

            // Only inject LLM_NEXT_ACTION if autorun is enabled
            if autorunAllowed {
                initCmd = initCmd.replacingOccurrences(of: "{{LLM_NEXT_ACTION}}", with: card.llmNextAction)

                // Clear llmNextAction after use (if token was present and had a value)
                if hasNextActionToken && hadNextAction {
                    card.llmNextAction = ""
                    BoardViewModel.shared.updateCard(card)
                }
            } else {
                // Replace token with empty string (don't consume the action)
                initCmd = initCmd.replacingOccurrences(of: "{{LLM_NEXT_ACTION}}", with: "")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                terminal.send(txt: initCmd + "\n")
            }
        }

        return container
    }

    /// Check if a session exists and is running
    func hasActiveSession(for cardId: UUID) -> Bool {
        return sessions[cardId]?.isRunning ?? false
    }

    /// Check if a session exists at all (regardless of running state)
    func sessionExists(for cardId: UUID) -> Bool {
        return sessions[cardId] != nil
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

    /// Remove a session (when card is deleted)
    /// Important: We remove from dictionary FIRST, then terminate.
    /// This ensures processTerminated callback won't fire onExit for a deleted tab.
    func removeSession(for cardId: UUID) {
        guard let session = sessions.removeValue(forKey: cardId) else { return }

        // Terminate the process if still running
        // The session is already removed from the dictionary, so when processTerminated
        // fires, it will see the session is gone and skip the onExit callback.
        if session.isRunning {
            session.terminal.send(txt: "exit\n")
        }
    }

    /// Clean up all sessions
    func removeAllSessions() {
        // Remove all sessions from dictionary first, then terminate
        let allSessions = sessions
        sessions.removeAll()

        for (_, session) in allSessions {
            if session.isRunning {
                session.terminal.send(txt: "exit\n")
            }
        }
    }

    private func escapeShellArg(_ arg: String) -> String {
        return "'" + arg.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
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
