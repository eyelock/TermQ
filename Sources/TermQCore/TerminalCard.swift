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
    @Published public var isFavourite: Bool

    /// Command(s) to run when terminal initializes (after shell starts)
    @Published public var initCommand: String

    /// LLM prompt/context for this terminal task
    @Published public var llmPrompt: String

    /// Badge text to display on the card (e.g., "prod", "dev", git branch)
    @Published public var badge: String

    /// Custom font name (empty = system default monospace)
    @Published public var fontName: String

    /// Font size in points (0 = default 13pt)
    @Published public var fontSize: CGFloat

    // Runtime state (not persisted)
    public var isRunning: Bool = false
    public var isTransient: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, description, tags, columnId, orderIndex, shellPath, workingDirectory
        case isFavourite, initCommand, llmPrompt, badge, fontName, fontSize
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
        isFavourite: Bool = false,
        initCommand: String = "",
        llmPrompt: String = "",
        badge: String = "",
        fontName: String = "",
        fontSize: CGFloat = 0
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.tags = tags
        self.columnId = columnId
        self.orderIndex = orderIndex
        self.shellPath = shellPath
        self.workingDirectory = workingDirectory
        self.isFavourite = isFavourite
        self.initCommand = initCommand
        self.llmPrompt = llmPrompt
        self.badge = badge
        self.fontName = fontName
        self.fontSize = fontSize
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
        isFavourite = try container.decodeIfPresent(Bool.self, forKey: .isFavourite) ?? false
        initCommand = try container.decodeIfPresent(String.self, forKey: .initCommand) ?? ""
        llmPrompt = try container.decodeIfPresent(String.self, forKey: .llmPrompt) ?? ""
        badge = try container.decodeIfPresent(String.self, forKey: .badge) ?? ""
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? ""
        fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 0
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
        try container.encode(isFavourite, forKey: .isFavourite)
        try container.encode(initCommand, forKey: .initCommand)
        try container.encode(llmPrompt, forKey: .llmPrompt)
        try container.encode(badge, forKey: .badge)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(fontSize, forKey: .fontSize)
    }
}

// MARK: - Equatable

extension TerminalCard: Equatable {
    public static func == (lhs: TerminalCard, rhs: TerminalCard) -> Bool {
        lhs.id == rhs.id
    }
}
