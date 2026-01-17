import Foundation

// MARK: - JSON Output Types (shared across CLI and MCP)

/// Standard terminal output format
public struct TerminalOutput: Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let column: String
    public let columnId: String
    public let tags: [String: String]
    public let path: String
    public let badges: [String]
    public let isFavourite: Bool
    public let llmPrompt: String
    public let llmNextAction: String
    public let allowAutorun: Bool

    public init(from card: Card, columnName: String) {
        self.id = card.id.uuidString
        self.name = card.title
        self.description = card.description
        self.column = columnName
        self.columnId = card.columnId.uuidString
        self.tags = card.tagsDictionary
        self.path = card.workingDirectory
        self.badges = card.badges
        self.isFavourite = card.isFavourite
        self.llmPrompt = card.llmPrompt
        self.llmNextAction = card.llmNextAction
        self.allowAutorun = card.allowAutorun
    }
}

/// Column output format
public struct ColumnOutput: Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let color: String
    public let terminalCount: Int

    public init(from column: Column, terminalCount: Int) {
        self.id = column.id.uuidString
        self.name = column.name
        self.description = column.description
        self.color = column.color
        self.terminalCount = terminalCount
    }
}

/// Pending terminal output format
public struct PendingTerminalOutput: Codable, Sendable {
    public let id: String
    public let name: String
    public let column: String
    public let path: String
    public let llmNextAction: String
    public let llmPrompt: String
    public let allowAutorun: Bool
    public let staleness: String
    public let tags: [String: String]

    public init(from card: Card, columnName: String, staleness: String) {
        self.id = card.id.uuidString
        self.name = card.title
        self.column = columnName
        self.path = card.workingDirectory
        self.llmNextAction = card.llmNextAction
        self.llmPrompt = card.llmPrompt
        self.allowAutorun = card.allowAutorun
        self.staleness = staleness
        self.tags = card.tagsDictionary
    }
}

/// Pending summary output format
public struct PendingSummary: Codable, Sendable {
    public let total: Int
    public let withNextAction: Int
    public let stale: Int
    public let fresh: Int

    public init(total: Int, withNextAction: Int, stale: Int, fresh: Int) {
        self.total = total
        self.withNextAction = withNextAction
        self.stale = stale
        self.fresh = fresh
    }
}

/// Complete pending output format
public struct PendingOutput: Codable, Sendable {
    public let terminals: [PendingTerminalOutput]
    public let summary: PendingSummary

    public init(terminals: [PendingTerminalOutput], summary: PendingSummary) {
        self.terminals = terminals
        self.summary = summary
    }
}

/// Error output format
public struct ErrorOutput: Codable, Sendable {
    public let error: String
    public let code: Int

    public init(error: String, code: Int) {
        self.error = error
        self.code = code
    }
}

/// Success response for set command
public struct SetResponse: Codable, Sendable {
    public let success: Bool
    public let id: String

    public init(success: Bool, id: String) {
        self.success = success
        self.id = id
    }
}

/// Success response for move command
public struct MoveResponse: Codable, Sendable {
    public let success: Bool
    public let id: String
    public let column: String

    public init(success: Bool, id: String, column: String) {
        self.success = success
        self.id = id
        self.column = column
    }
}

/// Response for pending terminal creation (when GUI hasn't processed yet)
public struct PendingCreateResponse: Codable, Sendable {
    public let id: String
    public let status: String
    public let message: String

    public init(id: String, status: String = "pending", message: String) {
        self.id = id
        self.status = status
        self.message = message
    }
}

/// Response for delete command
public struct DeleteResponse: Codable, Sendable {
    public let id: String
    public let deleted: Bool
    public let permanent: Bool

    public init(id: String, deleted: Bool = true, permanent: Bool) {
        self.id = id
        self.deleted = deleted
        self.permanent = permanent
    }
}

// MARK: - JSON Encoding Helper

public enum JSONHelper {
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value),
            let string = String(data: data, encoding: .utf8)
        {
            print(string)
        }
    }

    public static func printErrorJSON(_ message: String, code: Int = 1) {
        printJSON(ErrorOutput(error: message, code: code))
    }
}
