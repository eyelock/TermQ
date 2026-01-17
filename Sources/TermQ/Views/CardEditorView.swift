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
    @State private var newTagKey: String = ""
    @State private var newTagValue: String = ""
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
    @AppStorage("enableTerminalAutorun") private var enableTerminalAutorun = false
    @AppStorage("allowOscClipboard") private var globalAllowOscClipboard = true
    @AppStorage("confirmExternalLLMModifications") private var globalConfirmExternalModifications = true
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
        case agents

        var title: String {
            switch self {
            case .general: return Strings.Editor.tabGeneral
            case .terminal: return Strings.Editor.sectionTerminal
            case .environment: return Strings.Settings.tabEnvironment
            case .metadata: return Strings.Editor.sectionTags
            case .agents: return Strings.Editor.sectionAgent
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
                case .agents:
                    agentsContent
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
            HStack {
                TextField(Strings.Editor.fieldDirectory, text: $workingDirectory)
                    .font(.system(.body, design: .monospaced))
                    .help(Strings.Editor.fieldDirectoryHelp)
                Button(Strings.Common.browse) {
                    browseDirectory()
                }
            }

            TextField(Strings.Editor.fieldShell, text: $shellPath)
                .font(.system(.body, design: .monospaced))
                .help(Strings.Editor.fieldShellHelp)
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
        }

        Section(Strings.Editor.sectionSecurity) {
            Toggle(Strings.Editor.fieldSafePaste, isOn: $safePasteEnabled)
                .help(Strings.Editor.fieldSafePasteHelp)

            if enableTerminalAutorun {
                Toggle(Strings.Editor.fieldAllowAutorun, isOn: $allowAutorun)
                    .help(Strings.Editor.fieldAllowAutorunHelp)
            } else {
                HStack {
                    Text(Strings.Editor.fieldAllowAutorun)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Strings.Editor.fieldAutorunDisabledGlobally)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .help(Strings.Editor.fieldAutorunEnableHint)
            }

            if globalAllowOscClipboard {
                Toggle(Strings.Editor.allowOscClipboard, isOn: $allowOscClipboard)
                    .help(Strings.Editor.allowOscClipboardHelp)
            } else {
                HStack {
                    Text(Strings.Editor.allowOscClipboard)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Strings.Editor.disabledGlobally)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .help(Strings.Editor.allowOscClipboardHelp)
            }

            if globalConfirmExternalModifications {
                Toggle(Strings.Editor.confirmExternalModifications, isOn: $confirmExternalModifications)
                    .help(Strings.Editor.confirmExternalModificationsHelp)
            } else {
                HStack {
                    Text(Strings.Editor.confirmExternalModifications)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Strings.Editor.disabledGlobally)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .help(Strings.Editor.confirmExternalModificationsHelp)
            }
        }
    }

    // MARK: - Metadata Tab Content

    @ViewBuilder
    private var metadataContent: some View {
        Section(Strings.Editor.sectionTags) {
            ForEach(tags) { tag in
                HStack {
                    Text(tag.key)
                        .fontWeight(.medium)
                    Text("=")
                    Text(tag.value)
                    Spacer()
                    Button {
                        tags.removeAll { $0.id == tag.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField(Strings.Editor.tagKeyPlaceholder, text: $newTagKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Text("=")
                    .foregroundColor(.secondary)
                TextField(Strings.Editor.tagValuePlaceholder, text: $newTagValue)
                    .textFieldStyle(.roundedBorder)
                Button(Strings.Editor.tagAdd) {
                    addTag()
                }
                .disabled(
                    newTagKey.trimmingCharacters(in: .whitespaces).isEmpty
                        || newTagValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .onSubmit {
                addTag()
            }

            if tags.isEmpty {
                Text(Strings.Editor.tagsHelp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Agents Tab Content

    @ViewBuilder
    private var agentsContent: some View {
        Section(Strings.Settings.sectionMcp) {
            HStack {
                Text(Strings.Settings.mcpTitle)
                Spacer()
                Image(systemName: mcpInstalled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(mcpInstalled ? .green : .secondary)
                Text(mcpInstalled ? Strings.Settings.cliInstalled : Strings.Settings.cliNotInstalled)
                    .foregroundColor(mcpInstalled ? .primary : .secondary)
            }

            HStack {
                Text(Strings.Editor.fieldTerminalAllowsAutorun)
                Spacer()
                if enableTerminalAutorun {
                    Image(systemName: allowAutorun ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(allowAutorun ? .green : .secondary)
                    Text(allowAutorun ? Strings.Common.installed : Strings.Editor.fieldAutorunDisabledGlobally)
                        .foregroundColor(allowAutorun ? .primary : .secondary)
                } else {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                    Text(Strings.Editor.fieldAutorunDisabledGlobally)
                        .foregroundColor(.secondary)
                }
            }
            .help(
                enableTerminalAutorun
                    ? Strings.Editor.fieldAllowAutorunHelp
                    : Strings.Editor.fieldAutorunEnableHint
            )
        }

        Section(Strings.Editor.sectionAgent) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Editor.fieldPersistentContext)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(Strings.Editor.fieldPersistentContextHelp, text: $llmPrompt, axis: .vertical)
                    .lineLimit(3...8)
                    .help(Strings.Editor.fieldPersistentContextHelp)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Editor.fieldNextAction)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(Strings.Editor.fieldNextActionHelp, text: $llmNextAction, axis: .vertical)
                    .lineLimit(3...8)
                    .help(Strings.Editor.fieldNextActionHelp)
            }
        }

        Section(Strings.Editor.sectionCommandGenerator) {
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
                    selectedTab = .terminal
                }
                .help(Strings.Editor.fieldApplyToInitCommandHelp)
            }
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

    private func addTag() {
        let key = newTagKey.trimmingCharacters(in: .whitespaces)
        let value = newTagValue.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty && !value.isEmpty {
            tags.append(Tag(key: key, value: value))
            newTagKey = ""
            newTagValue = ""
        }
    }

    private func browseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectory)

        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }
}
