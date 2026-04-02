import Foundation
import TermQCore

/// Parses tmux control mode (-CC) output for advanced integration
///
/// tmux control mode sends structured notifications prefixed with `%`:
/// - `%begin <timestamp> <number> <flags>` - Start of command output
/// - `%end <timestamp> <number> <flags>` - End of command output
/// - `%output <pane-id> <data>` - Pane output data (escaped)
/// - `%pane-mode-changed <pane-id>` - Pane entered/exited mode
/// - `%window-add <window-id>` - Window created
/// - `%window-close <window-id>` - Window closed
/// - `%layout-change <window-id> <layout>` - Layout changed
/// - `%session-changed <session-id> <name>` - Active session changed
/// - `%exit [reason]` - Server is exiting
///
/// Reference: tmux(1) man page, Control Mode section
/// https://github.com/tmux/tmux/wiki/Control-Mode
@MainActor
public class TmuxControlModeParser: ObservableObject {

    // MARK: - Published State

    /// Current panes in the session
    @Published public private(set) var panes: [TmuxPane] = []

    /// Current windows in the session
    @Published public private(set) var windows: [TmuxWindow] = []

    /// Current layout description
    @Published public private(set) var currentLayout: String = ""

    /// Whether the control mode connection is active
    @Published public private(set) var isConnected: Bool = false

    /// Error from last parse operation (if any)
    @Published public private(set) var lastError: String?

    // MARK: - Callbacks

    /// Called when pane output is received (pane_id, output data)
    public var onPaneOutput: ((String, Data) -> Void)?

    /// Called when layout changes (window_id, layout string)
    public var onLayoutChange: ((String, String) -> Void)?

    /// Called when a window is added (window_id)
    public var onWindowAdd: ((String) -> Void)?

    /// Called when a window is closed (window_id)
    public var onWindowClose: ((String) -> Void)?

    /// Called when pane mode changes (pane_id) - e.g. copy mode enter/exit
    public var onPaneModeChanged: ((String) -> Void)?

    /// Called when session changes
    public var onSessionChange: ((String, String) -> Void)?

    /// Called when tmux server exits
    public var onExit: ((String?) -> Void)?

    // MARK: - Private State

    /// Buffer for accumulating partial lines
    private var lineBuffer: String = ""

    /// Pending command responses (by command ID)
    private var pendingCommands: [Int: CommandResponse] = [:]

    /// Next command ID for tracking
    private var nextCommandId: Int = 0

    /// Current command response being accumulated
    private var currentResponse: CommandResponse?

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Parse incoming data from tmux control mode
    /// Call this method with raw output from the tmux -CC process
    public func parse(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            lastError = "Failed to decode control mode data as UTF-8"
            return
        }
        parse(text)
    }

    /// Parse incoming text from tmux control mode
    public func parse(_ text: String) {
        lineBuffer += text

        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<newlineIndex])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])
            parseLine(line)
        }
    }

    /// Reset parser state
    public func reset() {
        lineBuffer = ""
        pendingCommands.removeAll()
        currentResponse = nil
        panes = []
        windows = []
        currentLayout = ""
        isConnected = false
        lastError = nil
    }

    // MARK: - Command Sending

    /// Generate a command string with tracking ID
    /// Returns the command to send and the ID to await response for
    public func prepareCommand(_ command: String) -> (command: String, id: Int) {
        let id = nextCommandId
        nextCommandId += 1
        return ("\(command)", id)
    }

    /// Wait for a command response (with timeout)
    public func awaitResponse(for id: Int, timeout: TimeInterval = 5.0) async -> CommandResponse? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let response = pendingCommands[id] {
                pendingCommands.removeValue(forKey: id)
                return response
            }
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }

        return nil
    }

    // MARK: - Private Parsing

    private func parseLine(_ line: String) {
        if line.hasPrefix("%") {
            parseControlLine(line)
        } else if currentResponse != nil {
            currentResponse?.output.append(line + "\n")
            parseListPanesLine(line)
        }
    }

    private func parseControlLine(_ line: String) {
        let parts = line.dropFirst().split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return }

        let command = String(parts[0])

        switch command {
        case "begin":
            handleBegin(parts)

        case "end":
            handleEnd(parts)

        case "output":
            handleOutput(parts)

        case "layout-change":
            handleLayoutChange(parts)

        case "window-add":
            handleWindowAdd(parts)

        case "window-close":
            handleWindowClose(parts)

        case "session-changed":
            handleSessionChanged(parts)

        case "pane-mode-changed":
            handlePaneModeChanged(parts)

        case "exit":
            handleExit(parts)

        default:
            break
        }
    }

    // MARK: - Control Message Handlers

    private func handleBegin(_ parts: [String.SubSequence]) {
        guard parts.count >= 3 else { return }

        let numberPart = parts[2].split(separator: " ").first ?? parts[2]
        guard let commandId = Int(numberPart) else { return }

        currentResponse = CommandResponse(id: commandId)
    }

    private func handleEnd(_ parts: [String.SubSequence]) {
        guard parts.count >= 3 else { return }

        let numberPart = parts[2].split(separator: " ").first ?? parts[2]
        guard let commandId = Int(numberPart) else { return }

        if var response = currentResponse, response.id == commandId {
            response.isComplete = true
            pendingCommands[commandId] = response
            currentResponse = nil
        }
    }

    private func handleOutput(_ parts: [String.SubSequence]) {
        guard parts.count >= 2 else { return }

        let paneIdPart = String(parts[1])
        let paneId = paneIdPart.hasPrefix("%") ? String(paneIdPart.dropFirst()) : paneIdPart

        let escapedData = parts.count > 2 ? String(parts[2]) : ""
        if let data = decodePercentEscaped(escapedData) {
            onPaneOutput?(paneId, data)
        }
    }

    private func handleLayoutChange(_ parts: [String.SubSequence]) {
        guard parts.count >= 3 else { return }

        let windowIdPart = String(parts[1])
        let windowId = windowIdPart.hasPrefix("@") ? String(windowIdPart.dropFirst()) : windowIdPart
        let layout = String(parts[2])

        currentLayout = layout
        onLayoutChange?(windowId, layout)
    }

    private func handleWindowAdd(_ parts: [String.SubSequence]) {
        guard parts.count >= 2 else { return }

        let windowIdPart = String(parts[1])
        let windowId = windowIdPart.hasPrefix("@") ? String(windowIdPart.dropFirst()) : windowIdPart

        if !windows.contains(where: { $0.id == windowId }) {
            windows.append(TmuxWindow(id: windowId, name: "Window \(windowId)"))
        }

        onWindowAdd?(windowId)
    }

    private func handleWindowClose(_ parts: [String.SubSequence]) {
        guard parts.count >= 2 else { return }

        let windowIdPart = String(parts[1])
        let windowId = windowIdPart.hasPrefix("@") ? String(windowIdPart.dropFirst()) : windowIdPart

        windows.removeAll { $0.id == windowId }
        panes.removeAll { $0.windowId == windowId }

        onWindowClose?(windowId)
    }

    private func handleSessionChanged(_ parts: [String.SubSequence]) {
        guard parts.count >= 3 else { return }

        let sessionIdPart = String(parts[1])
        let sessionId = sessionIdPart.hasPrefix("$") ? String(sessionIdPart.dropFirst()) : sessionIdPart
        let name = String(parts[2])

        isConnected = true
        onSessionChange?(sessionId, name)
    }

    private func handlePaneModeChanged(_ parts: [String.SubSequence]) {
        guard parts.count >= 2 else { return }

        let paneIdPart = String(parts[1])
        let paneId = paneIdPart.hasPrefix("%") ? String(paneIdPart.dropFirst()) : paneIdPart

        if let index = panes.firstIndex(where: { $0.id == paneId }) {
            panes[index].inCopyMode.toggle()
        }

        onPaneModeChanged?(paneId)
    }

    private func handleExit(_ parts: [String.SubSequence]) {
        let reason = parts.count > 1 ? String(parts[1]) : nil
        isConnected = false
        onExit?(reason)
    }

    // MARK: - Layout Parsing

    /// Parse list-panes -F output line
    /// Format from: list-panes -F '#{pane_id} #{pane_width} #{pane_height} #{pane_left} #{pane_top} #{pane_active}'
    /// Example: "%0 80 24 0 0 1" (active) or "%1 80 24 0 0 " (inactive)
    private func parseListPanesLine(_ line: String) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count >= 5,
            let first = parts.first, first.hasPrefix("%")
        else {
            return
        }

        let paneId = String(first.dropFirst())
        let width = Int(parts[1]) ?? 0
        let height = Int(parts[2]) ?? 0
        let x = Int(parts[3]) ?? 0
        let y = Int(parts[4]) ?? 0
        let isActive = parts.count > 5 && parts[5] == "1"

        if let index = panes.firstIndex(where: { $0.id == paneId }) {
            panes[index].width = width
            panes[index].height = height
            panes[index].x = x
            panes[index].y = y
            panes[index].isActive = isActive
        } else {
            var pane = TmuxPane(
                id: paneId,
                windowId: "0",
                width: width,
                height: height,
                x: x,
                y: y
            )
            pane.isActive = isActive
            panes.append(pane)
        }
    }

    // MARK: - Helpers

    /// Decode percent-escaped data from control mode output
    private func decodePercentEscaped(_ string: String) -> Data? {
        var result = Data()
        var index = string.startIndex

        while index < string.endIndex {
            let char = string[index]

            if char == "%" {
                let nextIndex = string.index(index, offsetBy: 2, limitedBy: string.endIndex)
                guard let next = nextIndex else { break }

                let hexString = String(string[string.index(after: index)..<next])
                if let byte = UInt8(hexString, radix: 16) {
                    result.append(byte)
                    index = next
                    continue
                }
            }

            if let data = String(char).data(using: .utf8) {
                result.append(data)
            }
            index = string.index(after: index)
        }

        return result
    }
}

// MARK: - Supporting Types

/// Represents a tmux pane in control mode
public struct TmuxPane: Identifiable, Sendable {
    public let id: String
    public var windowId: String
    public var width: Int
    public var height: Int
    public var x: Int
    public var y: Int
    public var title: String = ""
    public var currentPath: String = ""
    public var inCopyMode: Bool = false
    public var isActive: Bool = false

    public init(id: String, windowId: String, width: Int, height: Int, x: Int, y: Int) {
        self.id = id
        self.windowId = windowId
        self.width = width
        self.height = height
        self.x = x
        self.y = y
    }
}

/// Represents a tmux window in control mode
public struct TmuxWindow: Identifiable, Sendable {
    public let id: String
    public var name: String
    public var layout: String = ""
    public var isActive: Bool = false

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Response from a tmux control mode command
public struct CommandResponse: Sendable {
    public let id: Int
    public var output: String = ""
    public var isComplete: Bool = false

    public init(id: Int) {
        self.id = id
    }
}

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

        // Set up process - direct tmux control mode with new-session
        // Use -C (not -CC) because -CC requires TTY for termios modifications
        // See: https://github.com/tmux/tmux/issues/3085
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmuxPath)
        proc.arguments = ["-C", "new-session", "-s", sessionName]
        proc.standardOutput = output
        proc.standardInput = input
        proc.standardError = Pipe()  // Suppress stderr

        // Handle output asynchronously
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            Task { @MainActor [weak self] in
                self?.parser.parse(data)
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
            sendCommand("set-option -t \(sessionName) status off")
            sendCommand("set-option -t \(sessionName) mouse on")
            sendCommand("set-option -t \(sessionName) default-terminal 'xterm-256color'")
            sendCommand("set-option -t \(sessionName) escape-time 10")
            sendCommand("set-option -t \(sessionName) allow-passthrough off")

            // Request initial pane information
            sendCommand(
                "list-panes -F '#{pane_id} #{pane_width} #{pane_height} #{pane_left} #{pane_top} #{pane_active}'")

            // Wait for panes response
            try await Task.sleep(nanoseconds: 200_000_000)  // 200ms

            await MainActor.run {
                self.panes = parser.panes
            }
        }

        // Capture initial pane content
        await MainActor.run {
            for pane in parser.panes {
                sendCommand("capture-pane -p -t %\(pane.id)")
            }
        }
    }

    /// Disconnect from the tmux session
    public func disconnect() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
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
    }
}
