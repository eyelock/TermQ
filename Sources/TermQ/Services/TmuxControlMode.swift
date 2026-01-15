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
        // Append to buffer and process complete lines
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
        // Control mode lines start with %
        if line.hasPrefix("%") {
            parseControlLine(line)
        } else if currentResponse != nil {
            // We're inside a command response - accumulate output
            currentResponse?.output.append(line + "\n")
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
            // Unknown control message - log for debugging
            print("TmuxControlMode: Unknown control message: \(command)")
        }
    }

    // MARK: - Control Message Handlers

    private func handleBegin(_ parts: [String.SubSequence]) {
        // %begin <timestamp> <number> <flags>
        guard parts.count >= 3,
            let commandId = Int(parts[2])
        else {
            return
        }

        currentResponse = CommandResponse(id: commandId)
    }

    private func handleEnd(_ parts: [String.SubSequence]) {
        // %end <timestamp> <number> <flags>
        guard parts.count >= 3,
            let commandId = Int(parts[2])
        else {
            return
        }

        if var response = currentResponse, response.id == commandId {
            response.isComplete = true
            pendingCommands[commandId] = response
            currentResponse = nil
        }
    }

    private func handleOutput(_ parts: [String.SubSequence]) {
        // %output %<pane-id> <escaped-data>
        guard parts.count >= 2 else { return }

        let paneIdPart = String(parts[1])
        let paneId = paneIdPart.hasPrefix("%") ? String(paneIdPart.dropFirst()) : paneIdPart

        // Data is URL-encoded (percent-escaped)
        let escapedData = parts.count > 2 ? String(parts[2]) : ""
        if let data = decodePercentEscaped(escapedData) {
            onPaneOutput?(paneId, data)
        }
    }

    private func handleLayoutChange(_ parts: [String.SubSequence]) {
        // %layout-change @<window-id> <layout>
        guard parts.count >= 3 else { return }

        let windowIdPart = String(parts[1])
        let windowId = windowIdPart.hasPrefix("@") ? String(windowIdPart.dropFirst()) : windowIdPart
        let layout = String(parts[2])

        currentLayout = layout
        parseLayoutString(layout)
        onLayoutChange?(windowId, layout)
    }

    private func handleWindowAdd(_ parts: [String.SubSequence]) {
        // %window-add @<window-id>
        guard parts.count >= 2 else { return }

        let windowIdPart = String(parts[1])
        let windowId = windowIdPart.hasPrefix("@") ? String(windowIdPart.dropFirst()) : windowIdPart

        if !windows.contains(where: { $0.id == windowId }) {
            windows.append(TmuxWindow(id: windowId, name: "Window \(windowId)"))
        }

        onWindowAdd?(windowId)
    }

    private func handleWindowClose(_ parts: [String.SubSequence]) {
        // %window-close @<window-id>
        guard parts.count >= 2 else { return }

        let windowIdPart = String(parts[1])
        let windowId = windowIdPart.hasPrefix("@") ? String(windowIdPart.dropFirst()) : windowIdPart

        windows.removeAll { $0.id == windowId }
        // Also remove panes belonging to this window
        panes.removeAll { $0.windowId == windowId }

        onWindowClose?(windowId)
    }

    private func handleSessionChanged(_ parts: [String.SubSequence]) {
        // %session-changed $<session-id> <name>
        guard parts.count >= 3 else { return }

        let sessionIdPart = String(parts[1])
        let sessionId = sessionIdPart.hasPrefix("$") ? String(sessionIdPart.dropFirst()) : sessionIdPart
        let name = String(parts[2])

        isConnected = true
        onSessionChange?(sessionId, name)
    }

    private func handlePaneModeChanged(_ parts: [String.SubSequence]) {
        // %pane-mode-changed %<pane-id>
        guard parts.count >= 2 else { return }

        let paneIdPart = String(parts[1])
        let paneId = paneIdPart.hasPrefix("%") ? String(paneIdPart.dropFirst()) : paneIdPart

        // Update pane mode if we're tracking it
        if let index = panes.firstIndex(where: { $0.id == paneId }) {
            panes[index].inCopyMode.toggle()
        }
    }

    private func handleExit(_ parts: [String.SubSequence]) {
        // %exit [reason]
        let reason = parts.count > 1 ? String(parts[1]) : nil
        isConnected = false
        onExit?(reason)
    }

    // MARK: - Layout Parsing

    /// Parse a tmux layout string into pane structures
    /// Format: WIDTHxHEIGHT,X,Y[{children}]
    /// Example: "177x42,0,0{88x42,0,0,0,88x42,89,0,1}"
    private func parseLayoutString(_ layout: String) {
        // This is a simplified parser - full layout parsing is complex
        // For now, we extract basic pane information

        var newPanes: [TmuxPane] = []

        // Find all pane IDs in the layout (comma-separated numbers at leaf nodes)
        let panePattern = /,(\d+)(?:,|$|\})/
        let matches = layout.matches(of: panePattern)

        for match in matches {
            let paneId = String(match.output.1)
            if !newPanes.contains(where: { $0.id == paneId }) {
                newPanes.append(
                    TmuxPane(
                        id: paneId,
                        windowId: "",  // Would need more context to set
                        width: 0,
                        height: 0,
                        x: 0,
                        y: 0
                    ))
            }
        }

        // Only update if we found panes
        if !newPanes.isEmpty {
            panes = newPanes
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
                // Percent-encoded byte
                let nextIndex = string.index(index, offsetBy: 2, limitedBy: string.endIndex)
                guard let next = nextIndex else { break }

                let hexString = String(string[string.index(after: index)..<next])
                if let byte = UInt8(hexString, radix: 16) {
                    result.append(byte)
                    index = next
                    continue
                }
            }

            // Regular character
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
    public func connect() async throws {
        guard let tmuxPath = TmuxManager.shared.tmuxPath else {
            throw TmuxError.notAvailable
        }

        // Create pipes for I/O
        let output = Pipe()
        let input = Pipe()
        self.outputPipe = output
        self.inputPipe = input

        // Set up process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmuxPath)
        proc.arguments = ["-CC", "attach-session", "-t", sessionName]
        proc.standardOutput = output
        proc.standardInput = input

        // Handle output asynchronously
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            Task { @MainActor [weak self] in
                self?.parser.parse(data)
            }
        }

        // Start the process
        try proc.run()
        self.process = proc

        // Wait for connection confirmation
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        isConnected = parser.isConnected
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

        parser.onLayoutChange = { [weak self] windowId, layout in
            Task { @MainActor [weak self] in
                self?.panes = self?.parser.panes ?? []
            }
        }

        parser.onWindowAdd = { [weak self] windowId in
            Task { @MainActor [weak self] in
                self?.windows = self?.parser.windows ?? []
            }
        }

        parser.onWindowClose = { [weak self] windowId in
            Task { @MainActor [weak self] in
                self?.windows = self?.parser.windows ?? []
            }
        }

        parser.onSessionChange = { [weak self] sessionId, name in
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
