import Foundation
import TermQCore

/// Lightweight metadata structure for tmux session storage/recovery
/// Contains the essential fields that can be recovered from an orphaned session
public struct TerminalCardMetadata: Sendable {
    public let id: UUID
    public let title: String
    public let description: String
    public let tags: [Tag]
    public let llmPrompt: String
    public let llmNextAction: String
    public let badge: String
    public let columnId: UUID?
    public let isFavourite: Bool

    public init(
        id: UUID,
        title: String,
        description: String = "",
        tags: [Tag] = [],
        llmPrompt: String = "",
        llmNextAction: String = "",
        badge: String = "",
        columnId: UUID? = nil,
        isFavourite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.tags = tags
        self.llmPrompt = llmPrompt
        self.llmNextAction = llmNextAction
        self.badge = badge
        self.columnId = columnId
        self.isFavourite = isFavourite
    }

    /// Create metadata from a TerminalCard
    public static func from(_ card: TerminalCard) -> TerminalCardMetadata {
        TerminalCardMetadata(
            id: card.id,
            title: card.title,
            description: card.description,
            tags: card.tags,
            llmPrompt: card.llmPrompt,
            llmNextAction: card.llmNextAction,
            badge: card.badge,
            columnId: card.columnId,
            isFavourite: card.isFavourite
        )
    }
}
