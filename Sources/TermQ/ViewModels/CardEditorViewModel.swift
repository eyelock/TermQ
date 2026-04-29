import Foundation
import TermQCore

/// Form state and logic for the card editor, extracted from CardEditorView.
/// All 25+ @State properties that mirror TerminalCard fields live here,
/// making validation and load/save logic unit-testable without a view hierarchy.
@MainActor
final class CardEditorViewModel: ObservableObject {

    // MARK: - Form State

    @Published var title: String = ""
    @Published var description: String = ""
    @Published var workingDirectory: String = ""
    @Published var shellPath: String = ""
    @Published var selectedColumnId: UUID = UUID()
    @Published var tags: [Tag] = []
    @Published var tagItems: [KeyValueItem] = []
    @Published var switchToTerminal: Bool = true
    @Published var isFavourite: Bool = false
    @Published var initCommand: String = ""
    @Published var llmPrompt: String = ""
    @Published var llmNextAction: String = ""
    @Published var badge: String = ""
    @Published var fontName: String = ""
    /// Optional override over the user-layer default. `nil` = inherit.
    @Published var fontSize: CGFloat?
    /// Optional override over the user-layer default. `nil` = inherit.
    @Published var safePasteEnabled: Bool?
    /// Optional override over the user-layer default. `nil` = inherit.
    @Published var themeId: String?
    @Published var mcpInstalled: Bool = false
    @Published var allowAutorun: Bool = false
    @Published var allowOscClipboard: Bool = true
    @Published var confirmExternalModifications: Bool = true
    @Published var selectedLLMVendor: LLMVendor = .claudeCode
    @Published var interactiveMode: Bool = true
    /// Optional override over the user-layer default. `nil` = inherit.
    @Published var backend: TerminalBackend?
    @Published var environmentVariables: [EnvironmentVariable] = []

    // Agent session fields. `hasAgentConfig` mirrors `card.agentConfig != nil`;
    // the editor's Agent tab is only shown when this is true. The other
    // fields hold the editable mirror; non-editable identity fields
    // (sessionId, harness, status) are preserved from the source card on
    // save.
    @Published var hasAgentConfig: Bool = false
    @Published var agentBackend: AgentBackend = .claudeCode
    @Published var agentMode: AgentMode = .plan
    @Published var agentInteractionMode: AgentInteractionMode = .confirm
    @Published var agentMaxTurns: Int = AgentBudget.default.maxTurns
    @Published var agentMaxTokens: Int = AgentBudget.default.maxTokens
    @Published var agentMaxWallMinutes: Int = AgentBudget.default.maxWallSeconds / 60
    @Published var agentLoopDriverCommand: String = ""

    // MARK: - Validation

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Load / Save

    func load(from card: TerminalCard) {
        title = card.title
        description = card.description
        workingDirectory = card.workingDirectory
        shellPath = card.shellPath
        selectedColumnId = card.columnId
        tags = card.tags.sorted { $0.key < $1.key }
        isFavourite = card.isFavourite
        initCommand = card.initCommand
        llmPrompt = card.llmPrompt
        llmNextAction = card.llmNextAction
        badge = card.badge
        fontName = card.fontName
        fontSize = card.fontSize
        safePasteEnabled = card.safePasteEnabled
        themeId = card.themeId
        allowAutorun = card.allowAutorun
        allowOscClipboard = card.allowOscClipboard
        confirmExternalModifications = card.confirmExternalModifications
        backend = card.backend
        environmentVariables = card.environmentVariables

        if let config = card.agentConfig {
            hasAgentConfig = true
            agentBackend = config.backend
            agentMode = config.mode
            agentInteractionMode = config.interactionMode
            agentMaxTurns = config.budget.maxTurns
            agentMaxTokens = config.budget.maxTokens
            agentMaxWallMinutes = max(1, config.budget.maxWallSeconds / 60)
            agentLoopDriverCommand = config.loopDriverCommand
        } else {
            hasAgentConfig = false
            agentLoopDriverCommand = ""
        }
    }

    func save(to card: TerminalCard) {
        card.title = title
        card.description = description
        card.workingDirectory = workingDirectory
        card.shellPath = shellPath
        card.columnId = selectedColumnId
        card.tags = tags
        card.isFavourite = isFavourite
        card.initCommand = initCommand
        card.llmPrompt = llmPrompt
        card.llmNextAction = llmNextAction
        card.badge = badge
        card.fontName = fontName
        card.fontSize = fontSize
        card.safePasteEnabled = safePasteEnabled
        card.themeId = themeId
        card.allowAutorun = allowAutorun
        card.allowOscClipboard = allowOscClipboard
        card.confirmExternalModifications = confirmExternalModifications
        card.backend = backend
        card.environmentVariables = environmentVariables

        if hasAgentConfig, var config = card.agentConfig {
            // Preserve identity fields (sessionId, harness, status); only
            // user-editable knobs are written through.
            config.backend = agentBackend
            config.mode = agentMode
            config.interactionMode = agentInteractionMode
            config.budget = AgentBudget(
                maxTurns: agentMaxTurns,
                maxTokens: agentMaxTokens,
                maxWallSeconds: agentMaxWallMinutes * 60
            )
            config.loopDriverCommand = agentLoopDriverCommand
            card.agentConfig = config
        }
    }

    // MARK: - Tag Helpers

    func addTag(key: String, value: String) {
        tags.append(Tag(key: key, value: value))
    }

    func deleteTag(id: UUID) {
        tags.removeAll { $0.id == id }
    }

    func syncTagItems() {
        tagItems = tags.map { tag in
            KeyValueItem(id: tag.id, key: tag.key, value: tag.value, isSecret: false)
        }
    }
}
