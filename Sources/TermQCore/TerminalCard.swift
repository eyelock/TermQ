import Foundation

/// Represents a terminal instance with metadata
public class TerminalCard: Identifiable, ObservableObject, Codable {
    public let id: UUID
    @Published public var title: String
    @Published public var description: String
    @Published public var tags: [Tag]
    @Published public var columnId: UUID
    @Published public var orderIndex: Int
    @Published public var shellPath: String
    @Published public var workingDirectory: String
    @Published public var isPinned: Bool

    // Runtime state (not persisted)
    public var isRunning: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, description, tags, columnId, orderIndex, shellPath, workingDirectory, isPinned
    }

    public init(
        id: UUID = UUID(),
        title: String = "New Terminal",
        description: String = "",
        tags: [Tag] = [],
        columnId: UUID,
        orderIndex: Int = 0,
        shellPath: String = "/bin/zsh",
        workingDirectory: String = NSHomeDirectory(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.tags = tags
        self.columnId = columnId
        self.orderIndex = orderIndex
        self.shellPath = shellPath
        self.workingDirectory = workingDirectory
        self.isPinned = isPinned
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        tags = try container.decode([Tag].self, forKey: .tags)
        columnId = try container.decode(UUID.self, forKey: .columnId)
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        shellPath = try container.decode(String.self, forKey: .shellPath)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(tags, forKey: .tags)
        try container.encode(columnId, forKey: .columnId)
        try container.encode(orderIndex, forKey: .orderIndex)
        try container.encode(shellPath, forKey: .shellPath)
        try container.encode(workingDirectory, forKey: .workingDirectory)
        try container.encode(isPinned, forKey: .isPinned)
    }
}

// MARK: - Equatable

extension TerminalCard: Equatable {
    public static func == (lhs: TerminalCard, rhs: TerminalCard) -> Bool {
        lhs.id == rhs.id
    }
}
