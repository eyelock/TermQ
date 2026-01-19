import Foundation
import TermQShared

/// Wraps BoardWriter with MCP-specific logic for headless operations
/// Sets needsTmuxSession flag and handles tag merging
enum HeadlessWriter {
    /// Parameters for updating a card
    struct UpdateParameters {
        let name: String?
        let description: String?
        let badge: String?
        let llmPrompt: String?
        let llmNextAction: String?
        let favourite: Bool?
        let tags: [(key: String, value: String)]?
        let replaceTags: Bool
    }

    /// Create a new card via BoardWriter with MCP-specific fields
    /// Marks card with needsTmuxSession=true for GUI to create sessions later
    static func createCard(
        name: String,
        columnName: String?,
        workingDirectory: String,
        description: String?,
        llmPrompt: String?,
        llmNextAction: String?,
        tags: [(key: String, value: String)]?,
        dataDirectory: URL? = nil,
        debug: Bool = false
    ) throws -> Card {
        // Create the card using BoardWriter
        var card = try BoardWriter.createCard(
            name: name,
            columnName: columnName,
            workingDirectory: workingDirectory,
            description: description ?? "",
            dataDirectory: dataDirectory,
            debug: debug
        )

        // Build updates for additional MCP fields
        var updates: [String: Any] = [:]

        if let llmPrompt = llmPrompt {
            updates["llmPrompt"] = llmPrompt
        }

        if let llmNextAction = llmNextAction {
            updates["llmNextAction"] = llmNextAction
        }

        // Mark as needing tmux session (GUI will create it on startup)
        updates["needsTmuxSession"] = true

        // Convert tags to dictionary format for storage
        if let tags = tags, !tags.isEmpty {
            let tagDicts = tags.map { ["key": $0.key, "value": $0.value] }
            updates["tags"] = tagDicts
        }

        // Apply all updates if there are any
        if !updates.isEmpty {
            card = try BoardWriter.updateCard(
                identifier: card.id.uuidString,
                updates: updates,
                dataDirectory: dataDirectory,
                debug: debug
            )
        }

        return card
    }

    /// Update a card's fields via BoardWriter
    static func updateCard(
        identifier: String,
        params: UpdateParameters,
        dataDirectory: URL? = nil,
        debug: Bool = false
    ) throws -> Card {
        var updates: [String: Any] = [:]

        if let name = params.name {
            updates["title"] = name
        }

        if let description = params.description {
            updates["description"] = description
        }

        if let badge = params.badge {
            updates["badge"] = badge
        }

        if let llmPrompt = params.llmPrompt {
            updates["llmPrompt"] = llmPrompt
        }

        if let llmNextAction = params.llmNextAction {
            updates["llmNextAction"] = llmNextAction
        }

        if let favourite = params.favourite {
            updates["isFavourite"] = favourite
        }

        // Handle tag updates
        if let tags = params.tags {
            if params.replaceTags {
                // Replace all tags
                let tagDicts = tags.map { ["key": $0.key, "value": $0.value] }
                updates["tags"] = tagDicts
            } else {
                // Merge with existing tags
                let board = try BoardLoader.loadBoard(dataDirectory: dataDirectory, debug: debug)
                guard let card = board.findTerminal(identifier: identifier) else {
                    throw BoardWriter.WriteError.cardNotFound(identifier: identifier)
                }

                // Merge existing tags with new ones
                var mergedTags = card.tags
                for newTag in tags {
                    // Replace existing tag with same key, or append if new
                    if let index = mergedTags.firstIndex(where: { $0.key == newTag.key }) {
                        mergedTags[index] = Tag(key: newTag.key, value: newTag.value)
                    } else {
                        mergedTags.append(Tag(key: newTag.key, value: newTag.value))
                    }
                }

                let tagDicts = mergedTags.map { ["key": $0.key, "value": $0.value] }
                updates["tags"] = tagDicts
            }
        } else if params.replaceTags {
            // Clear all tags
            updates["tags"] = [[String: String]]()
        }

        return try BoardWriter.updateCard(
            identifier: identifier,
            updates: updates,
            dataDirectory: dataDirectory,
            debug: debug
        )
    }

    /// Move a card to a different column via BoardWriter
    static func moveCard(
        identifier: String,
        toColumn columnName: String,
        dataDirectory: URL? = nil,
        debug: Bool = false
    ) throws -> Card {
        try BoardWriter.moveCard(
            identifier: identifier,
            toColumn: columnName,
            dataDirectory: dataDirectory,
            debug: debug
        )
    }

    /// Soft-delete a card (sets deletedAt timestamp)
    static func deleteCard(
        identifier: String,
        permanent: Bool,
        dataDirectory: URL? = nil,
        debug: Bool = false
    ) throws {
        if permanent {
            // For permanent deletion, load board and remove from array
            // Note: BoardWriter doesn't have permanent delete, so we handle it here
            let rawBoard = try BoardWriter.loadRawBoard(dataDirectory: dataDirectory, debug: debug)
            let boardURL = rawBoard.url
            var board = rawBoard.data
            guard var cards = board["cards"] as? [[String: Any]] else {
                throw BoardWriter.WriteError.encodingFailed("Invalid cards format")
            }

            // Find and remove the card
            let cardIndex = try BoardWriter.findCardIndex(identifier: identifier, in: cards)
            cards.remove(at: cardIndex)

            board["cards"] = cards
            try BoardWriter.saveRawBoard(board, to: boardURL)
        } else {
            // Soft delete - set deletedAt timestamp
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let nowString = formatter.string(from: Date())

            _ = try BoardWriter.updateCard(
                identifier: identifier,
                updates: ["deletedAt": nowString],
                dataDirectory: dataDirectory,
                debug: debug
            )
        }
    }
}

// Extension to expose findCardIndex for permanent deletion
extension BoardWriter {
    /// Find card index by identifier (exposed for HeadlessWriter)
    static func findCardIndex(identifier: String, in cards: [[String: Any]]) throws -> Int {
        // Try as UUID
        if let _ = UUID(uuidString: identifier) {
            if let index = cards.firstIndex(where: {
                ($0["id"] as? String) == identifier
            }) {
                return index
            }
        }

        // Try as exact name (case-insensitive)
        let identifierLower = identifier.lowercased()
        if let index = cards.firstIndex(where: {
            ($0["title"] as? String)?.lowercased() == identifierLower
        }) {
            return index
        }

        // Try as partial name match
        if let index = cards.firstIndex(where: {
            ($0["title"] as? String)?.lowercased().contains(identifierLower) == true
        }) {
            return index
        }

        throw WriteError.cardNotFound(identifier: identifier)
    }
}
