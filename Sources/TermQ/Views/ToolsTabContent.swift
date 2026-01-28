import AppKit
import SwiftUI

// MARK: - Tools Tab Content

struct ToolsTabContent: View {
    @Binding var isInstallingMCP: Bool
    @Binding var configCopied: Bool
    @Binding var mcpInstallPath: String
    @Binding var mcpInstalled: Bool
    @Binding var isInstalling: Bool
    @Binding var cliInstallPath: String
    @Binding var cliInstalled: Bool

    // Use @AppStorage directly instead of @Binding to ensure persistence
    @AppStorage("tmuxEnabled") private var tmuxEnabled = true
    @AppStorage("tmuxAutoReattach") private var tmuxAutoReattach = true

    let installMCPServer: () -> Void
    let uninstallMCPServer: () -> Void
    let copyMCPConfig: () -> Void
    let installCLI: () -> Void
    let uninstallCLI: () -> Void

    @ObservedObject private var boardViewModel = BoardViewModel.shared
    @ObservedObject private var tmuxManager = TmuxManager.shared

    var isCLIInstalled: Bool { cliInstalled }
    var isMCPInstalled: Bool { mcpInstalled }
    var installedLocation: InstallLocation? { CLIInstaller.currentInstallLocation }
    var installedMCPLocation: MCPInstallLocation? { MCPServerInstaller.currentInstallLocation }

    var activeTmuxSessionCount: Int {
        boardViewModel.activeSessionCards.filter { cardId in
            guard boardViewModel.card(for: cardId) != nil else { return false }
            return TerminalSessionManager.shared.getBackend(for: cardId)?.usesTmux ?? false
        }.count
    }

    var body: some View {
        statusSection
        mcpSection
        cliSection
        tmuxSection
    }
}

// MARK: - Status Section

extension ToolsTabContent {
    @ViewBuilder
    var statusSection: some View {
        Section {
            StatusIndicator(
                icon: "server.rack",
                label: Strings.Settings.mcpTitle,
                status: isMCPInstalled ? .installed : .inactive,
                message: isMCPInstalled ? Strings.Settings.cliInstalled : Strings.Settings.notInstalled
            )

            StatusIndicator(
                icon: "terminal",
                label: Strings.Settings.cliTitle,
                status: isCLIInstalled ? .installed : .inactive,
                message: isCLIInstalled ? Strings.Settings.cliInstalled : Strings.Settings.notInstalled
            )

            StatusIndicator(
                icon: "rectangle.split.3x3",
                label: "tmux",
                status: tmuxManager.isAvailable ? (tmuxEnabled ? .ready : .disabled) : .inactive,
                message: {
                    if !tmuxManager.isAvailable {
                        return Strings.Settings.notInstalled
                    }
                    if tmuxEnabled {
                        return "\(tmuxManager.version ?? "") · \(activeTmuxSessionCount) active"
                    }
                    return Strings.Settings.statusDisabled
                }()
            )
        } header: {
            Text(Strings.Settings.sectionStatus)
        }
    }
}

// MARK: - MCP Section

extension ToolsTabContent {
    @ViewBuilder
    var mcpSection: some View {
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
                        installedBadge
                    }
                }

                Divider()

                if let location = installedMCPLocation {
                    mcpInstalledContent(location: location)
                } else {
                    mcpInstallContent
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(Strings.Settings.sectionMcp)
        }
    }

    @ViewBuilder
    func mcpInstalledContent(location: MCPInstallLocation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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

            Divider()

            PathInputField(
                label: "Install Path",
                path: $mcpInstallPath,
                helpText: "Directory path for MCP server installation (e.g., /usr/local/bin)",
                validatePath: true
            )

            HStack {
                Button(Strings.Common.reinstall) {
                    installMCPServer()
                }
                .disabled(isInstallingMCP || mcpInstallPath.isEmpty)

                Button(Strings.Common.uninstall, role: .destructive) {
                    uninstallMCPServer()
                }
                .disabled(isInstallingMCP)
            }
        }
    }

    @ViewBuilder
    var mcpInstallContent: some View {
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

            PathInputField(
                label: "Install Path",
                path: $mcpInstallPath,
                helpText: "Directory path for MCP server installation (e.g., /usr/local/bin)",
                validatePath: true
            )

            Button {
                installMCPServer()
            } label: {
                HStack {
                    if isInstallingMCP {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(Strings.Settings.mcpInstall)
                }
            }
            .disabled(isInstallingMCP || mcpInstallPath.isEmpty)
        }
    }
}

// MARK: - CLI Section

extension ToolsTabContent {
    @ViewBuilder
    var cliSection: some View {
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
                        installedBadge
                    }
                }

                Divider()

                if let location = installedLocation {
                    cliInstalledContent(location: location)
                } else {
                    cliInstallContent
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(Strings.Settings.sectionCli)
        }
    }

    @ViewBuilder
    func cliInstalledContent(location: InstallLocation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Settings.cliUsage)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            Divider()

            PathInputField(
                label: "Install Path",
                path: $cliInstallPath,
                helpText: "Directory path for CLI installation (e.g., /usr/local/bin)",
                validatePath: true
            )

            HStack {
                Button(Strings.Common.reinstall) {
                    installCLI()
                }
                .disabled(isInstalling || cliInstallPath.isEmpty)

                Button(Strings.Common.uninstall, role: .destructive) {
                    uninstallCLI()
                }
                .disabled(isInstalling)
            }
        }
    }

    @ViewBuilder
    var cliInstallContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.Settings.cliDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            PathInputField(
                label: "Install Path",
                path: $cliInstallPath,
                helpText: "Directory path for CLI installation (e.g., /usr/local/bin)",
                validatePath: true
            )

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
            .disabled(isInstalling || cliInstallPath.isEmpty)
        }
    }
}

// MARK: - tmux Section

extension ToolsTabContent {
    @ViewBuilder
    var tmuxSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "rectangle.split.3x3")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("tmux")
                            .font(.headline)
                        Text(Strings.Settings.tmuxDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if tmuxManager.isAvailable {
                        installedBadge
                    } else {
                        notInstalledBadge
                    }
                }

                Divider()

                if tmuxManager.isAvailable {
                    tmuxAvailableContent
                } else {
                    tmuxNotAvailableContent
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(Strings.Settings.sectionTmux)
        }
    }

    @ViewBuilder
    var tmuxAvailableContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(Strings.Settings.tmuxEnabled, isOn: $tmuxEnabled)
                .help(Strings.Settings.tmuxEnabledHelp)

            Toggle(Strings.Settings.tmuxAutoReattach, isOn: $tmuxAutoReattach)
                .help(Strings.Settings.tmuxAutoReattachHelp)
                .disabled(!tmuxEnabled)

            Divider()

            HStack {
                Text(Strings.Settings.tmuxVersion)
                    .foregroundColor(.secondary)
                Text(tmuxManager.version ?? "Unknown")
                    .font(.system(.body, design: .monospaced))
            }
            .font(.caption)

            if let path = tmuxManager.tmuxPath {
                HStack {
                    Text(Strings.Settings.tmuxPath)
                        .foregroundColor(.secondary)
                    Text(path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.caption)
            }

            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text(Strings.Settings.tmuxInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    var tmuxNotAvailableContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Settings.tmuxNotInstalledDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(Strings.Settings.tmuxInstallHint)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("brew install tmux")
                    .font(.system(.body, design: .monospaced))
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install tmux", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .help(Strings.Settings.copyToClipboard)
            }

            Button(Strings.Settings.tmuxCheckAgain) {
                Task {
                    await tmuxManager.detectTmux()
                }
            }
            .font(.caption)
        }
    }
}

// MARK: - Helper Views

extension ToolsTabContent {
    var installedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(Strings.Common.installed)
                .foregroundColor(.green)
        }
        .font(.caption)
    }

    var notInstalledBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "xmark.circle")
                .foregroundColor(.secondary)
            Text(Strings.Settings.notInstalled)
                .foregroundColor(.secondary)
        }
        .font(.caption)
    }
}
