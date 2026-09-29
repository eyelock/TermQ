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
    @Published var autoResumeSession: Bool = false
    @Published var selectedLLMVendor: LLMVendor = .claudeCode
    @Published var interactiveMode: Bool = true
    /// Optional override over the user-layer default. `nil` = inherit.
    @Published var backend: TerminalBackend?
    @Published var environmentVariables: [EnvironmentVariable] = []

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
        autoResumeSession = card.autoResumeSession
        backend = card.backend
        environmentVariables = card.environmentVariables
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
        card.autoResumeSession = autoResumeSession
        card.backend = backend
        card.environmentVariables = environmentVariables
    }

    // MARK: - Session Resume

    /// Whether the session-resume toggle applies to the card being edited.
    ///
    /// Two conditions, both necessary: the card must have been launched by a
    /// harness (a plain shell has no LLM session to continue), and the vendor
    /// it runs must report `supports_resume`. The latter is false for any YNH
    /// predating the feature, which is what stops TermQ emitting a flag that
    /// such a binary would forward to the vendor CLI as a bare `--resume` —
    /// opening an interactive session picker and hanging the pane.
    ///
    /// Takes the resumable vendor ids as a parameter rather than reaching for
    /// VendorService.shared, so the rule stays unit-testable and this view
    /// model keeps depending only on TermQCore.
    func canResumeSession(resumableVendorIDs: Set<String>) -> Bool {
        guard let vendorID = tags.first(where: { $0.key == "vendor" })?.value,
            !vendorID.isEmpty
        else { return false }
        return resumableVendorIDs.contains(vendorID)
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
