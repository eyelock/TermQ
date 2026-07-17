import AppKit
import SwiftUI
import TermQShared

// MARK: - git-spice Section

extension ToolsTabContent {
    var gitSpiceStatusIndicator: StatusIndicatorState {
        switch stackService.availability {
        case .missing: return .inactive
        case .unusable: return .disabled
        case .ready: return .ready
        }
    }

    var gitSpiceStatusMessage: String {
        switch stackService.availability {
        case .missing:
            return Strings.Settings.notInstalled
        case .unusable(let reason):
            return Strings.Settings.GitSpice.statusUnusable(reason)
        case .ready(let version):
            return version
        }
    }

    @ViewBuilder
    var gitSpiceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Strings.Settings.GitSpice.title)
                            .font(.headline)
                        Text(Strings.Settings.GitSpice.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if case .ready = stackService.availability {
                        installedBadge
                    } else if case .unusable = stackService.availability {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(Strings.Settings.notInstalled)
                                .foregroundColor(.orange)
                        }
                        .font(.caption)
                    } else {
                        notInstalledBadge
                    }
                }

                Divider()

                if case .missing = stackService.availability {
                    gitSpiceNotAvailableContent
                } else {
                    gitSpiceAvailableContent
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(Strings.Settings.GitSpice.section)
        }
        .onAppear {
            Task { await stackService.probe() }
        }
    }

    @ViewBuilder
    var gitSpiceAvailableContent: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 8) {
            if case .ready(let version) = stackService.availability {
                HStack {
                    Text(Strings.Settings.GitSpice.version)
                        .foregroundColor(.secondary)
                    Text(version)
                        .font(.system(.body, design: .monospaced))
                }
                .font(.caption)
            }

            if let path = GitSpiceStackProvider.findGsBinary() {
                HStack {
                    Text(Strings.Settings.GitSpice.path)
                        .foregroundColor(.secondary)
                    Text(path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.caption)
            }

            if case .unusable(let reason) = stackService.availability {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(Strings.Settings.GitSpice.statusUnusable(reason))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text(Strings.Settings.GitSpice.info)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Picker(Strings.Settings.GitSpice.newStackMode, selection: $settings.newStackMode) {
                Text(Strings.Stacks.newStackModeDefault).tag(NewStackMode.branchOffDefault)
                Text(Strings.Stacks.newStackModeIntegration).tag(NewStackMode.branchOffIntegration)
            }
            .pickerStyle(.radioGroup)
            .font(.caption)
            .help(Strings.Settings.GitSpice.newStackModeHelp)

            Toggle(
                Strings.Settings.GitSpice.hideStackedWorktrees, isOn: $settings.hideStackedWorktrees
            )
            .font(.caption)
            .help(Strings.Settings.GitSpice.hideStackedWorktreesHelp)

            HStack {
                Spacer()
                Button(Strings.Settings.GitSpice.checkAgain) {
                    Task { await stackService.probe() }
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    var gitSpiceNotAvailableContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Settings.GitSpice.notInstalledDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(Strings.Settings.GitSpice.installHint)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("brew install git-spice")
                    .font(.system(.body, design: .monospaced))
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install git-spice", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .help(Strings.Settings.copyToClipboard)
            }

            Button(Strings.Settings.GitSpice.checkAgain) {
                Task { await stackService.probe() }
            }
            .font(.caption)
        }
    }
}
