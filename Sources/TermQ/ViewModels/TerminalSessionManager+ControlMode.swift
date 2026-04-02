import AppKit
import Foundation
import SwiftTerm
import TermQCore

// MARK: - Control Mode Terminal View

/// Simple terminal view for control mode panes (no local process)
class ControlModeTerminalView: TerminalView {
    init() {
        super.init(frame: .zero)
        self.terminalDelegate = nil  // Will be set by SessionManager
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
}

// MARK: - Control Mode Pane Delegate

/// Terminal delegate that routes input to tmux control mode instead of local PTY
class ControlModePaneDelegate: TerminalViewDelegate {
    let cardId: UUID
    let paneId: String

    init(cardId: UUID, paneId: String) {
        self.cardId = cardId
        self.paneId = paneId
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let capturedCardId = self.cardId
        let capturedPaneId = self.paneId
        let inputData = Data(data)

        Task { @MainActor in
            guard
                let controlSession = TerminalSessionManager.shared
                    .getControlModeSession(for: capturedCardId)
            else { return }
            controlSession.sendInputToPane(inputData, paneId: capturedPaneId)
        }
    }

    func scrolled(source: TerminalView, position: Double) {}

    func setTerminalTitle(source: TerminalView, title: String) {}

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        let capturedCardId = self.cardId
        Task { @MainActor in
            guard
                let controlSession = TerminalSessionManager.shared
                    .getControlModeSession(for: capturedCardId)
            else { return }
            controlSession.sendCommand("refresh-client -C \(newCols),\(newRows)")
        }
    }

    func setTerminalIconTitle(source: TerminalView, title: String) {}

    // MARK: - Unimplemented/Optional delegate methods

    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func bell(source: TerminalView) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}

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

        var tmuxEnvArgs: [String] = []
        for (key, value) in env {
            if key == "TERM" || key == "COLORTERM" { continue }
            tmuxEnvArgs.append("-e")
            tmuxEnvArgs.append("\(key)=\(value)")
        }

        guard tmuxManager.tmuxPath != nil else {
            startDirectProcess(terminal: terminal, card: card, environment: env)
            return
        }

        let cardId = card.id
        let workingDirectory = card.workingDirectory
        let shellPath = card.shellPath
        let metadata = TerminalCardMetadata.from(card)

        Task {
            let controlSession = TmuxControlModeSession(sessionName: sessionName)

            await MainActor.run {
                setupControlModeCallbacks(for: cardId, session: controlSession)
            }

            do {
                try await controlSession.connect(
                    workingDirectory: workingDirectory,
                    shell: shellPath,
                    environment: env
                )
            } catch {
                return
            }

            await MainActor.run {
                sessions[cardId]?.controlModeSession = controlSession
                if let activePane = controlSession.parser.panes.first(where: { $0.isActive }) {
                    sessions[cardId]?.activePaneId = activePane.id
                }
                objectWillChange.send()
            }

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

        controlSession.closePane()
        objectWillChange.send()
    }

    /// Zoom/unzoom the current pane (fullscreen toggle)
    func togglePaneZoom(cardId: UUID) {
        guard let session = sessions[cardId],
            session.backend == .tmuxControl,
            let controlSession = session.controlModeSession
        else { return }

        controlSession.toggleZoom()
        objectWillChange.send()
    }

    /// Set the active pane for input routing
    func setActivePane(cardId: UUID, paneId: String) {
        sessions[cardId]?.activePaneId = paneId

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
    func getTerminalView(for cardId: UUID, paneId: String) -> TerminalView? {
        if paneTerminals[cardId] == nil {
            paneTerminals[cardId] = [:]
        }

        if let existingView = paneTerminals[cardId]?[paneId] {
            return existingView
        }

        let terminalView = ControlModeTerminalView()

        if let session = sessions[cardId] {
            terminalView.font = session.terminal.font
            let theme = themeManager.theme(for: "")
            terminalView.nativeForegroundColor = theme.foreground
            terminalView.nativeBackgroundColor = theme.background
            terminalView.caretColor = theme.cursor
            terminalView.installColors(theme.swiftTermColors)
        }

        let delegate = ControlModePaneDelegate(cardId: cardId, paneId: paneId)
        terminalView.terminalDelegate = delegate
        Self.terminalDelegates[cardId, default: [:]][paneId] = delegate

        paneTerminals[cardId]?[paneId] = terminalView
        return terminalView
    }

    /// Store delegates to keep them alive
    private static var terminalDelegates: [UUID: [String: ControlModePaneDelegate]] = [:]

    /// Clean up terminal views and delegates for panes that no longer exist
    private func cleanupStalePaneTerminals(cardId: UUID, currentPanes: [TmuxPane]) {
        let currentPaneIds = Set(currentPanes.map(\.id))

        if let paneViews = paneTerminals[cardId] {
            for paneId in paneViews.keys where !currentPaneIds.contains(paneId) {
                paneTerminals[cardId]?.removeValue(forKey: paneId)
                Self.terminalDelegates[cardId]?.removeValue(forKey: paneId)
            }
        }
    }

    // MARK: - Output Handling

    /// Handle pane output from control mode
    private func handlePaneOutput(cardId: UUID, paneId: String, data: Data) {
        let bytes = [UInt8](data)

        if let paneTerminal = getTerminalView(for: cardId, paneId: paneId) {
            paneTerminal.feed(byteArray: bytes[...])
        }
    }

    /// Set up control mode callbacks for a tmux session
    private func setupControlModeCallbacks(for cardId: UUID, session: TmuxControlModeSession) {
        session.onPaneOutput = { [weak self] paneId, data in
            self?.handlePaneOutput(cardId: cardId, paneId: paneId, data: data)
        }

        session.parser.onLayoutChange = { [weak self] _, _ in
            self?.cleanupStalePaneTerminals(cardId: cardId, currentPanes: session.parser.panes)
            self?.objectWillChange.send()
        }

        session.parser.onWindowAdd = { [weak self] _ in
            self?.objectWillChange.send()
        }

        session.parser.onWindowClose = { [weak self] _ in
            self?.objectWillChange.send()
        }

        session.parser.onPaneModeChanged = { [weak self] _ in
            self?.objectWillChange.send()
        }

        session.parser.onExit = { [weak self] _ in
            self?.sessions[cardId]?.isRunning = false
            self?.objectWillChange.send()
        }
    }
}
