import Foundation

/// Represents a terminal card (shared across CLI and MCP)
public struct Card: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let description: String
    public let tags: [Tag]
    public let columnId: UUID
    public let orderIndex: Int
    public let workingDirectory: String
    public let isFavourite: Bool
    public let badge: String
    public let llmPrompt: String
    public let llmNextAction: String
    public let allowAutorun: Bool
    public let deletedAt: Date?

    // Custom decoding to handle missing fields for backwards compatibility
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags) ?? []
        columnId = try container.decode(UUID.self, forKey: .columnId)
        orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex) ?? 0
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
        isFavourite = try container.decodeIfPresent(Bool.self, forKey: .isFavourite) ?? false
        badge = try container.decodeIfPresent(String.self, forKey: .badge) ?? ""
        llmPrompt = try container.decodeIfPresent(String.self, forKey: .llmPrompt) ?? ""
        llmNextAction = try container.decodeIfPresent(String.self, forKey: .llmNextAction) ?? ""
        allowAutorun = try container.decodeIfPresent(Bool.self, forKey: .allowAutorun) ?? false
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, tags, columnId, orderIndex
        case workingDirectory, isFavourite, badge, llmPrompt, llmNextAction, allowAutorun, deletedAt
    }

    /// Memberwise initializer for programmatic creation and tests
    public init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        tags: [Tag] = [],
        columnId: UUID,
        orderIndex: Int = 0,
        workingDirectory: String = "",
        isFavourite: Bool = false,
        badge: String = "",
        llmPrompt: String = "",
        llmNextAction: String = "",
        allowAutorun: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.tags = tags
        self.columnId = columnId
        self.orderIndex = orderIndex
        self.workingDirectory = workingDirectory
        self.isFavourite = isFavourite
        self.badge = badge
        self.llmPrompt = llmPrompt
        self.llmNextAction = llmNextAction
        self.allowAutorun = allowAutorun
        self.deletedAt = deletedAt
    }

    /// Whether this card is in the bin (soft-deleted)
    public var isDeleted: Bool { deletedAt != nil }

    /// Parsed badges from comma-separated badge string
    public var badges: [String] {
        guard !badge.isEmpty else { return [] }
        return
            badge
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Convert tags to dictionary
    public var tagsDictionary: [String: String] {
        var dict: [String: String] = [:]
        for tag in tags {
            dict[tag.key] = tag.value
        }
        return dict
    }

    /// Get staleness value from tags
    public var staleness: String {
        if let stalenessTag = tags.first(where: { $0.key.lowercased() == "staleness" }) {
            return stalenessTag.value.lowercased()
        }
        return "unknown"
    }

    /// Get staleness rank for sorting (higher = needs more attention)
    public var stalenessRank: Int {
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
