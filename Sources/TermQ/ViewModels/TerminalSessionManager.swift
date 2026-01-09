import AppKit
import Foundation
import SwiftTerm
import TermQCore

/// Manages persistent terminal sessions across view navigations
@MainActor
class TerminalSessionManager: ObservableObject {
    static let shared = TerminalSessionManager()

    /// Active terminal sessions keyed by card ID
    private var sessions: [UUID: TerminalSession] = [:]

    struct TerminalSession {
        let terminal: TermQTerminalView
        let container: TerminalContainerView
        var isRunning: Bool = true
        var currentDirectory: String?
    }

    private init() {}

    /// Get or create a terminal session for a card
    func getOrCreateSession(for card: TerminalCard, onExit: @escaping () -> Void) -> TerminalContainerView {
        // Return existing session if available
        if let session = sessions[card.id], session.isRunning {
            // Re-focus the terminal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                session.container.window?.makeFirstResponder(session.terminal)
            }
            return session.container
        }

        // Create new terminal (using our subclass that fixes copy/paste)
        let terminal = TermQTerminalView(frame: .zero)

        // Configure terminal appearance
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

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

        return container
    }

    /// Check if a session exists and is running
    func hasActiveSession(for cardId: UUID) -> Bool {
        return sessions[cardId]?.isRunning ?? false
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

    /// Remove a session (when card is deleted)
    func removeSession(for cardId: UUID) {
        if let session = sessions[cardId] {
            // Terminate the process if still running
            if session.isRunning {
                session.terminal.send(txt: "exit\n")
            }
        }
        sessions.removeValue(forKey: cardId)
    }

    /// Clean up all sessions
    func removeAllSessions() {
        for (_, session) in sessions {
            if session.isRunning {
                session.terminal.send(txt: "exit\n")
            }
        }
        sessions.removeAll()
    }

    private func escapeShellArg(_ arg: String) -> String {
        return "'" + arg.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
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
            self.manager?.markSessionTerminated(cardId: self.cardId)
            self.onExit()
        }
    }
}
