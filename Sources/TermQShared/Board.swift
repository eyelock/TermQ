import Foundation

/// Represents the entire board state (shared across CLI and MCP)
public struct Board: Codable, Sendable {
    public let columns: [Column]
    public let cards: [Card]

    public init(columns: [Column], cards: [Card]) {
        self.columns = columns
        self.cards = cards
    }

    /// All active (non-deleted) cards
    public var activeCards: [Card] {
        cards.filter { !$0.isDeleted }
    }

    /// Get column name for a column ID
    public func columnName(for columnId: UUID) -> String {
        columns.first { $0.id == columnId }?.name ?? "Unknown"
    }

    /// Get columns sorted by order index
    public func sortedColumns() -> [Column] {
        columns.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Find a terminal by identifier (UUID, name, or path)
    public func findTerminal(identifier: String) -> Card? {
        // Try as UUID first
        if let uuid = UUID(uuidString: identifier) {
            if let card = activeCards.first(where: { $0.id == uuid }) {
                return card
            }
        }

        // Try as exact name (case-insensitive)
        let identifierLower = identifier.lowercased()
        if let card = activeCards.first(where: { $0.title.lowercased() == identifierLower }) {
            return card
        }

        // Try as path (exact match or ends with)
        let normalizedPath =
            identifier.hasSuffix("/")
            ? String(identifier.dropLast())
            : identifier
        if let card = activeCards.first(where: { card in
            card.workingDirectory == normalizedPath
                || card.workingDirectory == identifier
                || card.workingDirectory.hasSuffix("/\(normalizedPath)")
        }) {
            return card
        }

        // Try as partial name match
        if let card = activeCards.first(where: { $0.title.lowercased().contains(identifierLower) }) {
            return card
        }

        return nil
    }
}
