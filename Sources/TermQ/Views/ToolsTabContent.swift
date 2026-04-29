import AppKit
import SwiftUI
import TermQShared

// MARK: - Tools Tab Content

struct ToolsTabContent: View {
    @Binding var isInstallingMCP: Bool
    @Binding var configCopied: Bool
    @Binding var mcpInstallPath: String
    @Binding var mcpInstalled: Bool
    @Binding var isInstalling: Bool
    @Binding var cliInstallPath: String
    @Binding var cliInstalled: Bool

    @Environment(SettingsStore.self) private var settings

    let installMCPServer: () -> Void
    let uninstallMCPServer: () -> Void
    let copyMCPConfig: () -> Void
    let installCLI: () -> Void
    let uninstallCLI: () -> Void

    @ObservedObject private var boardViewModel = BoardViewModel.shared
    @ObservedObject private var tmuxManager = TmuxManager.shared
    @ObservedObject private var ynhDetector = YNHDetector.shared

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
        ynhSection
        agentSection
    }
}

// MARK: - Agent Loop Section

extension ToolsTabContent {
    @ViewBuilder
    var agentSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.Settings.Agent.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    Strings.Settings.Agent.enableAgentTab,
                    isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "feature.agentTab") },
                        set: { UserDefaults.standard.set($0, forKey: "feature.agentTab") }
                    )
                )
                .help(Strings.Settings.Agent.enableAgentTabHelp)
            }
            .padding(.vertical, 4)
        } header: {
            Text(Strings.Settings.Agent.sectionTitle)
        }
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
                status: tmuxManager.isAvailable
                    ? (settings.tmuxEnabled ? .ready : .disabled) : .inactive,
                message: {
                    if !tmuxManager.isAvailable {
                        return Strings.Settings.notInstalled
                    }
                    if settings.tmuxEnabled {
                        return "\(tmuxManager.version ?? "") · \(activeTmuxSessionCount) active"
                    }
                    return Strings.Settings.statusDisabled
                }()
            )

            StatusIndicator(
                icon: "puzzlepiece.extension",
                label: "ynh",
                status: ynhStatusIndicator,
                message: ynhStatusMessage
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
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 8) {
            Toggle(Strings.Settings.tmuxEnabled, isOn: $settings.tmuxEnabled)
                .help(Strings.Settings.tmuxEnabledHelp)

            Toggle(Strings.Settings.tmuxAutoReattach, isOn: $settings.tmuxAutoReattach)
                .help(Strings.Settings.tmuxAutoReattachHelp)
                .disabled(!settings.tmuxEnabled)

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

// MARK: - YNH Section

extension ToolsTabContent {
    var ynhStatusIndicator: StatusIndicatorState {
        switch ynhDetector.status {
        case .missing: return .inactive
        case .binaryOnly: return .disabled
        case .outdated: return .disabled
        case .ready: return .installed
        }
    }

    var ynhStatusMessage: String {
        switch ynhDetector.status {
        case .missing: return Strings.Settings.notInstalled
        case .binaryOnly: return Strings.Settings.Ynh.initRequired
        case .outdated: return Strings.Settings.Ynh.outdatedBadge
        case .ready: return Strings.Settings.Ynh.ready
        }
    }

    @ViewBuilder
    var ynhSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Strings.Settings.Ynh.title)
                            .font(.headline)
                        Text(Strings.Settings.Ynh.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if case .ready = ynhDetector.status {
                        installedBadge
                    } else if case .binaryOnly = ynhDetector.status {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(Strings.Settings.Ynh.initRequired)
                                .foregroundColor(.orange)
                        }
                        .font(.caption)
                    } else if case .outdated = ynhDetector.status {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle")
                                .foregroundColor(.orange)
                            Text(Strings.Settings.Ynh.outdatedBadge)
                                .foregroundColor(.orange)
                        }
                        .font(.caption)
                    } else {
                        notInstalledBadge
                    }
                }

                Divider()

                ynhSettingsContent
            }
            .padding(.vertical, 4)
        } header: {
            Text(Strings.Settings.Ynh.sectionTitle)
        }
        .onAppear {
            Task { await ynhDetector.detect() }
        }
    }

    @ViewBuilder
    private var ynhSettingsContent: some View {
        // Feature flag toggle
        Toggle(
            Strings.Settings.Ynh.enableHarnessTab,
            isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "feature.harnessTab") },
                set: { UserDefaults.standard.set($0, forKey: "feature.harnessTab") }
            )
        )
        .help(Strings.Settings.Ynh.enableHarnessTabHelp)

        // Detected binary info (mirrors the tmux Version/Path pattern)
        ynhBinaryInfo

        // Read-only paths echo (only when ready)
        if case .ready(_, _, let paths) = ynhDetector.status {
            ynhPathsDisplay(paths)
        }

        // Advanced: YNH_HOME override
        DisclosureGroup(Strings.Settings.Ynh.advanced) {
            ynhHomeOverrideField
                .padding(.top, 4)
        }

        // Re-detect button
        HStack {
            Spacer()
            Button {
                Task { await ynhDetector.detect() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text(Strings.Settings.Ynh.redetect)
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var ynhBinaryInfo: some View {
        switch ynhDetector.status {
        case .missing:
            Link(
                Strings.Settings.Ynh.docsLinkLabel,
                // swiftlint:disable:next force_unwrapping
                destination: URL(string: "https://eyelock.github.io/ynh")!
            )
            .font(.caption)

        case .binaryOnly(let ynhPath):
            VStack(alignment: .leading, spacing: 4) {
                if let version = ynhDetector.version {
                    HStack {
                        Text(Strings.Settings.Ynh.versionLabel)
                            .foregroundColor(.secondary)
                        Text(version)
                            .font(.system(.body, design: .monospaced))
                    }
                    .font(.caption)
                }

                HStack {
                    Text(Strings.Settings.Ynh.pathLabel)
                        .foregroundColor(.secondary)
                    Text(ynhPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.caption)

                HStack {
                    Text(Strings.Settings.Ynh.statusLabel)
                        .foregroundColor(.secondary)
                    Text(Strings.Settings.Ynh.initRequired)
                        .foregroundColor(.orange)
                }
                .font(.caption)
            }

        case .outdated(let ynhPath, _, let capabilities):
            VStack(alignment: .leading, spacing: 4) {
                if let version = ynhDetector.version {
                    HStack {
                        Text(Strings.Settings.Ynh.versionLabel)
                            .foregroundColor(.secondary)
                        Text(version)
                            .font(.system(.body, design: .monospaced))
                    }
                    .font(.caption)
                }

                HStack {
                    Text(Strings.Settings.Ynh.pathLabel)
                        .foregroundColor(.secondary)
                    Text(ynhPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.caption)

                HStack {
                    Text(Strings.Settings.Ynh.capabilitiesLabel)
                        .foregroundColor(.secondary)
                    Text(
                        Strings.Settings.Ynh.capabilitiesBelowMinimum(
                            reported: capabilities ?? Strings.Settings.Ynh.capabilitiesUnknown,
                            minimum: YNHDetector.minimumCapabilitiesVersion
                        )
                    )
                    .foregroundColor(.orange)
                }
                .font(.caption)
            }

        case .ready(let ynhPath, let yndPath, _):
            VStack(alignment: .leading, spacing: 4) {
                if let version = ynhDetector.version {
                    HStack {
                        Text(Strings.Settings.Ynh.versionLabel)
                            .foregroundColor(.secondary)
                        Text(version)
                            .font(.system(.body, design: .monospaced))
                    }
                    .font(.caption)
                }

                HStack {
                    Text(Strings.Settings.Ynh.pathLabel)
                        .foregroundColor(.secondary)
                    Text(ynhPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.caption)

                // Only show ynd path if it differs from the ynh directory
                if let yndPath, yndDirectory(yndPath) != yndDirectory(ynhPath) {
                    HStack {
                        Text(Strings.Settings.Ynh.yndPathLabel)
                            .foregroundColor(.secondary)
                        Text(yndPath)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                }

                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text(Strings.Settings.Ynh.readyInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// Extract the parent directory from a binary path for comparison.
    private func yndDirectory(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    @ViewBuilder
    private var ynhHomeOverrideField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Strings.Settings.Ynh.homeOverride)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if ynhDetector.ynhHomeOverride != nil {
                    Button(Strings.Common.clear, role: .destructive) {
                        ynhDetector.ynhHomeOverride = nil
                        Task { await ynhDetector.detect() }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }

            TextField(
                Strings.Settings.Ynh.homeOverridePlaceholder,
                text: Binding(
                    get: { ynhDetector.ynhHomeOverride ?? "" },
                    set: { newValue in
                        ynhDetector.ynhHomeOverride = newValue.isEmpty ? nil : newValue
                    }
                )
            )
            .font(.system(.caption, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                Task { await ynhDetector.detect() }
            }

            Text(Strings.Settings.Ynh.homeOverrideHelp)
                .font(.caption2)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
    }

    @ViewBuilder
    private func ynhPathsDisplay(_ paths: YNHPaths) -> some View {
        DisclosureGroup(Strings.Settings.Ynh.resolvedPaths) {
            VStack(alignment: .leading, spacing: 4) {
                pathRow(label: "home", value: paths.home)
                pathRow(label: "config", value: paths.config)
                pathRow(label: "harnesses", value: paths.harnesses)
                pathRow(label: "symlinks", value: paths.symlinks)
                pathRow(label: "cache", value: paths.cache)
                pathRow(label: "run", value: paths.run)
                pathRow(label: "bin", value: paths.bin)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func pathRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
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
