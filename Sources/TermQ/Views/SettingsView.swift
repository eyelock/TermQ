import AppKit
import SwiftUI

struct SettingsView: View {
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
    @ObservedObject private var sessionManager = TerminalSessionManager.shared
    @ObservedObject private var boardViewModel = BoardViewModel.shared
    @State private var selectedTab: SettingsTab = .general

    // Language preferences
    @State private var selectedLanguage: SupportedLanguage = LanguageManager.currentLanguage

    private enum SettingsTab: CaseIterable {
        case general
        case tools
        case data

        var title: String {
            switch self {
            case .general: return Strings.Settings.tabGeneral
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
            refreshInstallStatus()
            refreshMCPInstallStatus()
        }
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
            LanguagePickerView(selectedLanguage: $selectedLanguage)
        } header: {
            Text(Strings.Settings.sectionLanguage)
        }
    }

    // MARK: - Tools Tab Content

    @ViewBuilder
    private var toolsContent: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "terminal")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Strings.Settings.cliTitle)
                            .font(.headline)
                        Text(Strings.Settings.cliDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if installedLocation != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(Strings.Settings.cliInstalled)
                                .foregroundColor(.green)
                        }
                        .font(.caption)
                    }
                }

                Divider()

                Toggle(Strings.Settings.enableTerminalAutorun, isOn: $enableTerminalAutorun)
                    .help(Strings.Settings.enableTerminalAutorunHelp)

                Divider()

                if let location = installedLocation {
                    // Already installed
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Strings.Settings.cliLocation)
                                .foregroundColor(.secondary)
                            Text(location.fullPath)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .font(.caption)

                        Text(Strings.Settings.cliUsage)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)

                        HStack {
                            Button(Strings.Common.reinstall) {
                                installCLI()
                            }
                            .disabled(isInstalling)

                            Button(Strings.Common.uninstall, role: .destructive) {
                                uninstallCLI()
                            }
                            .disabled(isInstalling)
                        }
                    }
                } else {
                    // Not installed - show install options
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Strings.Settings.cliDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker(Strings.Settings.cliPath, selection: $selectedLocation) {
                            ForEach(InstallLocation.allCases) { location in
                                Text(location.displayName).tag(location)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Text(selectedLocation.pathNote)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Button {
                            installCLI()
                        } label: {
                            HStack {
                                if isInstalling {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(Strings.Settings.cliInstall)
                            }
                        }
                        .disabled(isInstalling)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(Strings.Settings.sectionCli)
        }

        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Strings.Settings.mcpTitle)
                            .font(.headline)
                        Text(Strings.Settings.mcpDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if installedMCPLocation != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(Strings.Common.installed)
                                .foregroundColor(.green)
                        }
                        .font(.caption)
                    }
                }

                Divider()

                if let location = installedMCPLocation {
                    // Already installed
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Strings.Settings.mcpLocation)
                                .foregroundColor(.secondary)
                            Text(location.fullPath)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .font(.caption)

                        // Configuration section
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Strings.Settings.mcpClaudeConfig)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(alignment: .top) {
                                Text(MCPServerInstaller.generateClaudeCodeConfig())
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                    .padding(6)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)

                                Button {
                                    copyMCPConfig()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: configCopied ? "checkmark" : "doc.on.doc")
                                        Text(configCopied ? Strings.Settings.configCopied : Strings.Settings.copyConfig)
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        HStack {
                            Button(Strings.Common.reinstall) {
                                installMCPServer()
                            }
                            .disabled(isInstallingMCP)

                            Button(Strings.Common.uninstall, role: .destructive) {
                                uninstallMCPServer()
                            }
                            .disabled(isInstallingMCP)
                        }
                    }
                } else {
                    // Not installed - show install options
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Strings.Settings.mcpInstallDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(Strings.Settings.mcpLocalOnly)
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }

                        Picker(Strings.Settings.cliPath, selection: $selectedMCPLocation) {
                            ForEach(MCPInstallLocation.allCases) { location in
                                Text(location.displayName).tag(location)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Text(selectedMCPLocation.pathNote)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Button {
                            installMCPServer()
                        } label: {
                            HStack {
                                if isInstallingMCP {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(Strings.Settings.cliInstall)
                            }
                        }
                        .disabled(isInstallingMCP)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(Strings.Settings.sectionMcp)
        }
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
