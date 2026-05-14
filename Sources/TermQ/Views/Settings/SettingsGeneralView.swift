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
    @Binding var scrollbackLines: Int

    // Bin preferences
    @Binding var binRetentionDays: Int
    @ObservedObject var boardViewModel: BoardViewModel

    // Updater
    @ObservedObject var updaterViewModel: UpdaterViewModel

    // Language
    @Binding var selectedLanguage: SupportedLanguage

    // Uninstall sheet
    @Binding var showUninstallSheet: Bool

    // Git preferences
    @Binding var protectedBranches: String

    // Remote PR feed cap (GitHub)
    @Binding var remotePRFeedCap: Int

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
                    Text(localizedName(for: backend)).tag(backend)
                }
            }
            .help(Strings.Settings.fieldDefaultBackendHelp)

            ScrollbackField(lines: $scrollbackLines)
                .help(Strings.Settings.scrollbackLinesHelp)
        } header: {
            Text(Strings.Settings.sectionTerminal)
        }

        // Git section
        Section {
            TextField(
                Strings.Settings.protectedBranchesLabel,
                text: $protectedBranches,
                prompt: Text(Strings.Settings.protectedBranchesPrompt)
            )
            Text(Strings.Settings.protectedBranchesHelp)
                .font(.caption)
                .foregroundColor(.secondary)

            Stepper(
                value: $remotePRFeedCap,
                in: 5...100,
                step: 5
            ) {
                HStack {
                    Text(Strings.Settings.githubFeedCapLabel)
                    Spacer()
                    Text("\(remotePRFeedCap)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            Text(Strings.Settings.githubFeedCapHelp)
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text(Strings.Settings.sectionGit)
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
                        Text(Strings.Settings.debugUpdateWarningTitle)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(Strings.Settings.debugUpdateWarningMessage)
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
                value: Bundle.main.infoDictionary?["TermQBuildSHA"] as? String ?? "Unknown"
            )
        } header: {
            Text(Strings.Settings.sectionAbout)
        }
    }

    // MARK: - Backend Localization Helper

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
}

private struct ScrollbackField: View {
    @Binding var lines: Int
    @State private var text: String = ""

    private let range = 500...100_000

    private var parsedValue: Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }
    private var isInvalid: Bool {
        guard let value = parsedValue else { return !text.trimmingCharacters(in: .whitespaces).isEmpty }
        return !range.contains(value)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(Strings.Settings.scrollbackLabel)
                Spacer()
                TextField("", text: $text)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit() }
                    .onChange(of: text) { _, _ in
                        if let value = parsedValue, range.contains(value) { lines = value }
                    }
                Text(Strings.Settings.scrollbackUnit)
                    .foregroundColor(.secondary)
            }
            if isInvalid {
                Text(Strings.Settings.scrollbackInvalid)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .onAppear { text = "\(lines)" }
        .onDisappear { commit() }
    }

    private func commit() {
        if let value = parsedValue, range.contains(value) {
            lines = value
        } else {
            text = "\(lines)"
        }
    }
}
