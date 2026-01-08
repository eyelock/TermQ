import SwiftUI
import TermQCore

struct CardEditorView: View {
    @ObservedObject var card: TerminalCard
    let columns: [Column]
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var workingDirectory: String = ""
    @State private var shellPath: String = ""
    @State private var selectedColumnId: UUID = UUID()
    @State private var tags: [Tag] = []
    @State private var newTagKey: String = ""
    @State private var newTagValue: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Terminal")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveChanges()
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Basic Info") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)

                    Picker("Column", selection: $selectedColumnId) {
                        ForEach(columns) { column in
                            Text(column.name).tag(column.id)
                        }
                    }
                }

                Section("Terminal Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Working Directory")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Text(workingDirectory)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Browse...") {
                                browseDirectory()
                            }
                        }
                    }

                    TextField("Shell Path", text: $shellPath)
                        .help("e.g., /bin/zsh, /bin/bash")
                }

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
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 600, height: 550)
        .onAppear {
            loadFromCard()
        }
    }

    private func loadFromCard() {
        title = card.title
        description = card.description
        workingDirectory = card.workingDirectory
        shellPath = card.shellPath
        selectedColumnId = card.columnId
        tags = card.tags
    }

    private func saveChanges() {
        card.title = title
        card.description = description
        card.workingDirectory = workingDirectory
        card.shellPath = shellPath
        card.columnId = selectedColumnId
        card.tags = tags
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
