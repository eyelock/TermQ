import AppKit
import SwiftUI
import TermQCore

struct CardEditorView: View {
    @ObservedObject var card: TerminalCard
    let columns: [Column]
    let isNewCard: Bool
    let onSave: (_ switchToTerminal: Bool) -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel = CardEditorViewModel()
    @State private var selectedTab: EditorTab = .general
    @ObservedObject private var tmuxManager = TmuxManager.shared
    @ObservedObject private var sessionManager = TerminalSessionManager.shared
    @Environment(SettingsStore.self) private var settings
    private var globalAllowAgentPrompts: Bool { settings.enableTerminalAutorun }
    private var globalAllowOscClipboard: Bool { settings.allowOscClipboard }
    private var globalConfirmExternalModifications: Bool { settings.confirmExternalLLMModifications }
    private var tmuxEnabled: Bool { settings.tmuxEnabled }

    private enum EditorTab: CaseIterable {
        case general
        case terminal
        case environment
        case agent
        case metadata
        case prompts

        var title: String {
            switch self {
            case .general: return Strings.Editor.tabGeneral
            case .terminal: return Strings.Editor.sectionTerminal
            case .environment: return Strings.Settings.tabEnvironment
            case .agent: return Strings.Editor.Agent.tab
            case .metadata: return Strings.Editor.sectionTags
            case .prompts: return Strings.Editor.sectionPrompts
            }
        }
    }

    /// Tabs visible in the picker. The Agent tab appears only for cards
    /// whose agentConfig is set.
    private var visibleTabs: [EditorTab] {
        EditorTab.allCases.filter { tab in
            tab != .agent || viewModel.hasAgentConfig
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

    /// Preview font based on current selection. Resolves the per-card
    /// override against the user-layer default for display only.
    private var previewFont: Font {
        let size = SettingsStore.shared.effectiveFontSize(card: viewModel.fontSize)
        if viewModel.fontName.isEmpty {
            return .system(size: size, design: .monospaced)
        } else {
            return .custom(viewModel.fontName, size: size)
        }
    }

    // MARK: - Override bindings
    //
    // The four drift-named fields each carry an Optional override. The
    // editor's UI exposes an "Override default" toggle that flips between
    // `nil` (inherit) and an explicit value. The bindings below keep that
    // mapping in one place so the form can keep using the existing
    // controls (Picker/Slider/Toggle) over a non-Optional value.

    private func overrideToggle<T>(
        for keyPath: ReferenceWritableKeyPath<CardEditorViewModel, T?>,
        defaultValue: @escaping () -> T
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel[keyPath: keyPath] != nil },
            set: { isOverride in
                if isOverride {
                    if viewModel[keyPath: keyPath] == nil {
                        viewModel[keyPath: keyPath] = defaultValue()
                    }
                } else {
                    viewModel[keyPath: keyPath] = nil
                }
            }
        )
    }

    private func overrideValue<T>(
        for keyPath: ReferenceWritableKeyPath<CardEditorViewModel, T?>,
        defaultValue: @escaping () -> T
    ) -> Binding<T> {
        Binding(
            get: { viewModel[keyPath: keyPath] ?? defaultValue() },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
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
                    viewModel.save(to: card)
                    onSave(isNewCard && viewModel.switchToTerminal)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(visibleTabs, id: \.self) { tab in
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
                        environmentVariables: $viewModel.environmentVariables,
                        cardId: card.id
                    )
                case .agent:
                    agentContent
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
            viewModel.load(from: card)
            viewModel.mcpInstalled = MCPServerInstaller.currentInstallLocation != nil
        }
    }

    // MARK: - General Tab Content

    @ViewBuilder
    private var generalContent: some View {
        Section(Strings.Editor.sectionDetails) {
            TextField(Strings.Editor.fieldName, text: $viewModel.title)
            TextField(Strings.Editor.fieldDescription, text: $viewModel.description, axis: .vertical)
                .lineLimit(3...6)
            TextField(Strings.Editor.fieldBadges, text: $viewModel.badge)
                .help(Strings.Editor.fieldBadgesHelp)
        }

        Section(Strings.Editor.fieldColumn) {
            Picker(Strings.Editor.fieldColumn, selection: $viewModel.selectedColumnId) {
                ForEach(columns) { column in
                    Text(column.name).tag(column.id)
                }
            }

            Toggle(Strings.Card.pin, isOn: $viewModel.isFavourite)

            if isNewCard {
                Toggle(Strings.Editor.saveOpen, isOn: $viewModel.switchToTerminal)
            }
        }

        Section(Strings.Editor.sectionAppearance) {
            // Theme: Override toggle + Picker (when overriding)
            Toggle(
                Strings.Editor.fieldThemeOverride,
                isOn: overrideToggle(for: \.themeId, defaultValue: { settings.themeId })
            )
            if viewModel.themeId != nil {
                Picker(
                    Strings.Editor.fieldTheme,
                    selection: overrideValue(for: \.themeId, defaultValue: { settings.themeId })
                ) {
                    ForEach(TerminalTheme.allThemes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
            } else {
                HStack {
                    Text(Strings.Editor.fieldTheme)
                    Spacer()
                    Text(TerminalTheme.theme(for: settings.themeId).name)
                        .foregroundColor(.secondary)
                }
            }

            Picker(Strings.Editor.fieldFontSize, selection: $viewModel.fontName) {
                ForEach(monospaceFonts, id: \.self) { font in
                    Text(font).tag(font == "System Default" ? "" : font)
                }
            }

            // Font size: Override toggle + Slider (when overriding)
            Toggle(
                Strings.Editor.fieldFontSizeOverride,
                isOn: overrideToggle(for: \.fontSize, defaultValue: { settings.fontSize })
            )
            if viewModel.fontSize != nil {
                let size = overrideValue(for: \.fontSize, defaultValue: { settings.fontSize })
                HStack {
                    Text(Strings.Editor.fieldFontSize)
                    Slider(value: size, in: 9...24, step: 1)
                    Text("\(Int(size.wrappedValue)) pt")
                        .frame(width: 40)
                }
            } else {
                HStack {
                    Text(Strings.Editor.fieldFontSize)
                    Spacer()
                    Text("\(Int(settings.fontSize)) pt")
                        .foregroundColor(.secondary)
                }
            }

            // Font preview reflects the *resolved* values so users see the
            // effective appearance whether or not they're overriding.
            let resolvedThemeId = settings.effectiveThemeId(card: viewModel.themeId)
            let previewTheme = TerminalTheme.theme(for: resolvedThemeId)
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
            let hasActiveSession = sessionManager.hasActiveSession(for: card.id)

            Section(Strings.Editor.sectionBackend) {
                Toggle(
                    Strings.Editor.fieldBackendOverride,
                    isOn: overrideToggle(for: \.backend, defaultValue: { settings.backend })
                )
                .disabled(hasActiveSession)

                let resolvedBackend = settings.effectiveBackend(card: viewModel.backend)
                if viewModel.backend != nil {
                    Picker(
                        Strings.Editor.fieldBackend,
                        selection: overrideValue(for: \.backend, defaultValue: { settings.backend })
                    ) {
                        ForEach(TerminalBackend.allCases, id: \.self) { backend in
                            Text(localizedName(for: backend)).tag(backend)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(hasActiveSession)
                } else {
                    HStack {
                        Text(Strings.Editor.fieldBackend)
                        Spacer()
                        Text(localizedName(for: resolvedBackend))
                            .foregroundColor(.secondary)
                    }
                }

                if hasActiveSession {
                    Text(Strings.Editor.backendLockedWarning)
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text(
                        "\(localizedDescription(for: resolvedBackend)) \(Strings.Editor.backendRestartHint)"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }

        Section(Strings.Editor.sectionTerminal) {
            PathInputField(
                label: Strings.Editor.fieldDirectory,
                path: $viewModel.workingDirectory,
                helpText: Strings.Editor.fieldDirectoryHelp,
                validatePath: true
            )

            TextField(Strings.Editor.fieldShell, text: $viewModel.shellPath)
                .font(.system(.body, design: .monospaced))
                .help(Strings.Editor.fieldShellHelp)
        }

        Section(Strings.Editor.sectionSecurity) {
            Toggle(
                Strings.Editor.fieldSafePasteOverride,
                isOn: overrideToggle(for: \.safePasteEnabled, defaultValue: { settings.safePaste })
            )
            if viewModel.safePasteEnabled != nil {
                Toggle(
                    Strings.Editor.fieldSafePaste,
                    isOn: overrideValue(
                        for: \.safePasteEnabled, defaultValue: { settings.safePaste })
                )
                .help(Strings.Editor.fieldSafePasteHelp)
            } else {
                HStack {
                    Text(Strings.Editor.fieldSafePaste)
                    Spacer()
                    Text(
                        settings.safePaste
                            ? Strings.Editor.fieldSafePasteInheritedOn
                            : Strings.Editor.fieldSafePasteInheritedOff
                    )
                    .foregroundColor(.secondary)
                }
            }

            SharedToggle(
                label: Strings.Editor.allowAgentPrompts,
                isOn: $viewModel.allowAutorun,
                isGloballyEnabled: globalAllowAgentPrompts,
                disabledMessage: Strings.Editor.allowAgentPromptsDisabledGlobally,
                helpText: Strings.Editor.allowAgentPromptsHelp
            )

            SharedToggle(
                label: Strings.Editor.confirmExternalModifications,
                isOn: $viewModel.confirmExternalModifications,
                isGloballyEnabled: globalConfirmExternalModifications,
                disabledMessage: Strings.Editor.confirmExternalModificationsDisabledGlobally,
                helpText: Strings.Editor.confirmExternalModificationsHelp
            )

            SharedToggle(
                label: Strings.Editor.allowOscClipboard,
                isOn: $viewModel.allowOscClipboard,
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
                TextField(
                    Strings.Editor.fieldInitCommandHelp, text: $viewModel.initCommand, axis: .vertical
                )
                .lineLimit(3...8)
                .help(Strings.Editor.fieldInitCommandHelp)
            }

            // Command Generator - only show when agent prompts are allowed
            if globalAllowAgentPrompts && viewModel.allowAutorun {
                Picker(Strings.Editor.sectionCommandGenerator, selection: $viewModel.selectedLLMVendor) {
                    ForEach(LLMVendor.allCases, id: \.self) { vendor in
                        Text(vendor.rawValue).tag(vendor)
                    }
                }
                .pickerStyle(.menu)

                if viewModel.selectedLLMVendor.supportsInteractiveToggle {
                    Toggle(Strings.Editor.interactiveModeToggle, isOn: $viewModel.interactiveMode)
                        .help(Strings.Editor.interactiveModeHelp)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Common.preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(
                        viewModel.selectedLLMVendor.commandTemplate(
                            interactive: viewModel.interactiveMode)
                    )
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
                }

                if !viewModel.selectedLLMVendor.includesPrompt {
                    Text(Strings.Editor.noLlmPromptWarning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !viewModel.interactiveMode && viewModel.selectedLLMVendor.supportsInteractiveToggle {
                    Text(Strings.Editor.nonInteractiveModeNote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button(Strings.Editor.fieldApplyToInitCommand) {
                        viewModel.initCommand = viewModel.selectedLLMVendor.commandTemplate(
                            interactive: viewModel.interactiveMode)
                    }
                    .help(Strings.Editor.fieldApplyToInitCommandHelp)
                }
            }
        }
    }

    // MARK: - Agent Tab Content

    @ViewBuilder
    private var agentContent: some View {
        Section(Strings.Editor.Agent.sectionConfig) {
            Picker(Strings.Editor.Agent.fieldBackend, selection: $viewModel.agentBackend) {
                ForEach(AgentBackend.allCases, id: \.self) { backend in
                    Text(backend.rawValue).tag(backend)
                }
            }
            Picker(Strings.Editor.Agent.fieldMode, selection: $viewModel.agentMode) {
                ForEach(AgentMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            Picker(Strings.Editor.Agent.fieldInteraction, selection: $viewModel.agentInteractionMode) {
                ForEach(AgentInteractionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
        }

        Section(Strings.Editor.Agent.sectionBudget) {
            Stepper(
                value: $viewModel.agentMaxTurns, in: 1...500, step: 5,
                label: {
                    HStack {
                        Text(Strings.Editor.Agent.fieldMaxTurns)
                        Spacer()
                        Text("\(viewModel.agentMaxTurns)").monospacedDigit()
                    }
                })
            Stepper(
                value: $viewModel.agentMaxTokens, in: 10_000...10_000_000, step: 50_000,
                label: {
                    HStack {
                        Text(Strings.Editor.Agent.fieldMaxTokens)
                        Spacer()
                        Text(formatTokens(viewModel.agentMaxTokens)).monospacedDigit()
                    }
                })
            Stepper(
                value: $viewModel.agentMaxWallMinutes, in: 1...720, step: 5,
                label: {
                    HStack {
                        Text(Strings.Editor.Agent.fieldMaxWallMinutes)
                        Spacer()
                        Text("\(viewModel.agentMaxWallMinutes) min").monospacedDigit()
                    }
                })
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return "\(tokens / 1_000_000)M" }
        if tokens >= 1_000 { return "\(tokens / 1_000)k" }
        return "\(tokens)"
    }

    // MARK: - Metadata Tab Content

    @ViewBuilder
    private var metadataContent: some View {
        Group {
            // Existing tags list
            Section(Strings.Editor.sectionTags) {
                KeyValueList(
                    items: $viewModel.tagItems,
                    onDelete: { id in
                        viewModel.deleteTag(id: id)
                    },
                    emptyMessage: Strings.Editor.noTags
                )
            }

            // Add new tag form
            Section {
                KeyValueAddForm(
                    config: .tags,
                    existingKeys: Set(viewModel.tags.map { $0.key }),
                    items: viewModel.tagItems,
                    onAdd: { key, value, _ in
                        viewModel.addTag(key: key, value: value)
                    }
                )
            } header: {
                Text(Strings.Editor.sectionAddTag)
            }

            if viewModel.tags.isEmpty {
                Section {
                    Text(Strings.Editor.tagsHelp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            viewModel.syncTagItems()
        }
        .onChange(of: viewModel.tags) { _, _ in
            viewModel.syncTagItems()
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
                status: viewModel.mcpInstalled ? .installed : .inactive,
                message: viewModel.mcpInstalled
                    ? Strings.Settings.cliInstalled : Strings.Settings.cliNotInstalled
            )

            StatusIndicator(
                icon: "bolt.fill",
                label: Strings.Editor.allowAgentPrompts,
                status: (globalAllowAgentPrompts && viewModel.allowAutorun) ? .active : .disabled,
                message: {
                    if !globalAllowAgentPrompts {
                        return Strings.Editor.allowAgentPromptsDisabledGlobally
                    }
                    return viewModel.allowAutorun ? Strings.Common.enabled : Strings.Common.disabled
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
                status: (globalConfirmExternalModifications && viewModel.confirmExternalModifications)
                    ? .active : .disabled,
                message: {
                    if !globalConfirmExternalModifications {
                        return Strings.Editor.confirmExternalModificationsDisabledGlobally
                    }
                    return viewModel.confirmExternalModifications
                        ? Strings.Common.enabled : Strings.Common.disabled
                }()
            )
            .help(
                globalConfirmExternalModifications
                    ? Strings.Editor.confirmExternalModificationsHelp
                    : Strings.Editor.confirmExternalModificationsDisabledGlobally
            )
        }

        // Prompts Section
        Section(Strings.Editor.sectionPrompts) {
            LargeTextInput(
                label: Strings.Editor.fieldPersistentContext,
                text: $viewModel.llmPrompt,
                placeholder: Strings.Editor.fieldPersistentContextHelp,
                helpText: Strings.Editor.fieldPersistentContextHelp,
                minLines: 3,
                maxLines: 8
            )

            LargeTextInput(
                label: Strings.Editor.fieldNextAction,
                text: $viewModel.llmNextAction,
                placeholder: Strings.Editor.fieldNextActionHelp,
                helpText: Strings.Editor.fieldNextActionHelp,
                minLines: 3,
                maxLines: 8
            )

            if !globalAllowAgentPrompts {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(Strings.Editor.nextActionRequiresInjection)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Backend Localization Helpers

    private func localizedName(for backend: TerminalBackend) -> String {
        switch backend {
        case .direct:
            return Strings.Editor.backendDirect
        case .tmuxAttach:
            return Strings.Editor.backendTmuxAttach
        case .tmuxControl:
            return Strings.Editor.backendTmuxControl
        }
    }

    private func localizedDescription(for backend: TerminalBackend) -> String {
        switch backend {
        case .direct:
            return Strings.Editor.backendDirectDescription
        case .tmuxAttach:
            return Strings.Editor.backendTmuxAttachDescription
        case .tmuxControl:
            return Strings.Editor.backendTmuxControlDescription
        }
    }

}
