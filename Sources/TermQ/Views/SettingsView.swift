import AppKit
import SwiftUI

struct SettingsView: View {
    // Initial tab selection (for deep linking)
    var initialTab: SettingsTab?

    // CLI Tool installation state
    @State private var selectedLocation: InstallLocation = .usrLocalBin
    @State private var installedLocation: InstallLocation?
    @State private var isInstalling = false

    // MCP Server installation state
    @State private var selectedMCPLocation: MCPInstallLocation = .usrLocalBin
    @State private var installedMCPLocation: MCPInstallLocation?
    @State private var isInstallingMCP = false
    @State private var configCopied = false

    // Alert state
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var alertIsError = false

    // Terminal preferences
    @AppStorage("copyOnSelect") private var copyOnSelect = false
    @AppStorage("binRetentionDays") private var binRetentionDays = 14
    @AppStorage("enableTerminalAutorun") private var enableTerminalAutorun = false
    @AppStorage("tmuxEnabled") private var tmuxEnabled = true
    @AppStorage("tmuxAutoReattach") private var tmuxAutoReattach = true
    @ObservedObject private var sessionManager = TerminalSessionManager.shared
    @ObservedObject private var boardViewModel = BoardViewModel.shared
    @ObservedObject private var tmuxManager = TmuxManager.shared
    @State private var selectedTab: SettingsTab = .general

    // Language preferences
    @State private var selectedLanguage: SupportedLanguage = LanguageManager.currentLanguage

    // Data directory
    @State private var dataDirectory: String = DataDirectoryManager.displayPath

    enum SettingsTab: CaseIterable {
        case general
        case environment
        case tools
        case data

        var title: String {
            switch self {
            case .general: return Strings.Settings.tabGeneral
            case .environment: return Strings.Settings.tabEnvironment
            case .tools: return Strings.Settings.tabTools
            case .data: return Strings.Settings.tabData
            }
        }
    }

    // Uninstall sheet state
    @State private var showUninstallSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Form {
                switch selectedTab {
                case .general:
                    generalContent
                case .environment:
                    SettingsEnvironmentView()
                case .tools:
                    toolsContent
                case .data:
                    dataContent
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 750)
        .sheet(isPresented: $showUninstallSheet) {
            UninstallView()
        }
        .alert(alertIsError ? Strings.Alert.error : Strings.Alert.success, isPresented: $showAlert) {
            Button(Strings.Common.ok) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            if let initialTab = initialTab {
                selectedTab = initialTab
            }
            refreshInstallStatus()
            refreshMCPInstallStatus()
        }
    }

    init(initialTab: SettingsTab? = nil) {
        self.initialTab = initialTab
    }

    // MARK: - General Tab Content

    @ViewBuilder
    private var generalContent: some View {
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
        } header: {
            Text(Strings.Settings.sectionTerminal)
        }

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

        Section {
            HStack {
                Text(dataDirectory)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button(Strings.Common.browse) {
                    browseForDataDirectory()
                }
            }

            Text(Strings.Settings.dataDirectoryHelp)
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text(Strings.Settings.sectionDataDirectory)
        }

        Section {
            LanguagePickerView(selectedLanguage: $selectedLanguage)
        } header: {
            Text(Strings.Settings.sectionLanguage)
        }
    }

    // MARK: - Tools Tab Content

    @ViewBuilder
    private var toolsContent: some View {
        ToolsTabContent(
            selectedMCPLocation: $selectedMCPLocation,
            installedMCPLocation: $installedMCPLocation,
            isInstallingMCP: $isInstallingMCP,
            configCopied: $configCopied,
            selectedLocation: $selectedLocation,
            installedLocation: $installedLocation,
            isInstalling: $isInstalling,
            enableTerminalAutorun: $enableTerminalAutorun,
            tmuxEnabled: $tmuxEnabled,
            tmuxAutoReattach: $tmuxAutoReattach,
            installMCPServer: installMCPServer,
            uninstallMCPServer: uninstallMCPServer,
            copyMCPConfig: copyMCPConfig,
            installCLI: installCLI,
            uninstallCLI: uninstallCLI
        )
    }

    // MARK: - Data Tab Content

    @ViewBuilder
    private var dataContent: some View {
        BackupSettingsView()

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
    }

    private func refreshInstallStatus() {
        installedLocation = CLIInstaller.currentInstallLocation
    }

    private func installCLI() {
        isInstalling = true
        let location = installedLocation ?? selectedLocation
        Task {
            let result = await CLIInstaller.install(to: location)
            await MainActor.run {
                isInstalling = false
                switch result {
                case .success(let message):
                    alertMessage = message
                    alertIsError = false
                    showAlert = true
                    refreshInstallStatus()
                case .failure(let error):
                    if case .userCancelled = error {
                        return
                    }
                    alertMessage = error.localizedDescription
                    alertIsError = true
                    showAlert = true
                }
            }
        }
    }

    private func uninstallCLI() {
        guard let location = installedLocation else { return }
        isInstalling = true
        Task {
            let result = await CLIInstaller.uninstall(from: location)
            await MainActor.run {
                isInstalling = false
                switch result {
                case .success(let message):
                    alertMessage = message
                    alertIsError = false
                    showAlert = true
                    refreshInstallStatus()
                case .failure(let error):
                    if case .userCancelled = error {
                        return
                    }
                    alertMessage = error.localizedDescription
                    alertIsError = true
                    showAlert = true
                }
            }
        }
    }

    // MARK: - MCP Server Methods

    private func refreshMCPInstallStatus() {
        installedMCPLocation = MCPServerInstaller.currentInstallLocation
    }

    private func installMCPServer() {
        isInstallingMCP = true
        let location = installedMCPLocation ?? selectedMCPLocation
        Task {
            let result = await MCPServerInstaller.install(to: location)
            await MainActor.run {
                isInstallingMCP = false
                switch result {
                case .success(let message):
                    alertMessage = message
                    alertIsError = false
                    showAlert = true
                    refreshMCPInstallStatus()
                case .failure(let error):
                    if case .userCancelled = error {
                        return
                    }
                    alertMessage = error.localizedDescription
                    alertIsError = true
                    showAlert = true
                }
            }
        }
    }

    private func uninstallMCPServer() {
        guard let location = installedMCPLocation else { return }
        isInstallingMCP = true
        Task {
            let result = await MCPServerInstaller.uninstall(from: location)
            await MainActor.run {
                isInstallingMCP = false
                switch result {
                case .success(let message):
                    alertMessage = message
                    alertIsError = false
                    showAlert = true
                    refreshMCPInstallStatus()
                case .failure(let error):
                    if case .userCancelled = error {
                        return
                    }
                    alertMessage = error.localizedDescription
                    alertIsError = true
                    showAlert = true
                }
            }
        }
    }

    private func copyMCPConfig() {
        let config = MCPServerInstaller.generateClaudeCodeConfig()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
        configCopied = true
        // Reset the "Copied!" state after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            configCopied = false
        }
    }

    // MARK: - Data Directory

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

// MARK: - Theme Preview Swatch

struct ThemePreviewSwatch: View {
    let theme: TerminalTheme

    var body: some View {
        HStack(spacing: 1) {
            // Background sample
            Rectangle()
                .fill(Color(nsColor: theme.background))
                .frame(width: 12, height: 12)

            // Foreground sample
            Rectangle()
                .fill(Color(nsColor: theme.foreground))
                .frame(width: 12, height: 12)

            // A few ANSI colors
            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(Color(nsColor: theme.ansiColors[index + 1]))  // Skip black, show R/G/Y/B
                    .frame(width: 8, height: 12)
            }
        }
        .cornerRadius(3)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        )
    }
}
