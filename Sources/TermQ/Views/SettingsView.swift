import AppKit
import Sparkle
import SwiftUI
import TermQCore

struct SettingsView: View {
    // Initial tab selection (for deep linking)
    var initialTab: SettingsTab?

    // Settings navigation coordinator
    @ObservedObject private var coordinator = SettingsCoordinator.shared

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
    @AppStorage("defaultWorkingDirectory") private var defaultWorkingDirectory = NSHomeDirectory()
    @AppStorage("defaultBackend") private var defaultBackendRawValue: String = "direct"

    // Computed property to convert between String and TerminalBackend
    private var defaultBackend: TerminalBackend {
        get { TerminalBackend(rawValue: defaultBackendRawValue) ?? .direct }
        set { defaultBackendRawValue = newValue.rawValue }
    }

    // Security preferences
    @AppStorage("allowTerminalsToRunAgentPrompts") private var allowTerminalsToRunAgentPrompts = false
    @AppStorage("allowExternalLLMModifications") private var allowExternalLLMModifications = false
    @AppStorage("allowOscClipboard") private var allowOscClipboard = false
    @ObservedObject private var sessionManager = TerminalSessionManager.shared
    @ObservedObject private var boardViewModel = BoardViewModel.shared
    @ObservedObject private var tmuxManager = TmuxManager.shared
    @State private var selectedTab: SettingsTab = .general

    // Language preferences
    @State private var selectedLanguage: SupportedLanguage = LanguageManager.currentLanguage

    // Data directory
    @State private var dataDirectory: String = DataDirectoryManager.displayPath

    // Updater (Sparkle)
    @StateObject private var updaterViewModel =
        UpdaterViewModel.shared
        ?? UpdaterViewModel(
            updater: SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil
            ).updater
        )

    enum SettingsTab: CaseIterable {
        case general
        case environment
        case tools
        case dataAndSecurity

        var title: String {
            switch self {
            case .general: return Strings.Settings.tabGeneral
            case .environment: return Strings.Settings.tabEnvironment
            case .tools: return Strings.Settings.tabTools
            case .dataAndSecurity: return Strings.Settings.tabDataAndSecurity
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
                    SettingsGeneralView(
                        sessionManager: sessionManager,
                        copyOnSelect: $copyOnSelect,
                        defaultWorkingDirectory: $defaultWorkingDirectory,
                        defaultBackend: Binding(
                            get: { defaultBackend },
                            set: { newValue in defaultBackendRawValue = newValue.rawValue }
                        ),
                        binRetentionDays: $binRetentionDays,
                        boardViewModel: boardViewModel,
                        updaterViewModel: updaterViewModel,
                        selectedLanguage: $selectedLanguage,
                        showUninstallSheet: $showUninstallSheet
                    )
                case .environment:
                    SettingsEnvironmentView()
                case .tools:
                    toolsContent
                case .dataAndSecurity:
                    SettingsDataSecurityView(
                        allowTerminalsToRunAgentPrompts: $allowTerminalsToRunAgentPrompts,
                        allowExternalLLMModifications: $allowExternalLLMModifications,
                        allowOscClipboard: $allowOscClipboard,
                        dataDirectory: $dataDirectory
                    )
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
            // Check coordinator first (for navigation from other views)
            if let requestedTab = coordinator.requestedTab {
                selectedTab = requestedTab
                coordinator.clearRequest()
            } else if let initialTab = initialTab {
                // Fall back to initialTab (for deep linking)
                selectedTab = initialTab
            }
            refreshInstallStatus()
            refreshMCPInstallStatus()
        }
    }

    init(initialTab: SettingsTab? = nil) {
        self.initialTab = initialTab
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
