import AppKit
import Foundation
import SwiftTerm
import TermQCore

/// Manages persistent terminal sessions across view navigations
@MainActor
class TerminalSessionManager: ObservableObject {
    static let shared = TerminalSessionManager()

    /// Current theme ID (stored in UserDefaults)
    @Published var themeId: String {
        didSet {
            UserDefaults.standard.set(themeId, forKey: "terminalTheme")
            applyThemeToAllSessions()
        }
    }

    /// Current theme
    var currentTheme: TerminalTheme {
        TerminalTheme.theme(for: themeId)
    }

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
        // Load saved theme or use default
        self.themeId = UserDefaults.standard.string(forKey: "terminalTheme") ?? "default-dark"
    }

    /// Get or create a terminal session for a card
    func getOrCreateSession(
        for card: TerminalCard,
        onExit: @escaping () -> Void,
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
        let effectiveThemeId = card.themeId.isEmpty ? themeId : card.themeId
        let theme = TerminalTheme.theme(for: effectiveThemeId)
        applyTheme(to: terminal, theme: theme)

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
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"

        // Start shell in the correct working directory using exec
        // This avoids the visible "cd" command flash by:
        // 1. Starting /bin/sh (non-interactive)
        // 2. cd to the working directory
        // 3. exec the user's shell as a login shell (replaces the process)
        let startCommand = "cd \(escapeShellArg(card.workingDirectory)) && exec \(escapeShellArg(card.shellPath)) -l"
        terminal.startProcess(
            executable: "/bin/sh",
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

        // Track if we're running an LLM action (for init command delay)
        let hasLlmAction = !card.llmNextAction.isEmpty

        // Run LLM next action if specified (one-time, then clear)
        if hasLlmAction {
            let llmAction = card.llmNextAction
            // Escape quotes in the prompt for shell
            let escapedPrompt = llmAction.replacingOccurrences(of: "\"", with: "\\\"")
            let llmCommand = "claude \"\(escapedPrompt)\""

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                terminal.send(txt: llmCommand + "\n")
            }

            // Clear the next action and save
            card.llmNextAction = ""
            BoardViewModel.shared.updateCard(card)
        }

        // Run init command if specified (after a short delay to let shell initialize)
        if !card.initCommand.isEmpty {
            let initCmd = card.initCommand
            // Delay slightly more if llmNextAction was also run
            let delay = hasLlmAction ? 1.0 : 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
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
    func isProcessing(cardId: UUID, threshold: TimeInterval = 2.0) -> Bool {
        guard let session = sessions[cardId], session.isRunning else { return false }
        return Date().timeIntervalSince(session.lastActivityTime) < threshold
    }

    /// Get all card IDs that are currently processing
    func processingCardIds(threshold: TimeInterval = 2.0) -> Set<UUID> {
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

    // MARK: - Theme Support

    /// Apply theme to a terminal view
    func applyTheme(to terminal: TermQTerminalView, theme: TerminalTheme? = nil) {
        let theme = theme ?? currentTheme

        // Set foreground and background colors
        terminal.nativeForegroundColor = theme.foreground
        terminal.nativeBackgroundColor = theme.background

        // Set cursor color
        terminal.caretColor = theme.cursor

        // Install the ANSI color palette
        terminal.installColors(theme.swiftTermColors)

        // Update container background if available
        if let container = terminal.superview as? TerminalContainerView {
            container.layer?.backgroundColor = theme.background.cgColor
        }

        // Force redraw
        terminal.setNeedsDisplay(terminal.bounds)
    }

    /// Apply theme to all active sessions
    func applyThemeToAllSessions() {
        let theme = currentTheme
        for (_, session) in sessions {
            applyTheme(to: session.terminal)
            // Also update container background
            session.container.layer?.backgroundColor = theme.background.cgColor
        }
    }
}

/// Delegate to handle terminal process events
class SessionDelegate: NSObject, LocalProcessTerminalViewDelegate {
    let cardId: UUID
    weak var manager: TerminalSessionManager?
    let onExit: () -> Void

    init(cardId: UUID, manager: TerminalSessionManager, onExit: @escaping () -> Void) {
        self.cardId = cardId
        self.manager = manager
        self.onExit = onExit
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Track the current directory when the shell reports it via OSC 7
        Task { @MainActor in
            if let dir = directory {
                // Parse file:// URL if present
                if let url = URL(string: dir), url.scheme == "file" {
                    self.manager?.updateCurrentDirectory(cardId: self.cardId, directory: url.path)
                } else {
                    self.manager?.updateCurrentDirectory(cardId: self.cardId, directory: dir)
                }
            }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            // Only call onExit if the session still exists in the manager.
            // If it was intentionally removed (via removeSession), we skip the callback
            // to avoid showing "Terminal session ended" on a different tab.
            guard self.manager?.sessionExists(for: self.cardId) == true else { return }

            self.manager?.markSessionTerminated(cardId: self.cardId)
            self.onExit()
        }
    }
}
