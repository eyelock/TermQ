import AppKit
import SwiftUI

/// Data & Security settings tab content extracted from SettingsView
struct SettingsDataSecurityView: View {
    // Security preferences
    @Binding var enableTerminalAutorun: Bool
    @Binding var confirmExternalLLMModifications: Bool
    @Binding var allowOscClipboard: Bool

    // Data directory
    @Binding var dataDirectory: String

    var body: some View {
        // Security section (moved to top)
        Section {
            Toggle(Strings.Settings.enableTerminalAutorun, isOn: $enableTerminalAutorun)
                .help(Strings.Settings.enableTerminalAutorunHelp)

            Toggle(Strings.Settings.confirmExternalModifications, isOn: $confirmExternalLLMModifications)
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
