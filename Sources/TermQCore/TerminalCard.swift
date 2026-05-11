import Foundation

/// Backend mode for terminal session management
public enum TerminalBackend: String, Codable, CaseIterable, Sendable {
    /// Direct shell process - session dies with app
    case direct

    /// tmux-backed session with regular attach - persists across app restarts
    case tmuxAttach

    /// tmux with control mode - full pane management support
    case tmuxControl

    public var displayName: String {
        switch self {
        case .direct:
            return NSLocalizedString("backend.direct", bundle: .main, comment: "Direct backend name")
        case .tmuxAttach:
            return NSLocalizedString("backend.tmux.attach", bundle: .main, comment: "TMUX Attach backend name")
        case .tmuxControl:
            return NSLocalizedString("backend.tmux.control", bundle: .main, comment: "TMUX Control backend name")
        }
    }

    public var description: String {
        switch self {
        case .direct:
            return NSLocalizedString(
                "backend.direct.description", bundle: .main, comment: "Direct backend description")
        case .tmuxAttach:
            return NSLocalizedString(
                "backend.tmux.attach.description", bundle: .main, comment: "TMUX Attach backend description")
        case .tmuxControl:
            return NSLocalizedString(
                "backend.tmux.control.description", bundle: .main, comment: "TMUX Control backend description")
        }
    }

    /// Returns true if this backend uses tmux (either regular or control mode)
    public var usesTmux: Bool {
        switch self {
        case .direct:
            return false
        case .tmuxAttach, .tmuxControl:
            return true
        }
    }

    /// Short tag value for the `backend` auto-tag
    public var tagValue: String {
        switch self {
        case .direct: return "pty"
        case .tmuxAttach: return "tmux-attach"
        case .tmuxControl: return "tmux-control"
        }
    }
}

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

    /// Font size override in points. `nil` means inherit the global default.
    @Published public var fontSize: CGFloat?

    /// Safe-paste override. `nil` means inherit the global default.
    @Published public var safePasteEnabled: Bool?

    /// Terminal color theme override. `nil` means inherit the global default.
    @Published public var themeId: String?

    /// Whether this terminal allows agent autorun commands (requires global enableTerminalAutorun)
    @Published public var allowAutorun: Bool

    /// Whether this terminal allows OSC 52 clipboard access (requires global allowOscClipboard)
    @Published public var allowOscClipboard: Bool

    /// Whether this terminal requires confirmation for external LLM modifications (requires global confirmExternalLLMModifications)
    @Published public var confirmExternalModifications: Bool

    /// When the card was soft-deleted (nil = active, set = in bin)
    @Published public var deletedAt: Date?

    /// When an LLM last called termq_get for this terminal (nil = never, set = LLM is aware of TermQ)
    @Published public var lastLLMGet: Date?

    /// Backend override for session management. `nil` means inherit the
    /// global default backend.
    @Published public var backend: TerminalBackend?

    /// Cards created via headless MCP need tmux sessions when GUI starts
    /// GUI will detect this flag and create sessions automatically
    @Published public var needsTmuxSession: Bool

    /// Terminal-specific environment variables (injected on launch, overrides global)
    @Published public var environmentVariables: [EnvironmentVariable] = []

    // Runtime state (not persisted)
    public var isTransient: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, description, tags, columnId, orderIndex, shellPath, workingDirectory
        case isFavourite, initCommand, llmPrompt, llmNextAction, badge, fontName, fontSize, safePasteEnabled, themeId
        case allowAutorun, allowOscClipboard, confirmExternalModifications
        case deletedAt, lastLLMGet, backend, needsTmuxSession, environmentVariables
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
        fontSize: CGFloat? = nil,
        safePasteEnabled: Bool? = nil,
        themeId: String? = nil,
        allowAutorun: Bool = false,
        allowOscClipboard: Bool = true,
        confirmExternalModifications: Bool = true,
        deletedAt: Date? = nil,
        lastLLMGet: Date? = nil,
        backend: TerminalBackend? = nil,
        needsTmuxSession: Bool = false,
        environmentVariables: [EnvironmentVariable] = []
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
        self.allowOscClipboard = allowOscClipboard
        self.confirmExternalModifications = confirmExternalModifications
        self.deletedAt = deletedAt
        self.lastLLMGet = lastLLMGet
        self.backend = backend
        self.needsTmuxSession = needsTmuxSession
        self.environmentVariables = environmentVariables
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
        // Drift-field migration: cards persisted before these became Optional
        // round-trip their concrete values as explicit overrides. Cards
        // written by this version with no override store nothing (inherit).
        // Sentinel values from older builds (`fontSize == 0`, empty themeId)
        // also map to "inherit" so a stored "use the default" intent survives.
        let decodedFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize)
        fontSize = (decodedFontSize.flatMap { $0 > 0 ? $0 : nil })
        safePasteEnabled = try container.decodeIfPresent(Bool.self, forKey: .safePasteEnabled)
        let decodedThemeId = try container.decodeIfPresent(String.self, forKey: .themeId)
        themeId = decodedThemeId.flatMap { $0.isEmpty ? nil : $0 }
        allowAutorun = try container.decodeIfPresent(Bool.self, forKey: .allowAutorun) ?? false
        allowOscClipboard = try container.decodeIfPresent(Bool.self, forKey: .allowOscClipboard) ?? true
        confirmExternalModifications =
            try container.decodeIfPresent(Bool.self, forKey: .confirmExternalModifications) ?? true
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        lastLLMGet = try container.decodeIfPresent(Date.self, forKey: .lastLLMGet)
        // Backend override: present-and-concrete = explicit override; absent = inherit.
        backend = try container.decodeIfPresent(TerminalBackend.self, forKey: .backend)
        needsTmuxSession = try container.decodeIfPresent(Bool.self, forKey: .needsTmuxSession) ?? false
        environmentVariables =
            try container.decodeIfPresent([EnvironmentVariable].self, forKey: .environmentVariables)
            ?? []
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
        try container.encodeIfPresent(fontSize, forKey: .fontSize)
        try container.encodeIfPresent(safePasteEnabled, forKey: .safePasteEnabled)
        try container.encodeIfPresent(themeId, forKey: .themeId)
        try container.encode(allowAutorun, forKey: .allowAutorun)
        try container.encode(allowOscClipboard, forKey: .allowOscClipboard)
        try container.encode(confirmExternalModifications, forKey: .confirmExternalModifications)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(lastLLMGet, forKey: .lastLLMGet)
        try container.encodeIfPresent(backend, forKey: .backend)
        try container.encode(needsTmuxSession, forKey: .needsTmuxSession)
        try container.encode(environmentVariables, forKey: .environmentVariables)
    }

    /// Whether this card is in the bin (soft-deleted)
    public var isDeleted: Bool {
        deletedAt != nil
    }

    /// Whether the LLM has recently identified itself via termq_get (within last 10 minutes)
    public var isWired: Bool {
        guard let lastGet = lastLLMGet else { return false }
        return Date().timeIntervalSince(lastGet) < 600  // 10 minutes
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

    /// tmux session name for this terminal (used when backend uses tmux)
    public var tmuxSessionName: String {
        "termq-\(id.uuidString.prefix(8).lowercased())"
    }
}

// MARK: - Equatable

extension TerminalCard: Equatable {
    public static func == (lhs: TerminalCard, rhs: TerminalCard) -> Bool {
        lhs.id == rhs.id
    }
}
