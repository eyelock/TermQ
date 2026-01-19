import AppKit
import SwiftUI

/// Data & Security settings tab content extracted from SettingsView
struct SettingsDataSecurityView: View {
    // Security preferences
    @Binding var allowTerminalsToRunAgentPrompts: Bool
    @Binding var allowExternalLLMModifications: Bool
    @Binding var allowOscClipboard: Bool

    // Data directory
    @Binding var dataDirectory: String

    var body: some View {
        // Security section (moved to top)
        Section {
            Toggle("Allow Terminals to run Agent Prompts", isOn: $allowTerminalsToRunAgentPrompts)
                .help("Allow terminals to execute prompts from agent context (global setting)")

            Toggle(Strings.Settings.confirmExternalModifications, isOn: $allowExternalLLMModifications)
                .help(Strings.Settings.confirmExternalModificationsHelp)

            Toggle(Strings.Settings.allowOscClipboard, isOn: $allowOscClipboard)
                .help(Strings.Settings.allowOscClipboardHelp)
        } header: {
            Text(Strings.Settings.sectionSecurity)
        }

        // Data Storage section
        Section {
            VStack(alignment: .leading, spacing: 4) {
                // Line 1: Label with Browse button
                HStack {
                    Text(Strings.Settings.dataDirectory)
                        .foregroundColor(.primary)

                    Spacer()

                    Button(Strings.Common.browse) {
                        browseForDataDirectory()
                    }
                }

                // Line 2: Full-width path display (read-only)
                TextField("", text: $dataDirectory)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(true)
            }
            .help(Strings.Settings.dataDirectoryHelp)
        } header: {
            Text(Strings.Settings.sectionDataDirectory)
        }

        // Data Protection section
        BackupSettingsView()
    }

    private func browseForDataDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = Strings.Common.select
        panel.message = Strings.Settings.dataDirectory

        if panel.runModal() == .OK, let url = panel.url {
            DataDirectoryManager.dataDirectory = url.path
            dataDirectory = DataDirectoryManager.displayPath
        }
    }
}
