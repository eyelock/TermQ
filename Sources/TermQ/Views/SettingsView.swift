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
    @State private var isInstalling = false
    @State private var cliInstallPath = "/usr/local/bin"
    @State private var cliInstalled = false

    // MCP Server installation state
    @State private var isInstallingMCP = false
    @State private var configCopied = false
    @State private var mcpInstallPath = "/usr/local/bin"
    @State private var mcpInstalled = false

    // Alert state
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var alertIsError = false

    // Git preferences
    @ObservedObject private var gitConfig = GitConfigStore.shared

    @Environment(SettingsStore.self) private var settings
    @ObservedObject private var sessionManager = TerminalSessionManager.shared
    @ObservedObject private var boardViewModel = BoardViewModel.shared
    @ObservedObject private var tmuxManager = TmuxManager.shared
    @State private var selectedTab: SettingsTab = .general

    // Language preferences
    @State private var selectedLanguage: SupportedLanguage = LanguageManager.currentLanguage

    // Data directory
    @State private var dataDirectory: String = DataDirectoryManager.displayPath

    // Updater (Sparkle) - injected from app level
    @EnvironmentObject var updaterViewModel: UpdaterViewModel

    enum SettingsTab: CaseIterable {
        case general
        case environment
        case tools
        case dataAndSecurity
        case marketplaces
        case gitHub

        var title: String {
            switch self {
            case .general: return Strings.Settings.tabGeneral
            case .environment: return Strings.Settings.tabEnvironment
            case .tools: return Strings.Settings.tabTools
            case .dataAndSecurity: return Strings.Settings.tabDataAndSecurity
            case .marketplaces: return Strings.Settings.tabMarketplaces
            case .gitHub: return Strings.Settings.tabGitHub
            }
        }
    }

    // Uninstall sheet state
    @State private var showUninstallSheet = false

    var body: some View {
        @Bindable var settings = settings
        return VStack(spacing: 0) {
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
                        copyOnSelect: $settings.copyOnSelect,
                        defaultWorkingDirectory: $settings.defaultWorkingDirectory,
                        defaultBackend: $settings.backend,
                        scrollbackLines: $settings.terminalScrollbackLines,
                        binRetentionDays: $settings.binRetentionDays,
                        boardViewModel: boardViewModel,
                        updaterViewModel: updaterViewModel,
                        selectedLanguage: $selectedLanguage,
                        showUninstallSheet: $showUninstallSheet,
                        protectedBranches: $gitConfig.globalProtectedBranches
                    )
                case .environment:
                    SettingsEnvironmentView()
                case .tools:
                    toolsContent
                case .dataAndSecurity:
                    SettingsDataSecurityView(
                        enableTerminalAutorun: $settings.enableTerminalAutorun,
                        confirmExternalLLMModifications: $settings.confirmExternalLLMModifications,
                        allowOscClipboard: $settings.allowOscClipboard,
                        defaultSafePaste: $settings.safePaste,
                        dataDirectory: $dataDirectory
                    )
                case .marketplaces:
                    SettingsMarketplacesView()
                case .gitHub:
                    SettingsGitHubView(remotePRFeedCap: $settings.remotePRFeedCap)
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
            if let requestedTab = coordinator.requestedTab {
                selectedTab = requestedTab
                coordinator.clearRequest()
            } else if let initialTab = initialTab {
                selectedTab = initialTab
            }
            refreshInstallStatus()
            refreshMCPInstallStatus()
        }
        .onChange(of: coordinator.requestedTab) { _, tab in
            if let tab {
                selectedTab = tab
                coordinator.clearRequest()
            }
        }
    }

    init(initialTab: SettingsTab? = nil) {
        self.initialTab = initialTab
    }

    // MARK: - Tools Tab Content

    @ViewBuilder
    private var toolsContent: some View {
        ToolsTabContent(
            isInstallingMCP: $isInstallingMCP,
            configCopied: $configCopied,
            mcpInstallPath: $mcpInstallPath,
            mcpInstalled: $mcpInstalled,
            isInstalling: $isInstalling,
            cliInstallPath: $cliInstallPath,
            cliInstalled: $cliInstalled,
            installMCPServer: installMCPServer,
            uninstallMCPServer: uninstallMCPServer,
            copyMCPConfig: copyMCPConfig,
            installCLI: installCLI,
            uninstallCLI: uninstallCLI
        )
    }

    private func refreshInstallStatus() {
        if let location = CLIInstaller.currentInstallLocation {
            TermQLogger.ui.info("refreshInstallStatus CLI found path=\(location.path)")
            cliInstallPath = location.path
            cliInstalled = true
        } else {
            TermQLogger.ui.info("refreshInstallStatus CLI not detected")
            cliInstallPath = "/usr/local/bin"
            cliInstalled = false
        }
    }

    private func installCLI() {
        isInstalling = true
        Task {
            // Always install to the path specified in cliInstallPath
            let result = await CLIInstaller.install(toPath: cliInstallPath, requiresAdmin: nil)

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
        guard let location = CLIInstaller.currentInstallLocation else { return }
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
        if let location = MCPServerInstaller.currentInstallLocation {
            mcpInstallPath = location.path
            mcpInstalled = true
        } else {
            mcpInstallPath = "/usr/local/bin"
            mcpInstalled = false
        }
    }

    private func installMCPServer() {
        isInstallingMCP = true
        Task {
            // Always install to the path specified in mcpInstallPath
            let result = await MCPServerInstaller.install(toPath: mcpInstallPath, requiresAdmin: nil)

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
        guard let location = MCPServerInstaller.currentInstallLocation else { return }
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
