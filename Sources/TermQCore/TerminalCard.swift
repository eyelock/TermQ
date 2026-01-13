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

    /// Persistent LLM context for this terminal (always available, never auto-cleared)
    @Published public var llmPrompt: String

    /// One-time LLM action to run on next terminal open (seeds into init command, then clears)
    @Published public var llmNextAction: String

    /// Badge text to display on the card (e.g., "prod", "dev", git branch)
    @Published public var badge: String

    /// Custom font name (empty = system default monospace)
    @Published public var fontName: String

    /// Font size in points (0 = default 13pt)
    @Published public var fontSize: CGFloat

    /// Whether to show warnings when pasting potentially dangerous content
    @Published public var safePasteEnabled: Bool

    /// Terminal color theme ID (empty = use global default theme)
    @Published public var themeId: String

    /// Whether this terminal allows agent autorun commands (requires global enableTerminalAutorun)
    @Published public var allowAutorun: Bool

    /// When the card was soft-deleted (nil = active, set = in bin)
    @Published public var deletedAt: Date?

    // Runtime state (not persisted)
    public var isRunning: Bool = false
    public var isTransient: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, description, tags, columnId, orderIndex, shellPath, workingDirectory
        case isFavourite, initCommand, llmPrompt, llmNextAction, badge, fontName, fontSize, safePasteEnabled, themeId
        case allowAutorun, deletedAt
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
        llmNextAction: String = "",
        badge: String = "",
        fontName: String = "",
        fontSize: CGFloat = 0,
        safePasteEnabled: Bool = true,
        themeId: String = "",
        allowAutorun: Bool = false,
        deletedAt: Date? = nil
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
        self.llmNextAction = llmNextAction
        self.badge = badge
        self.fontName = fontName
        self.fontSize = fontSize
        self.safePasteEnabled = safePasteEnabled
        self.themeId = themeId
        self.allowAutorun = allowAutorun
        self.deletedAt = deletedAt
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
        llmNextAction = try container.decodeIfPresent(String.self, forKey: .llmNextAction) ?? ""
        badge = try container.decodeIfPresent(String.self, forKey: .badge) ?? ""
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? ""
        fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 0
        safePasteEnabled = try container.decodeIfPresent(Bool.self, forKey: .safePasteEnabled) ?? true
        themeId = try container.decodeIfPresent(String.self, forKey: .themeId) ?? ""
        allowAutorun = try container.decodeIfPresent(Bool.self, forKey: .allowAutorun) ?? false
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
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
        try container.encode(llmNextAction, forKey: .llmNextAction)
        try container.encode(badge, forKey: .badge)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(safePasteEnabled, forKey: .safePasteEnabled)
        try container.encode(themeId, forKey: .themeId)
        try container.encode(allowAutorun, forKey: .allowAutorun)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    /// Whether this card is in the bin (soft-deleted)
    public var isDeleted: Bool {
        deletedAt != nil
    }

    /// Parsed badges from comma-separated badge string (trimmed)
    public var badges: [String] {
        guard !badge.isEmpty else { return [] }
        return
            badge
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Equatable

extension TerminalCard: Equatable {
    public static func == (lhs: TerminalCard, rhs: TerminalCard) -> Bool {
        lhs.id == rhs.id
    }
}
