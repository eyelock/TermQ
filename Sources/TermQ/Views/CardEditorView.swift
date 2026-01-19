import AppKit
import SwiftUI
import TermQCore

struct CardEditorView: View {
    @ObservedObject var card: TerminalCard
    let columns: [Column]
    let isNewCard: Bool
    let onSave: (_ switchToTerminal: Bool) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var workingDirectory: String = ""
    @State private var shellPath: String = ""
    @State private var selectedColumnId: UUID = UUID()
    @State private var tags: [Tag] = []
    @State private var tagItems: [KeyValueItem] = []
    @State private var switchToTerminal: Bool = true
    @State private var isFavourite: Bool = false
    @State private var initCommand: String = ""
    @State private var llmPrompt: String = ""
    @State private var llmNextAction: String = ""
    @State private var badge: String = ""
    @State private var fontName: String = ""
    @State private var fontSize: CGFloat = 13
    @State private var safePasteEnabled: Bool = true
    @State private var themeId: String = ""
    @State private var selectedTab: EditorTab = .general
    @State private var mcpInstalled: Bool = false
    @State private var allowAutorun: Bool = false
    @State private var allowOscClipboard: Bool = true
    @State private var confirmExternalModifications: Bool = true
    @AppStorage("allowTerminalsToRunAgentPrompts") private var globalAllowAgentPrompts = false
    @AppStorage("allowOscClipboard") private var globalAllowOscClipboard = false
    @AppStorage("allowExternalLLMModifications") private var globalAllowExternalModifications = false
    @State private var selectedLLMVendor: LLMVendor = .claudeCode
    @State private var interactiveMode: Bool = true
    @State private var backend: TerminalBackend = .direct
    @State private var environmentVariables: [EnvironmentVariable] = []
    @ObservedObject private var tmuxManager = TmuxManager.shared
    @AppStorage("tmuxEnabled") private var tmuxEnabled = true

    private enum EditorTab: CaseIterable {
        case general
        case terminal
        case environment
        case metadata
        case prompts

        var title: String {
            switch self {
            case .general: return Strings.Editor.tabGeneral
            case .terminal: return Strings.Editor.sectionTerminal
            case .environment: return Strings.Settings.tabEnvironment
            case .metadata: return Strings.Editor.sectionTags
            case .prompts: return Strings.Editor.sectionPrompts
            }
        }
    }

    /// Available monospace fonts
    private var monospaceFonts: [String] {
        let fontManager = NSFontManager.shared
        let monoFonts = fontManager.availableFontFamilies.filter { family in
            if let font = NSFont(name: family, size: 12) {
                return font.isFixedPitch
            }
            return false
        }
        return ["System Default"] + monoFonts.sorted()
    }

    /// Preview font based on current selection
    private var previewFont: Font {
        if fontName.isEmpty {
            return .system(size: fontSize, design: .monospaced)
        } else {
            return .custom(fontName, size: fontSize)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNewCard ? Strings.Editor.titleNew : Strings.Editor.titleEdit)
                    .font(.headline)
                Spacer()
                Button(Strings.Editor.cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(Strings.Editor.save) {
                    saveChanges()
                    onSave(isNewCard && switchToTerminal)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(EditorTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            // Form with tabbed content
            Form {
                switch selectedTab {
                case .general:
                    generalContent
                case .terminal:
                    terminalContent
                case .environment:
                    CardEditorEnvironmentTab(
                        environmentVariables: $environmentVariables,
                        cardId: card.id
                    )
                case .metadata:
                    metadataContent
                case .prompts:
                    promptsContent
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 600, height: 580)
        .onAppear {
            loadFromCard()
            mcpInstalled = MCPServerInstaller.currentInstallLocation != nil
        }
    }

    // MARK: - General Tab Content

    @ViewBuilder
    private var generalContent: some View {
        Section(Strings.Editor.sectionDetails) {
            TextField(Strings.Editor.fieldName, text: $title)
            TextField(Strings.Editor.fieldDescription, text: $description, axis: .vertical)
                .lineLimit(3...6)
            TextField(Strings.Editor.fieldBadges, text: $badge)
                .help(Strings.Editor.fieldBadgesHelp)
        }

        Section(Strings.Editor.fieldColumn) {
            Picker(Strings.Editor.fieldColumn, selection: $selectedColumnId) {
                ForEach(columns) { column in
                    Text(column.name).tag(column.id)
                }
            }

            Toggle(Strings.Card.pin, isOn: $isFavourite)

            if isNewCard {
                Toggle(Strings.Editor.saveOpen, isOn: $switchToTerminal)
            }
        }

        Section(Strings.Editor.sectionAppearance) {
            Picker(Strings.Editor.fieldTheme, selection: $themeId) {
                Text(Strings.Editor.fieldThemeDefault).tag("")
                ForEach(TerminalTheme.allThemes) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }

            Picker(Strings.Editor.fieldFontSize, selection: $fontName) {
                ForEach(monospaceFonts, id: \.self) { font in
                    Text(font).tag(font == "System Default" ? "" : font)
                }
            }

            HStack {
                Text(Strings.Editor.fieldFontSize)
                Slider(value: $fontSize, in: 9...24, step: 1)
                Text("\(Int(fontSize)) pt")
                    .frame(width: 40)
            }

            // Font preview with theme colors
            let previewTheme =
                themeId.isEmpty ? TerminalTheme.defaultDark : TerminalTheme.theme(for: themeId)
            Text(Strings.Editor.fontPreview)
                .font(previewFont)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: previewTheme.background))
                .foregroundColor(Color(nsColor: previewTheme.foreground))
                .cornerRadius(4)
        }
    }

    // MARK: - Terminal Tab Content

    @ViewBuilder
    private var terminalContent: some View {
        // Session Backend at top - only show if tmux is available and enabled globally
        if tmuxManager.isAvailable && tmuxEnabled {
            Section(Strings.Editor.sectionBackend) {
                Picker(Strings.Editor.fieldBackend, selection: $backend) {
                    ForEach(TerminalBackend.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("\(backend.description) \(Strings.Editor.backendRestartHint)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        Section(Strings.Editor.sectionTerminal) {
            PathInputField(
                label: Strings.Editor.fieldDirectory,
                path: $workingDirectory,
                helpText: Strings.Editor.fieldDirectoryHelp,
                validatePath: true
            )

            TextField(Strings.Editor.fieldShell, text: $shellPath)
                .font(.system(.body, design: .monospaced))
                .help(Strings.Editor.fieldShellHelp)
        }

        Section(Strings.Editor.sectionSecurity) {
            Toggle(Strings.Editor.fieldSafePaste, isOn: $safePasteEnabled)
                .help(Strings.Editor.fieldSafePasteHelp)

            SharedToggle(
                label: Strings.Editor.allowAgentPrompts,
                isOn: $allowAutorun,
                isGloballyEnabled: globalAllowAgentPrompts,
                disabledMessage: Strings.Editor.allowAgentPromptsDisabledGlobally,
                helpText: Strings.Editor.allowAgentPromptsHelp
            )

            SharedToggle(
                label: Strings.Editor.confirmExternalModifications,
                isOn: $confirmExternalModifications,
                isGloballyEnabled: globalAllowExternalModifications,
                disabledMessage: Strings.Editor.confirmExternalModificationsDisabledGlobally,
                helpText: Strings.Editor.confirmExternalModificationsHelp
            )

            SharedToggle(
                label: Strings.Editor.allowOscClipboard,
                isOn: $allowOscClipboard,
                isGloballyEnabled: globalAllowOscClipboard,
                disabledMessage: Strings.Editor.allowOscClipboardDisabledGlobally,
                helpText: Strings.Editor.allowOscClipboardHelp
            )
        }

        Section(Strings.Editor.sectionAutomation) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Editor.fieldInitCommand)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(Strings.Editor.fieldInitCommandHelp, text: $initCommand, axis: .vertical)
                    .lineLimit(3...8)
                    .help(Strings.Editor.fieldInitCommandHelp)
            }

            // Command Generator - only show when agent prompts are allowed
            if globalAllowAgentPrompts && allowAutorun {
                Picker(Strings.Editor.sectionCommandGenerator, selection: $selectedLLMVendor) {
                    ForEach(LLMVendor.allCases, id: \.self) { vendor in
                        Text(vendor.rawValue).tag(vendor)
                    }
                }
                .pickerStyle(.menu)

                if selectedLLMVendor.supportsInteractiveToggle {
                    Toggle(Strings.Editor.interactiveModeToggle, isOn: $interactiveMode)
                        .help(Strings.Editor.interactiveModeHelp)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Common.preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(selectedLLMVendor.commandTemplate(interactive: interactiveMode))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                }

                if !selectedLLMVendor.includesPrompt {
                    Text(Strings.Editor.noLlmPromptWarning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !interactiveMode && selectedLLMVendor.supportsInteractiveToggle {
                    Text(Strings.Editor.nonInteractiveModeNote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button(Strings.Editor.fieldApplyToInitCommand) {
                        initCommand = selectedLLMVendor.commandTemplate(interactive: interactiveMode)
                    }
                    .help(Strings.Editor.fieldApplyToInitCommandHelp)
                }
            }
        }
    }

    // MARK: - Metadata Tab Content

    @ViewBuilder
    private var metadataContent: some View {
        Group {
            // Existing tags list
            Section(Strings.Editor.sectionTags) {
                KeyValueList(
                    items: $tagItems,
                    onDelete: { id in
                        deleteTag(id: id)
                    }
                )
            }

            // Add new tag form
            Section {
                KeyValueAddForm(
                    config: .tags,
                    existingKeys: Set(tags.map { $0.key }),
                    items: tagItems,
                    onAdd: { key, value, _ in
                        addTag(key: key, value: value)
                    }
                )
            } header: {
                Text(Strings.Editor.sectionAddTag)
            }

            if tags.isEmpty {
                Section {
                    Text(Strings.Editor.tagsHelp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            syncTagItems()
        }
        .onChange(of: tags) { _, _ in
            syncTagItems()
        }
    }

    // MARK: - Prompts Tab Content

    @ViewBuilder
    private var promptsContent: some View {
        // Status Indicators Section
        Section {
            StatusIndicator(
                icon: "cpu",
                label: Strings.Settings.mcpTitle,
                status: mcpInstalled ? .installed : .inactive,
                message: mcpInstalled ? Strings.Settings.cliInstalled : Strings.Settings.cliNotInstalled
            )

            StatusIndicator(
                icon: "bolt.fill",
                label: Strings.Editor.allowAgentPrompts,
                status: (globalAllowAgentPrompts && allowAutorun) ? .active : .disabled,
                message: {
                    if !globalAllowAgentPrompts {
                        return Strings.Editor.allowAgentPromptsDisabledGlobally
                    }
                    return allowAutorun ? Strings.Common.enabled : Strings.Common.disabled
                }()
            )
            .help(
                globalAllowAgentPrompts
                    ? Strings.Editor.allowAgentPromptsHelp
                    : Strings.Editor.fieldAutorunEnableHint
            )

            StatusIndicator(
                icon: "checkmark.shield.fill",
                label: Strings.Editor.confirmExternalModifications,
                status: (globalAllowExternalModifications && confirmExternalModifications) ? .active : .disabled,
                message: {
                    if !globalAllowExternalModifications {
                        return Strings.Editor.confirmExternalModificationsDisabledGlobally
                    }
                    return confirmExternalModifications ? Strings.Common.enabled : Strings.Common.disabled
                }()
            )
            .help(
                globalAllowExternalModifications
                    ? Strings.Editor.confirmExternalModificationsHelp
                    : Strings.Editor.confirmExternalModificationsDisabledGlobally
            )
        }

        // Prompts Section
        Section(Strings.Editor.sectionPrompts) {
            LargeTextInput(
                label: Strings.Editor.fieldPersistentContext,
                text: $llmPrompt,
                placeholder: Strings.Editor.fieldPersistentContextHelp,
                helpText: Strings.Editor.fieldPersistentContextHelp,
                minLines: 3,
                maxLines: 8
            )

            LargeTextInput(
                label: Strings.Editor.fieldNextAction,
                text: $llmNextAction,
                placeholder: Strings.Editor.fieldNextActionHelp,
                helpText: Strings.Editor.fieldNextActionHelp,
                minLines: 3,
                maxLines: 8
            )
        }
    }

    private func loadFromCard() {
        title = card.title
        description = card.description
        workingDirectory = card.workingDirectory
        shellPath = card.shellPath
        selectedColumnId = card.columnId
        tags = card.tags
        isFavourite = card.isFavourite
        initCommand = card.initCommand
        llmPrompt = card.llmPrompt
        llmNextAction = card.llmNextAction
        badge = card.badge
        fontName = card.fontName
        fontSize = card.fontSize > 0 ? card.fontSize : 13
        safePasteEnabled = card.safePasteEnabled
        themeId = card.themeId
        allowAutorun = card.allowAutorun
        allowOscClipboard = card.allowOscClipboard
        confirmExternalModifications = card.confirmExternalModifications
        backend = card.backend
        environmentVariables = card.environmentVariables
    }

    private func saveChanges() {
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
    }

    private func addTag(key: String, value: String) {
        let tag = Tag(key: key, value: value)
        tags.append(tag)
    }

    private func deleteTag(id: UUID) {
        tags.removeAll { $0.id == id }
    }

    private func syncTagItems() {
        tagItems = tags.map { tag in
            KeyValueItem(
                id: tag.id,
                key: tag.key,
                value: tag.value,
                isSecret: false
            )
        }
    }

}
