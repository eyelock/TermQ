import Foundation
import TermQCore

// MARK: - Control Mode Session

/// Manages a tmux control mode connection
@MainActor
public class TmuxControlModeSession: ObservableObject {
    /// Parser for control mode output
    public let parser = TmuxControlModeParser()
    private let sessionName: String

    /// Process and pipes are nonisolated(unsafe) for deinit access
    nonisolated(unsafe) private var process: Process?
    nonisolated(unsafe) private var outputPipe: Pipe?
    nonisolated(unsafe) private var inputPipe: Pipe?

    /// Current panes in the session
    @Published public private(set) var panes: [TmuxPane] = []

    /// Current windows in the session
    @Published public private(set) var windows: [TmuxWindow] = []

    /// Whether connected to the tmux session
    @Published public private(set) var isConnected: Bool = false

    /// Callback for pane output
    public var onPaneOutput: ((String, Data) -> Void)?

    public init(sessionName: String) {
        self.sessionName = sessionName
        setupParserCallbacks()
    }

    deinit {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
    }

    // MARK: - Connection

    /// Connect to the tmux session in control mode
    /// Creates a new session directly - do NOT pre-create the session
    public func connect(workingDirectory: String, shell: String, environment: [String: String]) async throws {
        guard let tmuxPath = TmuxManager.shared.tmuxPath else {
            throw TmuxError.notAvailable
        }

        // Create pipes for I/O
        let output = Pipe()
        let input = Pipe()
        self.outputPipe = output
        self.inputPipe = input

        // Set up process - direct tmux control mode with new-session.
        // Use -C (not -CC) because -CC requires TTY for termios modifications.
        // See: https://github.com/tmux/tmux/issues/3085
        //
        // -A: attach to an existing session if one exists, else create new.
        //     Without -A, new-session fails if the session already exists
        //     (e.g., on TermQ relaunch with persistent tmux sessions).
        // -c: starting directory for new sessions (ignored when attaching).
        // shell -l: login shell command for new sessions (ignored when attaching).
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmuxPath)
        proc.arguments = ["-C", "new-session", "-A", "-s", sessionName, "-c", workingDirectory, shell, "-l"]
        proc.standardOutput = output
        proc.standardInput = input
        proc.standardError = Pipe()  // Suppress stderr

        // Handle output asynchronously.
        // @Sendable breaks @MainActor isolation inheritance — FileHandle calls this
        // on a background queue, not the main actor.
        output.fileHandleForReading.readabilityHandler = { @Sendable [weak self] handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                TermQLogger.session.info("pipe EOF — removing readabilityHandler")
                handle.readabilityHandler = nil
                return
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    TermQLogger.session.warning("pipe-task: session nil — \(data.count) bytes discarded")
                    return
                }
                self.parser.parse(data)
            }
        }

        proc.terminationHandler = { _ in }

        try proc.run()
        self.process = proc

        // Wait for connection
        for _ in 1...10 {
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

            if parser.isConnected {
                break
            }

            if !proc.isRunning {
                throw TmuxError.notAvailable
            }
        }

        isConnected = parser.isConnected

        // Configure session options via control mode
        if parser.isConnected {
            // Enable the tmux backpressure pause/continue protocol.
            // Without this, tmux kills the control client with "too far behind"
            // if output queues for >5 minutes. With pause-after=1, tmux instead
            // sends %pause when a pane falls 1 second behind; we respond with
            // refresh-client -A %<id>:continue and receive %extended-output
            // from the current pane position. This prevents the %output stream
            // from stalling when TUI apps (Claude Code, htop) produce large
            // bursts of escape sequences.
            sendCommand("refresh-client -f pause-after=1")

            sendCommand("set-option -t \(sessionName) status off")
            sendCommand("set-option -t \(sessionName) mouse on")
            // TERM inside tmux must be tmux or screen variant — per tmux FAQ:
            // "Don't bother reporting problems where it isn't!"
            sendCommand("set-option -t \(sessionName) default-terminal 'tmux-256color'")
            sendCommand("set-option -t \(sessionName) escape-time 10")
            sendCommand("set-option -t \(sessionName) allow-passthrough on")

            // Set an initial client size so the pane isn't stuck at tmux's
            // default 80x24 before SwiftUI's layout fires refresh-client -C.
            sendClientResize(cols: 120, rows: 40)

            // Request initial pane information
            sendCommand(
                "list-panes -F '#{pane_id} #{pane_width} #{pane_height} #{pane_left} #{pane_top} #{pane_active}'")

            // Wait for panes response
            try await Task.sleep(nanoseconds: 200_000_000)  // 200ms

            await MainActor.run {
                self.panes = parser.panes
            }
        }

    }

    /// Disconnect from the tmux session
    public func disconnect() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
    }

    // MARK: - Client Resize (deduplicated)

    /// Last client size successfully sent — avoids sending duplicate refresh-client commands.
    private var lastClientCols: Int = 0
    private var lastClientRows: Int = 0

    /// Whether `sendClientResize` has been called at least once with valid dimensions.
    ///
    /// Used by init-command timing: processes that read terminal size at startup
    /// (e.g. Claude's TUI) need the pane to reflect SwiftUI's actual layout, not
    /// tmux's default 80×24. Callers poll this before sending commands.
    public private(set) var hasReceivedClientResize: Bool = false

    /// Resize the tmux client window, ignoring no-op calls with the same dimensions.
    ///
    /// Each `ControlModePaneDelegate.sizeChanged` fires when any individual pane is
    /// laid out, so several delegates call this per render pass. Deduplication here
    /// ensures we send at most one `refresh-client` per unique window size, preventing
    /// the %layout-change → sizeChanged → refresh-client → %layout-change loop.
    public func sendClientResize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        guard cols != lastClientCols || rows != lastClientRows else { return }
        lastClientCols = cols
        lastClientRows = rows
        hasReceivedClientResize = true
        sendCommand("refresh-client -C \(cols)x\(rows)")
    }

    // MARK: - Commands

    /// Send a command to tmux
    public func sendCommand(_ command: String) {
        guard let inputPipe = inputPipe else { return }

        let commandWithNewline = command + "\n"
        if let data = commandWithNewline.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
    }

    /// Send a command and wait for response
    public func sendCommandAndWait(_ command: String, timeout: TimeInterval = 5.0) async -> String? {
        let (cmd, id) = parser.prepareCommand(command)
        sendCommand(cmd)

        if let response = await parser.awaitResponse(for: id, timeout: timeout) {
            return response.output
        }
        return nil
    }

    /// Send input data to a specific pane via send-keys -H (hex encoding)
    /// This is the correct way to send keystrokes in control mode - raw bytes
    /// on stdin are interpreted as tmux commands, not shell input.
    public func sendInputToPane(_ data: Data, paneId: String) {
        let hexString = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        sendCommand("send-keys -H -t %\(paneId) \(hexString)")
    }

    // MARK: - Pane Operations

    /// Split the active pane horizontally
    public func splitHorizontal() {
        sendCommand("split-window -v")
    }

    /// Split the active pane vertically
    public func splitVertical() {
        sendCommand("split-window -h")
    }

    /// Select a pane by direction
    public func selectPane(direction: PaneDirection) {
        let flag: String
        switch direction {
        case .up: flag = "-U"
        case .down: flag = "-D"
        case .left: flag = "-L"
        case .right: flag = "-R"
        }
        sendCommand("select-pane \(flag)")
    }

    /// Close the active pane
    public func closePane() {
        sendCommand("kill-pane")
    }

    /// Toggle pane zoom
    public func toggleZoom() {
        sendCommand("resize-pane -Z")
    }

    /// Refresh pane layout information
    public func refreshLayout() {
        sendCommand("display-message -p '#{window_layout}'")
    }

    /// Resize the active pane
    public func resizePane(direction: PaneDirection, cells: Int = 5) {
        let flag: String
        switch direction {
        case .up: flag = "-U"
        case .down: flag = "-D"
        case .left: flag = "-L"
        case .right: flag = "-R"
        }
        sendCommand("resize-pane \(flag) \(cells)")
    }

    /// Swap the active pane with an adjacent pane
    public func swapPane(direction: PaneDirection) {
        let flag: String
        switch direction {
        case .up: flag = "-U"
        case .down: flag = "-D"
        case .left: flag = "-L"
        case .right: flag = "-R"
        }
        sendCommand("swap-pane \(flag)")
    }

    /// Select a specific pane by ID
    public func selectPane(id: String) {
        sendCommand("select-pane -t %\(id)")
    }

    /// Break the active pane out to a new window
    public func breakPane() {
        sendCommand("break-pane")
    }

    /// Join a pane from another window
    public func joinPane(fromWindowId: String, paneId: String) {
        sendCommand("join-pane -s @\(fromWindowId).%\(paneId)")
    }

    // MARK: - Window Operations

    /// Create a new window
    public func newWindow(name: String? = nil) {
        if let name = name {
            sendCommand("new-window -n '\(name)'")
        } else {
            sendCommand("new-window")
        }
    }

    /// Select a window by ID
    public func selectWindow(id: String) {
        sendCommand("select-window -t @\(id)")
    }

    /// Rename a window
    public func renameWindow(id: String? = nil, name: String) {
        if let id = id {
            sendCommand("rename-window -t @\(id) '\(name)'")
        } else {
            sendCommand("rename-window '\(name)'")
        }
    }

    /// Close a window
    public func closeWindow(id: String? = nil) {
        if let id = id {
            sendCommand("kill-window -t @\(id)")
        } else {
            sendCommand("kill-window")
        }
    }

    /// Navigate to the next window
    public func nextWindow() {
        sendCommand("next-window")
    }

    /// Navigate to the previous window
    public func previousWindow() {
        sendCommand("previous-window")
    }

    // MARK: - Private

    private func setupParserCallbacks() {
        parser.onPaneOutput = { [weak self] paneId, data in
            self?.onPaneOutput?(paneId, data)
        }

        parser.onLayoutChange = { [weak self] _, _ in
            self?.sendCommand(
                "list-panes -F '#{pane_id} #{pane_width} #{pane_height} #{pane_left} #{pane_top} #{pane_active}'")

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                self?.panes = self?.parser.panes ?? []
            }
        }

        parser.onWindowAdd = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.windows = self?.parser.windows ?? []
            }
        }

        parser.onWindowClose = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.windows = self?.parser.windows ?? []
            }
        }

        parser.onSessionChange = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.isConnected = true
            }
        }

        parser.onExit = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isConnected = false
            }
        }

        parser.onPausePane = { [weak self] paneId in
            TermQLogger.tmux.info("onPausePane pane=\(paneId) — sending refresh-client -A continue")
            self?.sendCommand("refresh-client -A %\(paneId):continue")
        }
    }
}
