import Foundation

/// Common errors for CLI and MCP operations
public enum TermQError: Error, LocalizedError, Sendable {
    case boardNotFound(path: String)
    case columnNotFound(name: String)
    case terminalNotFound(identifier: String)

    public var errorDescription: String? {
        switch self {
        case .boardNotFound(let path):
            return "Board file not found at: \(path). Is TermQ installed and has been run at least once?"
        case .columnNotFound(let name):
            return "Column not found: \(name)"
        case .terminalNotFound(let identifier):
            return "Terminal not found: \(identifier)"
        }
    }
}
