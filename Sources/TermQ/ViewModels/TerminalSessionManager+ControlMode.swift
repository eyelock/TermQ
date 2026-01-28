import Foundation
import TermQCore

// MARK: - Control Mode Integration

extension TerminalSessionManager {

    // MARK: - Session Startup

    /// Start a tmux-backed session with control mode (full pane management)
    func startTmuxControlProcess(
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

        // Capture values to avoid data race warnings
        let cardId = card.id
        let workingDirectory = card.workingDirectory
        let shellPath = card.shellPath
        let metadata = TerminalCardMetadata.from(card)

        // Create and configure the tmux session if it doesn't exist
        // This is a one-shot setup - we don't attach here, control mode will handle all I/O
        Task {
            let script = """
                # Create session if it doesn't exist
                if ! \(escapeShellArg(tmuxPath)) has-session -t \(escapeShellArg(sessionName)) 2>/dev/null; then
                    \(escapeShellArg(tmuxPath)) new-session -d -s \(escapeShellArg(sessionName)) -c \(escapeShellArg(workingDirectory)) \(tmuxEnvArgs.map { escapeShellArg($0) }.joined(separator: " ")) \(escapeShellArg(shellPath)) -l
                fi
                # Configure session for TermQ
                \(escapeShellArg(tmuxPath)) set-option -t \(escapeShellArg(sessionName)) status off 2>/dev/null || true
                \(escapeShellArg(tmuxPath)) set-option -t \(escapeShellArg(sessionName)) mouse on 2>/dev/null || true
                \(escapeShellArg(tmuxPath)) set-option -t \(escapeShellArg(sessionName)) default-terminal 'xterm-256color' 2>/dev/null || true
                \(escapeShellArg(tmuxPath)) set-option -t \(escapeShellArg(sessionName)) escape-time 10 2>/dev/null || true
                \(escapeShellArg(tmuxPath)) set-option -t \(escapeShellArg(sessionName)) allow-passthrough off 2>/dev/null || true
                """

            // Run setup script
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]
            try? process.run()
            process.waitUntilExit()

            // Now start control mode session for ALL interaction
            let controlSession = TmuxControlModeSession(sessionName: sessionName)

            await MainActor.run {
                setupControlModeCallbacks(for: cardId, session: controlSession)
            }

            // Connect to control mode
            try? await controlSession.connect()

            // Store control mode session in the terminal session
            await MainActor.run {
                sessions[cardId]?.controlModeSession = controlSession
                // Set active pane ID from parser
                if let activePane = controlSession.parser.panes.first(where: { $0.isActive }) {
                    sessions[cardId]?.activePaneId = activePane.id
                }
                objectWillChange.send()
            }

            // Sync full metadata to tmux session
            await tmuxManager.syncMetadataToSession(sessionName: sessionName, card: metadata)
        }
    }

    // MARK: - Pane Navigation & Management

    /// Select pane by direction (deprecated - use setActivePane instead)
    @available(*, deprecated, message: "Use setActivePane instead")
    func selectPaneOld(direction: PaneDirection, cardId: UUID) {
        guard let session = sessions[cardId],
            session.backend == .tmuxAttach,
            let tmuxPath = tmuxManager.tmuxPath
        else { return }

        let sessionName = tmuxManager.sessionName(for: cardId)
        let flag: String
        switch direction {
        case .up: flag = "-U"
        case .down: flag = "-D"
        case .left: flag = "-L"
        case .right: flag = "-R"
        }

        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmuxPath)
            process.arguments = ["select-pane", flag, "-t", sessionName]
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// Close the current pane (if multiple panes exist)
    func closeCurrentPane(cardId: UUID) {
        guard let session = sessions[cardId],
            session.backend == .tmuxControl,
            let controlSession = session.controlModeSession
        else { return }

        // Use control mode to close pane
        // This will automatically trigger %layout-change event which updates UI
        controlSession.closePane()

        // Trigger immediate UI update
        objectWillChange.send()
    }

    /// Zoom/unzoom the current pane (fullscreen toggle)
    func togglePaneZoom(cardId: UUID) {
        guard let session = sessions[cardId],
            session.backend == .tmuxControl,
            let controlSession = session.controlModeSession
        else { return }

        // Use control mode to zoom/unzoom pane
        // This will automatically trigger %layout-change event which updates UI
        controlSession.toggleZoom()

        // Trigger immediate UI update
        objectWillChange.send()
    }

    /// Set the active pane for input routing
    func setActivePane(cardId: UUID, paneId: String) {
        sessions[cardId]?.activePaneId = paneId

        // Select the pane in tmux
        if let controlSession = sessions[cardId]?.controlModeSession {
            controlSession.selectPane(id: paneId)
        }
    }

    // MARK: - Session Access

    /// Get the control mode session for a card (if it exists)
    func getControlModeSession(for cardId: UUID) -> TmuxControlModeSession? {
        return sessions[cardId]?.controlModeSession
    }

    /// Get terminal view for a specific pane (creates if doesn't exist)
    func getTerminalView(for cardId: UUID, paneId: String) -> TermQTerminalView? {
        // Ensure pane terminals dictionary exists for this card
        if paneTerminals[cardId] == nil {
            paneTerminals[cardId] = [:]
        }

        // Return existing terminal view if available
        if let existingView = paneTerminals[cardId]?[paneId] {
            return existingView
        }

        // Create new terminal view for this pane
        let terminalView = TermQTerminalView(frame: .zero)

        // Configure terminal with same settings as main terminal
        if let session = sessions[cardId] {
            terminalView.font = session.terminal.font
            // Apply theme
            let theme = themeManager.theme(for: "")  // Use default theme for panes
            themeManager.applyTheme(to: terminalView, theme: theme)
        }

        paneTerminals[cardId]?[paneId] = terminalView
        return terminalView
    }

    // MARK: - Output Handling

    /// Handle pane output from control mode
    /// Routes output to per-pane terminal views used by TmuxMultiPaneView
    private func handlePaneOutput(cardId: UUID, paneId: String, data: Data) {
        // Get or create terminal view for this pane
        guard let paneTerminal = getTerminalView(for: cardId, paneId: paneId) else {
            return
        }

        // Feed data to the pane's terminal emulator
        let bytes = [UInt8](data)
        paneTerminal.feed(byteArray: bytes[...])
    }

    /// Set up control mode callbacks for a tmux session
    private func setupControlModeCallbacks(for cardId: UUID, session: TmuxControlModeSession) {
        // Route pane output to correct terminal emulator
        session.onPaneOutput = { [weak self] paneId, data in
            self?.handlePaneOutput(cardId: cardId, paneId: paneId, data: data)
        }

        // Trigger UI refresh on layout changes
        session.parser.onLayoutChange = { [weak self] _, _ in
            self?.objectWillChange.send()
        }

        // Trigger UI refresh on window add/close
        session.parser.onWindowAdd = { [weak self] _ in
            self?.objectWillChange.send()
        }

        session.parser.onWindowClose = { [weak self] _ in
            self?.objectWillChange.send()
        }

        // Track active pane changes
        session.parser.onPaneModeChanged = { [weak self] paneId in
            self?.sessions[cardId]?.activePaneId = paneId
            self?.objectWillChange.send()
        }

        // Handle session exit
        session.parser.onExit = { [weak self] _ in
            self?.sessions[cardId]?.isRunning = false
            self?.objectWillChange.send()
        }
    }
}
