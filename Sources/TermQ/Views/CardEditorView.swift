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

    private enum EditorTab: String, CaseIterable {
        case general = "General"
        case terminal = "Terminal"
        case metadata = "Metadata"
        case agents = "Agents"
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
                Text(isNewCard ? "New Terminal" : "Edit Terminal")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
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
                    Text(tab.rawValue).tag(tab)
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
        }
    }

    // MARK: - General Tab Content

    @ViewBuilder
    private var generalContent: some View {
        Section("Display") {
            TextField("Title", text: $title)
            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(3...6)
            TextField("Badges", text: $badge)
                .help("Comma separated values (e.g., 'prod, api, v2')")
        }

        Section("Behaviour") {
            Picker("Column", selection: $selectedColumnId) {
                ForEach(columns) { column in
                    Text(column.name).tag(column.id)
                }
            }

            Toggle("Favourite", isOn: $isFavourite)

            Toggle("Safe Paste", isOn: $safePasteEnabled)
                .help("Warn when pasting potentially dangerous commands")

            if isNewCard {
                Toggle("Switch to new terminal", isOn: $switchToTerminal)
            }
        }

        Section("Appearance") {
            Picker("Theme", selection: $themeId) {
                Text("Default (Global)").tag("")
                ForEach(TerminalTheme.allThemes) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }

            Picker("Font", selection: $fontName) {
                ForEach(monospaceFonts, id: \.self) { font in
                    Text(font).tag(font == "System Default" ? "" : font)
                }
            }

            HStack {
                Text("Size:")
                Slider(value: $fontSize, in: 9...24, step: 1)
                Text("\(Int(fontSize)) pt")
                    .frame(width: 40)
            }

            // Font preview with theme colors
            let previewTheme =
                themeId.isEmpty ? TerminalTheme.defaultDark : TerminalTheme.theme(for: themeId)
            Text("AaBbCc 123 ~/code $ ls -la")
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
        Section("Open") {
            HStack {
                TextField("Working Directory", text: $workingDirectory)
                    .font(.system(.body, design: .monospaced))
                    .help("Path where terminal opens (paste or type)")
                Button("Browse...") {
                    browseDirectory()
                }
            }

            TextField("Shell Path", text: $shellPath)
                .font(.system(.body, design: .monospaced))
                .help("e.g., /bin/zsh, /bin/bash (leave empty for default)")
        }

        Section("Initialisation") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Init Command")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Commands to run on start", text: $initCommand, axis: .vertical)
                    .lineLimit(3...8)
                    .help("e.g., 'source .env && npm run dev'")
            }
            // TODO: Add "Allow Agent Autorun" toggle here
        }
    }

    // MARK: - Metadata Tab Content

    @ViewBuilder
    private var metadataContent: some View {
        Section("Tags") {
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
                TextField("Key", text: $newTagKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Text("=")
                    .foregroundColor(.secondary)
                TextField("Value", text: $newTagValue)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
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
                Text("Tags help organize and search terminals (e.g., env=prod, team=backend)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Agents Tab Content

    @ViewBuilder
    private var agentsContent: some View {
        // TODO: Add MCP Server section here (Is Installed?, Last used?)

        Section("Agent Context") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Persistent Context")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Background info always available to agents", text: $llmPrompt, axis: .vertical)
                    .lineLimit(3...8)
                    .help("Context about this terminal (never auto-cleared)")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Next Action (runs once)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Task to run on next open, then clear", text: $llmNextAction, axis: .vertical)
                    .lineLimit(3...8)
                    .help("Seeds into init command on next open, then clears")
            }
        }

        // TODO: Add Generate Init Command section here (Vendor, Non-interactive)
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
