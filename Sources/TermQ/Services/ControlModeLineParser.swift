import Foundation

/// Structured result of parsing a single tmux control mode output line.
enum ControlModeEvent {
    case begin(commandId: Int)
    case end(commandId: Int)
    /// `paneId` has the `%` sigil stripped; `escapedData` is raw tmux backslash-octal encoding.
    case output(paneId: String, escapedData: String)
    /// Same encoding as `.output`; age field is consumed during parsing.
    case extendedOutput(paneId: String, escapedData: String)
    case pause(paneId: String)
    case `continue`(paneId: String)
    case layoutChange(windowId: String, layout: String)
    case windowAdd(windowId: String)
    case windowClose(windowId: String)
    case sessionChanged(sessionId: String, name: String)
    case paneModeChanged(paneId: String)
    case exit(reason: String?)
    case unknown(line: String)
}

/// Pure, synchronous parser for individual tmux control mode output lines.
/// No actor isolation, no callbacks, no SwiftTerm dependency.
struct ControlModeLineParser {

    func parse(_ line: String) -> ControlModeEvent {
        guard line.hasPrefix("%") else { return .unknown(line: line) }

        let parts = line.dropFirst().split(
            separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return .unknown(line: line) }

        let command = String(parts[0])

        switch command {
        case "begin":
            return parseCommandId(parts).map { .begin(commandId: $0) }
                ?? .unknown(line: line)
        case "end":
            return parseCommandId(parts).map { .end(commandId: $0) }
                ?? .unknown(line: line)
        case "output":
            return parseOutput(parts, line: line)
        case "extended-output":
            return parseExtendedOutput(parts, line: line)
        case "pause":
            return parsePaneId(parts).map { .pause(paneId: $0) }
                ?? .unknown(line: line)
        case "continue":
            let raw = parts.count >= 2 ? String(parts[1]) : "?"
            return .continue(paneId: stripSigil(raw, sigil: "%"))
        case "layout-change":
            return parseLayoutChange(parts, line: line)
        case "window-add":
            return parseWindowId(parts).map { .windowAdd(windowId: $0) }
                ?? .unknown(line: line)
        case "window-close":
            return parseWindowId(parts).map { .windowClose(windowId: $0) }
                ?? .unknown(line: line)
        case "session-changed":
            return parseSessionChanged(parts, line: line)
        case "pane-mode-changed":
            return parsePaneId(parts).map { .paneModeChanged(paneId: $0) }
                ?? .unknown(line: line)
        case "exit":
            let reason = parts.count > 1 ? String(parts[1]) : nil
            return .exit(reason: reason)
        default:
            return .unknown(line: line)
        }
    }

    // MARK: - Private parsers

    private func parseCommandId(_ parts: [String.SubSequence]) -> Int? {
        guard parts.count >= 3 else { return nil }
        let numberPart = parts[2].split(separator: " ").first ?? parts[2]
        return Int(numberPart)
    }

    private func parseOutput(_ parts: [String.SubSequence], line: String) -> ControlModeEvent {
        guard parts.count >= 2 else { return .unknown(line: line) }
        let paneId = stripSigil(String(parts[1]), sigil: "%")
        let escapedData = parts.count > 2 ? String(parts[2]) : ""
        return .output(paneId: paneId, escapedData: escapedData)
    }

    private func parseExtendedOutput(_ parts: [String.SubSequence], line: String) -> ControlModeEvent {
        guard parts.count >= 3 else { return .unknown(line: line) }
        let paneId = stripSigil(String(parts[1]), sigil: "%")
        let remainder = String(parts[2])
        guard let separatorRange = remainder.range(of: " : ") else {
            return .unknown(line: line)
        }
        let escapedData = String(remainder[separatorRange.upperBound...])
        return .extendedOutput(paneId: paneId, escapedData: escapedData)
    }

    private func parseLayoutChange(_ parts: [String.SubSequence], line: String) -> ControlModeEvent {
        guard parts.count >= 3 else { return .unknown(line: line) }
        let windowId = stripSigil(String(parts[1]), sigil: "@")
        let layout = String(parts[2])
        return .layoutChange(windowId: windowId, layout: layout)
    }

    private func parseSessionChanged(_ parts: [String.SubSequence], line: String) -> ControlModeEvent {
        guard parts.count >= 3 else { return .unknown(line: line) }
        let sessionId = stripSigil(String(parts[1]), sigil: "$")
        let name = String(parts[2])
        return .sessionChanged(sessionId: sessionId, name: name)
    }

    private func parsePaneId(_ parts: [String.SubSequence]) -> String? {
        guard parts.count >= 2 else { return nil }
        return stripSigil(String(parts[1]), sigil: "%")
    }

    private func parseWindowId(_ parts: [String.SubSequence]) -> String? {
        guard parts.count >= 2 else { return nil }
        return stripSigil(String(parts[1]), sigil: "@")
    }

    private func stripSigil(_ value: String, sigil: String) -> String {
        value.hasPrefix(sigil) ? String(value.dropFirst()) : value
    }
}
