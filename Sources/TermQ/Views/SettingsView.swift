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

    private enum SettingsTab: String, CaseIterable {
        case general = "General"
        case tools = "Tools"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Form {
                if selectedTab == .general {
                    generalContent
                } else {
                    toolsContent
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 700)
        .alert(alertIsError ? "Error" : "Success", isPresented: $showAlert) {
            Button("OK") {}
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
            Picker("Theme", selection: $sessionManager.themeId) {
                ForEach(TerminalTheme.allThemes) { theme in
                    HStack {
                        ThemePreviewSwatch(theme: theme)
                        Text(theme.name)
                    }
                    .tag(theme.id)
                }
            }
            .help("Color scheme for terminal windows")

            Toggle("Copy on select", isOn: $copyOnSelect)
                .help("Automatically copy selected text to clipboard")
        } header: {
            Text("Terminal")
        }

        Section {
            Stepper(
                "Auto-empty after \(binRetentionDays) days",
                value: $binRetentionDays,
                in: 1...90
            )
            .help("Deleted terminals are automatically removed after this many days")

            HStack {
                let binCount = boardViewModel.binCards.count
                Text(
                    binCount == 0
                        ? "Bin is empty" : "\(binCount) item\(binCount == 1 ? "" : "s") in bin"
                )
                .foregroundColor(.secondary)

                Spacer()

                Button("Empty Bin Now", role: .destructive) {
                    boardViewModel.emptyBin()
                }
                .disabled(boardViewModel.binCards.isEmpty)
            }
        } header: {
            Text("Bin")
        }

        Section {
            LabeledContent(
                "Version",
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            )
            LabeledContent(
                "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
        } header: {
            Text("About")
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
                        Text("Command Line Tool")
                            .font(.headline)
                        Text("termq - Open terminals from the command line")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if installedLocation != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Installed")
                                .foregroundColor(.green)
                        }
                        .font(.caption)
                    }
                }

                Divider()

                Toggle("Enable Terminal Autorun", isOn: $enableTerminalAutorun)
                    .help(
                        "Allow agents to run commands automatically when terminals open. Per-terminal setting must also be enabled."
                    )

                Divider()

                if let location = installedLocation {
                    // Already installed
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Location:")
                                .foregroundColor(.secondary)
                            Text(location.fullPath)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .font(.caption)

                        Text("Usage: termq open [--name \"My Terminal\"] [--column \"In Progress\"]")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)

                        HStack {
                            Button("Reinstall") {
                                installCLI()
                            }
                            .disabled(isInstalling)

                            Button("Uninstall", role: .destructive) {
                                uninstallCLI()
                            }
                            .disabled(isInstalling)
                        }
                    }
                } else {
                    // Not installed - show install options
                    VStack(alignment: .leading, spacing: 12) {
                        Text(
                            "The CLI tool allows you to open new terminals in TermQ from any terminal window."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Picker("Install to:", selection: $selectedLocation) {
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
                                Text(isInstalling ? "Installing..." : "Install Command Line Tool")
                            }
                        }
                        .disabled(isInstalling)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("CLI Tools")
        }

        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("MCP Server")
                            .font(.headline)
                        Text("termqmcp - Enable LLM assistants to access TermQ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if installedMCPLocation != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Installed")
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
                            Text("Location:")
                                .foregroundColor(.secondary)
                            Text(location.fullPath)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .font(.caption)

                        // Configuration section
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Claude Code Configuration:")
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
                                        Text(configCopied ? "Copied!" : "Copy")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        HStack {
                            Button("Reinstall") {
                                installMCPServer()
                            }
                            .disabled(isInstallingMCP)

                            Button("Uninstall", role: .destructive) {
                                uninstallMCPServer()
                            }
                            .disabled(isInstallingMCP)
                        }
                    }
                } else {
                    // Not installed - show install options
                    VStack(alignment: .leading, spacing: 12) {
                        Text(
                            "The MCP server enables AI assistants like Claude Code to interact with TermQ for cross-session workflow continuity."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("LOCAL USE ONLY: Do not expose to networks or deploy.")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }

                        Picker("Install to:", selection: $selectedMCPLocation) {
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
                                Text(isInstallingMCP ? "Installing..." : "Install MCP Server")
                            }
                        }
                        .disabled(isInstallingMCP)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("MCP Integration")
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
