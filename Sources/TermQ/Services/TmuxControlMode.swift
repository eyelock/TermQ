import Foundation
import TermQCore

/// Parses tmux control mode (-CC) output for advanced integration
///
/// tmux control mode sends structured notifications prefixed with `%`:
/// - `%begin <timestamp> <number> <flags>` - Start of command output
/// - `%end <timestamp> <number> <flags>` - End of command output
/// - `%output <pane-id> <data>` - Pane output data (escaped)
/// - `%extended-output <pane-id> <age-ms> : <data>` - Pane output when pause-after is active
/// - `%pause <pane-id>` - Pane output paused due to backpressure; client must send refresh-client -A
/// - `%continue <pane-id>` - Pane output resumed after client acknowledgment
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

    /// Called when a pane is paused due to output backpressure (pane_id)
    /// The receiver must respond with `refresh-client -A %<pane-id>:continue`
    public var onPausePane: ((String) -> Void)?

    // MARK: - Private State

    /// Buffer for accumulating partial lines
    private var lineBuffer: String = ""

    /// Buffer for accumulating partial UTF-8 sequences split across pipe reads
    private var rawBuffer: Data = Data()

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
        rawBuffer.append(contentsOf: data)

        // Split on 0x0A (newline) at the raw byte level.
        //
        // tmux control mode uses 0x0A exclusively as a protocol line terminator.
        // Data content newlines are octal-encoded as \012, so a literal 0x0A byte
        // is always a line boundary and never appears inside a data value.
        //
        // Processing lines at the byte level avoids a class of UTF-8 decode bugs:
        // when %extended-output data sections contain multi-byte UTF-8 sequences
        // (e.g., box-drawing chars like ─ = 0xE2 0x94 0x80), tmux may split them
        // across consecutive %extended-output lines — the lead byte ends one line
        // and the continuation bytes start the next.  Decoding the entire buffer
        // as UTF-8 before splitting on newlines causes those boundary sequences to
        // be mangled or dropped.  By splitting first and routing output lines to a
        // byte-level decoder, the bytes are passed to SwiftTerm intact.
        while let nlIdx = rawBuffer.firstIndex(of: 0x0A) {
            let lineBytes = Data(rawBuffer[rawBuffer.startIndex..<nlIdx])
            rawBuffer = Data(rawBuffer[rawBuffer.index(after: nlIdx)...])
            processRawLine(lineBytes)
        }
        // Remaining bytes are a partial line — held in rawBuffer until \n arrives.
    }

    // Routes one complete raw protocol line to the appropriate handler.
    private func processRawLine(_ lineBytes: Data) {
        guard !lineBytes.isEmpty else { return }

        // %output and %extended-output carry raw terminal bytes (including multi-byte
        // UTF-8 sequences) that must NOT pass through a UTF-8 decode/re-encode cycle.
        let outputPrefix = Array("%output ".utf8)
        let extOutputPrefix = Array("%extended-output ".utf8)
        if lineBytes.starts(with: outputPrefix) || lineBytes.starts(with: extOutputPrefix) {
            processRawOutputLine(lineBytes)
            return
        }

        // All other protocol lines are pure ASCII — UTF-8 decode is always safe.
        let line = String(data: lineBytes, encoding: .utf8) ?? ""
        parseLine(line)
    }

    // Decodes one %output or %extended-output line entirely at the byte level,
    // extracting the data section without any UTF-8 decode/re-encode.
    private func processRawOutputLine(_ lineBytes: Data) {
        var pos = lineBytes.startIndex

        // Skip '%'
        guard pos < lineBytes.endIndex, lineBytes[pos] == 0x25 else { return }
        pos = lineBytes.index(after: pos)

        // Read keyword (output or extended-output)
        let kwStart = pos
        while pos < lineBytes.endIndex && lineBytes[pos] != 0x20 {
            pos = lineBytes.index(after: pos)
        }
        let isExtended = lineBytes[kwStart..<pos].elementsEqual("extended-output".utf8)

        // Skip space after keyword
        guard pos < lineBytes.endIndex, lineBytes[pos] == 0x20 else { return }
        pos = lineBytes.index(after: pos)

        // Read pane ID token (e.g., "%86")
        let paneStart = pos
        while pos < lineBytes.endIndex && lineBytes[pos] != 0x20 {
            pos = lineBytes.index(after: pos)
        }
        var paneId = String(bytes: Data(lineBytes[paneStart..<pos]), encoding: .ascii) ?? ""
        if paneId.hasPrefix("%") { paneId = String(paneId.dropFirst()) }
        guard !paneId.isEmpty else { return }

        // Skip space after pane ID
        guard pos < lineBytes.endIndex, lineBytes[pos] == 0x20 else { return }
        pos = lineBytes.index(after: pos)

        let dataSectionBytes: Data
        if isExtended {
            // %extended-output format: "<age-ms> [reserved...] : <data>"
            // Find " : " separator (space-colon-space) to locate the data start.
            let sep = Data([0x20, 0x3A, 0x20])
            guard let sepRange = lineBytes.range(of: sep, options: [], in: pos..<lineBytes.endIndex)
            else {
                TermQLogger.tmux.warning("ext-output pane=\(paneId) — no ' : ' separator")
                return
            }
            dataSectionBytes = Data(lineBytes[sepRange.upperBound...])
        } else {
            dataSectionBytes = Data(lineBytes[pos...])
        }

        let decoded = decodeTmuxOutputBytes(dataSectionBytes)
        TermQLogger.tmux.debug("ext-output pane=\(paneId) len=\(decoded.count)")
        let filtered = filterForSwiftTerm(decoded)
        if !filtered.isEmpty {
            onPaneOutput?(paneId, filtered)
        }
    }

    /// Decode tmux control mode output escaping directly from raw bytes.
    ///
    /// tmux encodes pane output as follows (control.c `control_write_data`):
    /// - Backslash → `\\` (0x5C 0x5C)
    /// - Non-printable bytes (< 0x20 or 0x7F) → `\NNN` (backslash + 3 octal digits)
    /// - All other bytes (0x20–0x7E, 0x80–0xFE) → passed through as-is
    ///
    /// Operating at the byte level preserves multi-byte UTF-8 sequences verbatim —
    /// SwiftTerm's feed() handles UTF-8 assembly internally.
    private func decodeTmuxOutputBytes(_ data: Data) -> Data {
        var result = Data()
        result.reserveCapacity(data.count)
        var i = data.startIndex

        while i < data.endIndex {
            let b = data[i]
            if b == 0x5C {  // backslash
                let ni = data.index(after: i)
                guard ni < data.endIndex else {
                    result.append(0x5C)
                    break
                }
                let nb = data[ni]
                if nb == 0x5C {  // \\ → single backslash
                    result.append(0x5C)
                    i = data.index(after: ni)
                } else if nb >= 0x30 && nb <= 0x37 {  // \NNN octal (tmux always writes 3 digits)
                    var val: UInt16 = 0
                    var si = ni
                    var digits = 0
                    while si < data.endIndex && digits < 3 {
                        let db = data[si]
                        guard db >= 0x30 && db <= 0x37 else { break }
                        val = val * 8 + UInt16(db - 0x30)
                        si = data.index(after: si)
                        digits += 1
                    }
                    if digits == 3 {
                        result.append(UInt8(val & 0xFF))
                        i = si
                    } else {
                        result.append(0x5C)
                        i = ni
                    }
                } else {
                    result.append(0x5C)
                    i = ni
                }
            } else {
                result.append(b)
                i = data.index(after: i)
            }
        }

        return result
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
        rawBuffer = Data()
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
        // When inside a command response block (%begin...%end), most lines are command
        // output (e.g. "%0 80 24 0 0 1" from list-panes). However, tmux can interleave
        // pane output notifications (%output) within a command response — this happens
        // because every send-keys command generates a %begin/%end pair while the shell
        // simultaneously echoes the key via %output. We must pass %output through
        // immediately; other notifications that could trigger new commands (e.g.
        // %layout-change → list-panes) are deferred until the block closes to avoid
        // nested %begin/%end which our single-response tracker cannot handle.
        if currentResponse != nil {
            if line.hasPrefix("%begin") || line.hasPrefix("%end") {
                parseControlLine(line)
            } else if line.hasPrefix("%output ") || line.hasPrefix("%extended-output ")
                || line.hasPrefix("%pause ") || line.hasPrefix("%continue ")
            {
                // Pane output / backpressure notifications interleaved with a command response
                parseControlLine(line)
            } else {
                // Non-output lines accumulated as command output
                if line.hasPrefix("%") {
                    TermQLogger.tmux.warning(
                        "parseLine absorbing pct-line inside block: \(String(line.prefix(40)))"
                    )
                }
                currentResponse?.output.append(line + "\n")
                parseListPanesLine(line)
            }
        } else if line.hasPrefix("%") {
            parseControlLine(line)
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

        case "extended-output":
            handleExtendedOutput(parts)

        case "pause":
            handlePause(parts)

        case "continue":
            handleContinue(parts)

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
        if let data = decodeTmuxOutput(escapedData) {
            onPaneOutput?(paneId, filterForSwiftTerm(data))
        }
    }

    private func handleExtendedOutput(_ parts: [String.SubSequence]) {
        guard parts.count >= 3 else { return }

        let paneIdPart = String(parts[1])
        let paneId = paneIdPart.hasPrefix("%") ? String(paneIdPart.dropFirst()) : paneIdPart

        // Format: "<age-ms> [reserved...] : <escaped-data>" — split on " : " to isolate data
        let remainder = String(parts[2])
        guard let separatorRange = remainder.range(of: " : ") else {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.io.warning(
                    "ext-output pane=\(paneId) — no ' : ' separator in: \(remainder.prefix(40))")
            }
            return
        }
        let escapedData = String(remainder[separatorRange.upperBound...])

        if let data = decodeTmuxOutput(escapedData) {
            TermQLogger.tmux.debug("ext-output pane=\(paneId) len=\(data.count)")
            onPaneOutput?(paneId, filterForSwiftTerm(data))
        }
    }

    private func handlePause(_ parts: [String.SubSequence]) {
        guard parts.count >= 2 else { return }
        let paneIdPart = String(parts[1])
        let paneId = paneIdPart.hasPrefix("%") ? String(paneIdPart.dropFirst()) : paneIdPart
        TermQLogger.tmux.info("pause pane=\(paneId) — sending continue")
        onPausePane?(paneId)
    }

    private func handleContinue(_ parts: [String.SubSequence]) {
        let raw = parts.count >= 2 ? String(parts[1]) : "?"
        let paneId = raw.hasPrefix("%") ? String(raw.dropFirst()) : raw
        TermQLogger.tmux.info("continue pane=\(paneId) — output resuming via ext-output")
    }

    /// Filter tmux-specific escape sequences that SwiftTerm does not support.
    ///
    /// The tmux/screen window-title sequence `ESC k <name> ESC \` is forwarded
    /// verbatim in `%output` notifications. SwiftTerm treats `ESC k` as an
    /// unknown 2-character escape — consuming only those two bytes — so the title
    /// text ("echo", "mkdir", etc.) is rendered as literal characters. This makes
    /// every command's output appear prepended with the command name, e.g.
    /// `echo hello` → `echohello` instead of `hello`.
    ///
    /// This function strips `ESC k ... ESC \` (and the BEL-terminated variant)
    /// before the bytes reach SwiftTerm.
    private func filterForSwiftTerm(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var result = [UInt8]()
        result.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            // ESC k — tmux/screen window-title sequence (not a standard xterm sequence)
            if bytes[i] == 0x1B, i + 1 < bytes.count, bytes[i + 1] == 0x6B {
                i += 2  // skip ESC k
                // Consume title text until String Terminator (ESC \) or BEL
                while i < bytes.count {
                    if bytes[i] == 0x07 {
                        i += 1
                        break  // BEL terminates
                    }
                    if bytes[i] == 0x1B, i + 1 < bytes.count, bytes[i + 1] == 0x5C {
                        i += 2
                        break  // ESC \ terminates
                    }
                    i += 1
                }
            } else {
                result.append(bytes[i])
                i += 1
            }
        }
        return Data(result)
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

    /// Decode tmux control mode output escaping from %output notifications.
    ///
    /// tmux encodes pane output as follows (control.c `control_write_data`):
    /// - Backslash → `\\`
    /// - Non-printable bytes (< 0x20 or 0x7f) → `\NNN` (3-digit zero-padded octal)
    /// - All other bytes → passed through as-is (including UTF-8 multi-byte sequences)
    ///
    /// ESC (0x1b = 033 octal) arrives as the four characters `\033`, not as `%1b`.
    private func decodeTmuxOutput(_ string: String) -> Data? {
        var result = Data()
        var index = string.startIndex

        while index < string.endIndex {
            let char = string[index]

            if char == "\\" {
                let afterBackslash = string.index(after: index)
                guard afterBackslash < string.endIndex else {
                    result.append(0x5c)  // trailing lone backslash
                    break
                }
                let nextChar = string[afterBackslash]
                if nextChar == "\\" {
                    // Escaped backslash → single backslash byte
                    result.append(0x5c)
                    index = string.index(after: afterBackslash)
                } else if nextChar >= "0" && nextChar <= "7" {
                    // Octal escape \NNN — tmux always writes exactly 3 digits
                    var octalStr = ""
                    var octalIndex = afterBackslash
                    for _ in 0..<3 {
                        guard octalIndex < string.endIndex else { break }
                        let c = string[octalIndex]
                        guard c >= "0" && c <= "7" else { break }
                        octalStr.append(c)
                        octalIndex = string.index(after: octalIndex)
                    }
                    if let value = UInt8(octalStr, radix: 8) {
                        result.append(value)
                    }
                    index = octalIndex
                } else {
                    // Unknown escape — pass backslash through and continue
                    result.append(0x5c)
                    index = afterBackslash
                }
            } else if let data = String(char).data(using: .utf8) {
                result.append(data)
                index = string.index(after: index)
            } else {
                index = string.index(after: index)
            }
        }

        return result
    }
}
