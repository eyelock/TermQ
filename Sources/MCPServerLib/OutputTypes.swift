import Foundation

// MARK: - JSON Output Types for MCP

/// Standard terminal output format
struct TerminalOutput: Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let column: String
    let columnId: String
    let tags: [String: String]
    let path: String
    let badges: [String]
    let isFavourite: Bool
    let llmPrompt: String
    let llmNextAction: String

    init(from card: MCPCard, columnName: String) {
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
    }
}

/// Column output format
struct ColumnOutput: Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let color: String
    let terminalCount: Int

    init(from column: MCPColumn, terminalCount: Int) {
        self.id = column.id.uuidString
        self.name = column.name
        self.description = column.description
        self.color = column.color
        self.terminalCount = terminalCount
    }
}

/// Pending terminal output format
struct PendingTerminalOutput: Codable, Sendable {
    let id: String
    let name: String
    let column: String
    let path: String
    let llmNextAction: String
    let llmPrompt: String
    let staleness: String
    let tags: [String: String]

    init(from card: MCPCard, columnName: String, staleness: String) {
        self.id = card.id.uuidString
        self.name = card.title
        self.column = columnName
        self.path = card.workingDirectory
        self.llmNextAction = card.llmNextAction
        self.llmPrompt = card.llmPrompt
        self.staleness = staleness
        self.tags = card.tagsDictionary
    }
}

/// Pending summary output format
struct PendingSummary: Codable, Sendable {
    let total: Int
    let withNextAction: Int
    let stale: Int
    let fresh: Int
}

/// Complete pending output format
struct PendingOutput: Codable, Sendable {
    let terminals: [PendingTerminalOutput]
    let summary: PendingSummary
}

/// Error output format
struct ErrorOutput: Codable, Sendable {
    let error: String
    let code: Int
}

// MARK: - JSON Encoding Helper

enum JSONHelper {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Staleness Calculation

extension MCPCard {
    /// Get staleness value from tags
    var staleness: String {
        if let stalenessTag = tags.first(where: { $0.key.lowercased() == "staleness" }) {
            return stalenessTag.value.lowercased()
        }
        return "unknown"
    }

    /// Get staleness rank for sorting (higher = needs more attention)
    var stalenessRank: Int {
        switch staleness {
        case "stale", "old":
            return 3
        case "ageing":
            return 2
        case "fresh":
            return 1
        default:
            return 0
        }
    }
}
