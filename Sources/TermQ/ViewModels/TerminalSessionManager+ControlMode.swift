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
        guard newCols > 0, newRows > 0 else { return }
        let capturedCardId = self.cardId
        let capturedPaneId = self.paneId
        let capturedCols = newCols
        let capturedRows = newRows
        Task { @MainActor in
            guard
                let controlSession = TerminalSessionManager.shared
                    .getControlModeSession(for: capturedCardId)
            else { return }
            let allPanes = controlSession.parser.panes

            // Skip if this pane isn't reflected in the parser yet.
            // This happens during a split transition: the new pane gets a SwiftUI
            // frame before the list-panes response has updated parser.panes, so we
            // can't scale its size reliably.  Wait for the next render cycle.
            guard let parserPane = allPanes.first(where: { $0.id == capturedPaneId }) else {
                TermQLogger.tmux.debug(
                    "sizeChanged SKIP pane=\(capturedPaneId) swiftterm=\(capturedCols)x\(capturedRows) reason=not-in-parser"
                )
                return
            }

            // SwiftTerm computed cols/rows from PIXEL space for this one pane.
            // Scale those up to the full tmux window using the parser's proportions.
            // Single-pane: ratio is 1 → exact. Multi-pane: extrapolation via ratio,
            // which is accurate for the widest/tallest pane and approximate for the
            // rest (deduplication in sendClientResize absorbs any minor drift).
            let totalParserCols = max(1, allPanes.map { $0.x + $0.width }.max() ?? 1)
            let totalParserRows = max(1, allPanes.map { $0.y + $0.height }.max() ?? 1)
            let paneParserWidth = max(1, parserPane.width)
            let paneParserHeight = max(1, parserPane.height)

            let computedCols = max(
                1,
                Int(
                    round(
                        Double(capturedCols) * Double(totalParserCols) / Double(paneParserWidth))))
            let computedRows = max(
                1,
                Int(
                    round(
                        Double(capturedRows) * Double(totalParserRows)
                            / Double(paneParserHeight))))

            // Snap to the parser's current total if within ±2 to absorb pixel-rounding
            // noise.  SwiftUI proportional layout doesn't guarantee an exact multiple of
            // cellHeight/cellWidth, so SwiftTerm's floor() can land 1–2 units below the
            // correct value.  A ≤2 difference is rounding, not a user-driven resize.
            let cols = abs(computedCols - totalParserCols) <= 2 ? totalParserCols : computedCols
            let rows = abs(computedRows - totalParserRows) <= 2 ? totalParserRows : computedRows

            let paneIds = allPanes.map { "\($0.id):\($0.width)x\($0.height)@\($0.x),\($0.y)" }
                .joined(separator: " ")
            TermQLogger.tmux.debug(
                "sizeChanged pane=\(capturedPaneId) swiftterm=\(capturedCols)x\(capturedRows)"
                    + " computed=\(computedCols)x\(computedRows) snap=\(cols)x\(rows)"
                    + " parser={\(paneIds)}"
            )

            controlSession.sendClientResize(cols: cols, rows: rows)
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
            // Detect before connecting so we know whether to clear PROMPT_SP
            // artifacts after the resize cycle. new-session -A attaches to the
            // existing session without starting a new shell, so we can't rely on
            // a fresh prompt — the resize reflow triggers zsh PROMPT_SP ("%")
            // marks that need a Ctrl+L to clear.
            let isExistingSession = await tmuxSessionExists(name: sessionName)
            TermQLogger.session.info(
                "startTmuxControl session=\(sessionName) existing=\(isExistingSession)"
            )

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

            if isExistingSession {
                // Wait for the resize cycle (SwiftUI layout → sizeChanged →
                // refresh-client → tmux reflow → %layout-change → list-panes)
                // to fully settle before clearing PROMPT_SP artifacts.
                try? await Task.sleep(nanoseconds: 700_000_000)
                await MainActor.run {
                    let paneIds = controlSession.parser.panes.map { $0.id }.joined(separator: " ")
                    TermQLogger.session.info("existing session — sending Ctrl+L to clear PROMPT_SP panes={\(paneIds)}")
                    for pane in controlSession.parser.panes {
                        controlSession.sendCommand("send-keys -H -t %\(pane.id) 0c")
                    }
                }
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
        // select-pane doesn't trigger %layout-change, so tmux won't send an event
        // we can react to. Fire objectWillChange now so the border updates immediately.
        objectWillChange.send()

        if let controlSession = sessions[cardId]?.controlModeSession {
            controlSession.selectPane(id: paneId)
        }
    }

    /// Get the active pane ID for a card
    func getActivePaneId(for cardId: UUID) -> String? {
        return sessions[cardId]?.activePaneId
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
        if TermQLogger.fileLoggingEnabled {
            let preview = bytes.prefix(80).map { b -> String in
                switch b {
                case 0x1B: return "\\e"
                case 0x07: return "\\a"
                case 0x0D: return "\\r"
                case 0x0A: return "\\n"
                case 0x5C: return "\\\\"
                case 0x20...0x7E: return String(UnicodeScalar(b))
                default: return String(format: "\\x%02X", b)
                }
            }.joined()
            TermQLogger.io.debug("output pane=\(paneId) len=\(data.count) «\(preview)»")
        }
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
            // Re-query pane layout on every change so split/close operations
            // update parser.panes (pane ID lines like "%0 80 24 0 0 1" start
            // with "%" and require the parseLine fix to be routed correctly).
            let beforePaneIds = Set(session.parser.panes.map { $0.id })
            let beforeDesc = session.parser.panes.map { "\($0.id):\($0.width)x\($0.height)" }
                .joined(separator: " ")
            TermQLogger.tmux.debug("layoutChange before={\(beforeDesc)}")
            session.sendCommand(
                "list-panes -F '#{pane_id} #{pane_width} #{pane_height} #{pane_left} #{pane_top} #{pane_active}'"
            )
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms for list-panes response
                self?.cleanupStalePaneTerminals(cardId: cardId, currentPanes: session.parser.panes)
                self?.objectWillChange.send()

                let afterDesc = session.parser.panes.map { "\($0.id):\($0.width)x\($0.height)" }
                    .joined(separator: " ")
                TermQLogger.tmux.debug("layoutChange after={\(afterDesc)}")

                // Send Ctrl+L to newly created panes after the resize settles.
                // zsh's PROMPT_SP fires when cursor isn't at column 0 before drawing
                // the prompt; a screen redraw after the size is stable clears it.
                let newPaneIds = Set(session.parser.panes.map { $0.id }).subtracting(beforePaneIds)
                if !newPaneIds.isEmpty {
                    TermQLogger.tmux.info(
                        "layoutChange new panes={\(newPaneIds.sorted().joined(separator: " "))} — scheduling Ctrl+L in 400ms"
                    )
                    try? await Task.sleep(nanoseconds: 400_000_000)  // 400ms for resize to settle
                    for paneId in newPaneIds {
                        session.sendCommand("send-keys -H -t %\(paneId) 0c")
                    }
                }
            }
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

    // MARK: - Helpers

    /// Returns true if a tmux session with this name already exists.
    ///
    /// Used to distinguish re-attach (existing session) from first-launch (new
    /// session) so we can send Ctrl+L only when needed to clear PROMPT_SP
    /// artifacts caused by the resize reflow on re-attach.
    private func tmuxSessionExists(name: String) async -> Bool {
        guard let tmuxPath = tmuxManager.tmuxPath else { return false }
        return await withCheckedContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: tmuxPath)
            proc.arguments = ["has-session", "-t", name]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            proc.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus == 0)
            }
            try? proc.run()
        }
    }
}
