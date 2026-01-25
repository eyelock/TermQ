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
            PathInputField(
                label: Strings.Settings.dataDirectory,
                path: $dataDirectory,
                helpText: Strings.Settings.dataDirectoryHelp,
                validatePath: true
            )
            .onChange(of: dataDirectory) { _, newValue in
                // Update DataDirectoryManager when path changes
                DataDirectoryManager.dataDirectory = newValue
            }
        } header: {
            Text(Strings.Settings.sectionDataDirectory)
        }

        // Data Protection section
        BackupSettingsView()
    }
}
