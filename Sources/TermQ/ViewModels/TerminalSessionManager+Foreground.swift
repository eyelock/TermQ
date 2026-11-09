import Darwin
import Foundation
import TermQCore
import TermQShared

/// Tells whether a program other than the shell holds a card's terminal, and
/// which session that answer was about. Injected so the close flows can be
/// tested without real terminals.
@MainActor
protocol TerminalForegroundProbing {
    /// When the card's current session started, or nil when it has none: an
    /// answer about one session must not act on a later one.
    func sessionStart(for cardId: UUID) -> Date?
    /// True when a program other than the shell runs (for a Wheelhouse seat,
    /// its harness); false when only the shell is left or nothing runs at
    /// all; nil when it can't be told. Callers treat nil as running.
    func isForegroundProgramRunning(for card: TerminalCard) async -> Bool?
}

// MARK: - What is running in a terminal

extension TerminalSessionManager: TerminalForegroundProbing {
    /// How long a session counts as still launching: its init command (such as
    /// `ynh run`) may not have started yet, so an idle shell proves nothing.
    static let launchGrace: TimeInterval = 10

    func sessionStart(for cardId: UUID) -> Date? { sessions[cardId]?.startedAt }

    func isForegroundProgramRunning(for card: TerminalCard) async -> Bool? {
        let shellName = card.tags.first { $0.key == "shell" }?.value
        guard let session = sessions[card.id] else {
            // Not attached here: a tmux session may still run on its own.
            guard effectiveBackend(for: card).usesTmux else { return false }
            return await tmuxPanesRunProgram(session: card.tmuxSessionName, shellName: shellName)
        }
        guard session.isRunning else { return false }
        if Date().timeIntervalSince(session.startedAt) < Self.launchGrace { return nil }
        switch session.backend {
        case .direct:
            // A harness stopped with Ctrl-Z or sent to the background leaves
            // the shell in the foreground, so it counts as not running.
            guard let process = session.terminal.process else { return nil }
            return Self.foregroundIsNotShell(foregroundGroup: tcgetpgrp(process.childfd), shellPid: process.shellPid)
        case .tmuxAttach, .tmuxControl:
            // The local process is only the tmux client: ask tmux.
            return await tmuxPanesRunProgram(session: tmuxManager.sessionName(for: card.id), shellName: shellName)
        }
    }

    /// Whether any pane of the tmux session runs something other than the
    /// card's shell. False when the session is gone; nil when tmux can't say.
    private func tmuxPanesRunProgram(session: String, shellName: String?) async -> Bool? {
        guard let tmux = tmuxManager.tmuxPath else { return nil }
        guard let exists = try? await StackProcessRunner.run(tmux, ["has-session", "-t", session], cwd: nil)
        else { return nil }
        if exists.exitCode != 0 { return false }
        guard
            let result = try? await StackProcessRunner.run(
                tmux, ["list-panes", "-s", "-t", session, "-F", "#{pane_current_command}"], cwd: nil),
            result.exitCode == 0
        else { return nil }
        let commands = result.stdout.split(whereSeparator: \.isNewline).map(String.init)
        return Self.panesRunProgram(commands, shellName: shellName)
    }

    /// Whether any of a session's pane commands is something other than the
    /// shell. With the card's shell known, only that shell counts as idle, so
    /// a harness started through a `bash` wrapper from `zsh` still counts.
    nonisolated static func panesRunProgram(_ commands: [String], shellName: String?) -> Bool? {
        guard !commands.isEmpty else { return nil }
        return commands.contains { command in
            if let shellName { return Self.loginName(command) != shellName }
            return !isShell(command)
        }
    }

    /// The pty's foreground process group against the shell's pid: anything
    /// else in the foreground is a program the shell started. Nil when the
    /// group can't be read.
    nonisolated static func foregroundIsNotShell(foregroundGroup: pid_t, shellPid: pid_t) -> Bool? {
        guard foregroundGroup > 0, shellPid > 0 else { return nil }
        return foregroundGroup != shellPid
    }

    /// Whether a process name is an interactive shell (a login shell shows as
    /// "-zsh").
    nonisolated static func isShell(_ command: String) -> Bool {
        ["zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "csh", "nu", "elvish", "xonsh"].contains(
            loginName(command))
    }

    nonisolated private static func loginName(_ command: String) -> String {
        command.hasPrefix("-") ? String(command.dropFirst()) : command
    }
}
