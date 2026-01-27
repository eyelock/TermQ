import AppKit
import Sparkle
import SwiftUI
import TermQCore

/// General settings tab content extracted from SettingsView
struct SettingsGeneralView: View {
    // Session manager for theme
    @ObservedObject var sessionManager: TerminalSessionManager

    // Terminal preferences
    @Binding var copyOnSelect: Bool
    @Binding var defaultWorkingDirectory: String
    @Binding var defaultBackend: TerminalBackend

    // Bin preferences
    @Binding var binRetentionDays: Int
    @ObservedObject var boardViewModel: BoardViewModel

    // Updater
    @ObservedObject var updaterViewModel: UpdaterViewModel

    // Language
    @Binding var selectedLanguage: SupportedLanguage

    // Uninstall sheet
    @Binding var showUninstallSheet: Bool

    var body: some View {
        // Terminal section
        Section {
            Picker(Strings.Settings.fieldTheme, selection: $sessionManager.themeId) {
                ForEach(TerminalTheme.allThemes) { theme in
                    HStack {
                        ThemePreviewSwatch(theme: theme)
                        Text(theme.name)
                    }
                    .tag(theme.id)
                }
            }
            .help(Strings.Settings.fieldThemeHelp)

            Toggle(Strings.Settings.fieldCopyOnSelect, isOn: $copyOnSelect)
                .help(Strings.Settings.fieldCopyOnSelectHelp)

            PathInputField(
                label: Strings.Settings.fieldDefaultWorkingDirectory,
                path: $defaultWorkingDirectory,
                helpText: Strings.Settings.fieldDefaultWorkingDirectoryHelp,
                validatePath: true
            )

            Picker(
                Strings.Settings.fieldDefaultBackend,
                selection: $defaultBackend
            ) {
                ForEach(TerminalBackend.allCases, id: \.self) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            .help(Strings.Settings.fieldDefaultBackendHelp)
        } header: {
            Text(Strings.Settings.sectionTerminal)
        }

        // Bin section
        Section {
            Stepper(
                Strings.Settings.autoEmpty(binRetentionDays),
                value: $binRetentionDays,
                in: 1...90
            )
            .help(Strings.Settings.autoEmptyHelp)

            HStack {
                let binCount = boardViewModel.binCards.count
                Text(
                    binCount == 0
                        ? Strings.Settings.binEmpty : Strings.Settings.binItems(binCount)
                )
                .foregroundColor(.secondary)

                Spacer()

                Button(Strings.Settings.emptyBinNow, role: .destructive) {
                    boardViewModel.emptyBin()
                }
                .disabled(boardViewModel.binCards.isEmpty)
            }
        } header: {
            Text(Strings.Settings.sectionBin)
        }

        // Updates section
        Section {
            #if DEBUG
            // Warning for debug builds
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debug Build Warning")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Proceeding with updates will install the Production version of TermQ.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
            #endif

            Toggle(Strings.Settings.autoCheckUpdates, isOn: $updaterViewModel.automaticallyChecksForUpdates)
                .help(Strings.Settings.autoCheckUpdatesHelp)

            Toggle(Strings.Settings.includeBetaReleases, isOn: $updaterViewModel.includeBetaReleases)
                .help(Strings.Settings.includeBetaReleasesHelp)

            HStack {
                Spacer()
                Button(Strings.Settings.checkForUpdates) {
                    updaterViewModel.checkForUpdates()
                }
                .disabled(!updaterViewModel.canCheckForUpdates)
            }
        } header: {
            Text(Strings.Settings.sectionUpdates)
        }

        // Language section
        Section {
            LanguagePickerView(selectedLanguage: $selectedLanguage)
        } header: {
            Text(Strings.Settings.sectionLanguage)
        }

        // Uninstall section (moved from Data & Security)
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Strings.Uninstall.title)
                            .font(.headline)
                        Text(Strings.Uninstall.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                Divider()

                Text(Strings.Uninstall.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(Strings.Uninstall.buttonTitle, role: .destructive) {
                    showUninstallSheet = true
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(Strings.Uninstall.sectionHeader)
        }

        // About section (moved to end)
        Section {
            LabeledContent(
                Strings.Settings.fieldVersion,
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            )
            LabeledContent(
                Strings.Settings.fieldBuild,
                value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
            )
        } header: {
            Text(Strings.Settings.sectionAbout)
        }
    }
}
