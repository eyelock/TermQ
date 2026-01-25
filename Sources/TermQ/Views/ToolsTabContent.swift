import AppKit
import SwiftUI

// MARK: - Tools Tab Content

struct ToolsTabContent: View {
    @Binding var selectedMCPLocation: MCPInstallLocation
    @Binding var installedMCPLocation: MCPInstallLocation?
    @Binding var isInstallingMCP: Bool
    @Binding var configCopied: Bool
    @Binding var useCustomMCPPath: Bool
    @Binding var customMCPPath: String
    @Binding var selectedLocation: InstallLocation
    @Binding var installedLocation: InstallLocation?
    @Binding var isInstalling: Bool
    @Binding var useCustomCLIPath: Bool
    @Binding var customCLIPath: String
    @Binding var enableTerminalAutorun: Bool
    @Binding var tmuxEnabled: Bool
    @Binding var tmuxAutoReattach: Bool

    let installMCPServer: () -> Void
    let uninstallMCPServer: () -> Void
    let copyMCPConfig: () -> Void
    let installCLI: () -> Void
    let uninstallCLI: () -> Void

    @ObservedObject private var boardViewModel = BoardViewModel.shared
    @ObservedObject private var tmuxManager = TmuxManager.shared

    var isCLIInstalled: Bool { CLIInstaller.currentInstallLocation != nil }
    var isMCPInstalled: Bool { MCPServerInstaller.currentInstallLocation != nil }

    var activeTmuxSessionCount: Int {
        boardViewModel.activeSessionCards.filter { cardId in
            guard boardViewModel.card(for: cardId) != nil else { return false }
            return TerminalSessionManager.shared.getBackend(for: cardId) == .tmux
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
            HStack {
                Text(Strings.Settings.mcpLocation)
                    .foregroundColor(.secondary)
                Text(location.fullPath)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.caption)

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

            Toggle("Use custom path", isOn: $useCustomMCPPath)
                .font(.caption)

            if useCustomMCPPath {
                PathInputField(
                    label: "Install Path",
                    path: $customMCPPath,
                    helpText: "Custom directory path for MCP server installation (e.g., ~/.local/bin)",
                    validatePath: true
                )
            } else {
                Picker(Strings.Settings.cliPath, selection: $selectedMCPLocation) {
                    ForEach(MCPInstallLocation.allCases) { location in
                        Text(location.displayName).tag(location)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(selectedMCPLocation.pathNote)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

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
            .disabled(isInstallingMCP || (useCustomMCPPath && customMCPPath.isEmpty))
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

                Toggle(Strings.Settings.enableTerminalAutorun, isOn: $enableTerminalAutorun)
                    .help(Strings.Settings.enableTerminalAutorunHelp)

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
    }

    @ViewBuilder
    var cliInstallContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.Settings.cliDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Use custom path", isOn: $useCustomCLIPath)
                .font(.caption)

            if useCustomCLIPath {
                PathInputField(
                    label: "Install Path",
                    path: $customCLIPath,
                    helpText: "Custom directory path for CLI installation (e.g., ~/.local/bin)",
                    validatePath: true
                )
            } else {
                Picker(Strings.Settings.cliPath, selection: $selectedLocation) {
                    ForEach(InstallLocation.allCases) { location in
                        Text(location.displayName).tag(location)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(selectedLocation.pathNote)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

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
            .disabled(isInstalling || (useCustomCLIPath && customCLIPath.isEmpty))
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
