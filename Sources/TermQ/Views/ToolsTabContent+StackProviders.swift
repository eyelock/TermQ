import AppKit
import SwiftUI
import TermQShared

// MARK: - Stacked Pull Requests Section

/// One Settings section covering stacked-PR support, with a card per backend.
///
/// Both tools can be installed at once and they own different repositories, so this is
/// not a "pick one" screen: each card reports its own availability independently, and the
/// preferred-backend picker only breaks ties for repos neither tool has claimed yet.
extension ToolsTabContent {
    /// The section-level indicator: stacking works if ANY backend is usable.
    var stackingStatusIndicator: StatusIndicatorState {
        switch stackService.availability {
        case .missing: return .inactive
        case .unusable: return .disabled
        case .ready: return .ready
        }
    }

    var stackingStatusMessage: String {
        switch stackService.availability {
        case .missing:
            return Strings.Settings.notInstalled
        case .unusable(let reason):
            return Strings.Settings.Stacking.statusUnusable(reason)
        case .ready(let version):
            return version
        }
    }

    @ViewBuilder
    var stackProvidersSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                stackProviderCard(
                    id: .gitSpice,
                    title: Strings.Settings.GitSpice.title,
                    description: Strings.Settings.GitSpice.description,
                    info: Strings.Settings.GitSpice.info,
                    detectedPath: GitSpiceStackProvider.findGsBinary(),
                    notInstalledDescription: Strings.Settings.GitSpice.notInstalledDescription,
                    installHint: Strings.Settings.GitSpice.installHint,
                    installCommand: Strings.Settings.GitSpice.installCommand)

                Divider()

                stackProviderCard(
                    id: .gitHub,
                    title: Strings.Settings.GitHubStack.title,
                    description: Strings.Settings.GitHubStack.description,
                    info: Strings.Settings.GitHubStack.info,
                    detectedPath: GitHubStackProvider.findGhBinary(),
                    notInstalledDescription: Strings.Settings.GitHubStack.notInstalledDescription,
                    // The extension can only be installed once gh itself exists, so the
                    // hint changes rather than offering a command that cannot run.
                    installHint: GitHubStackProvider.findGhBinary() == nil
                        ? Strings.Settings.GitHubStack.needsGhCli
                        : Strings.Settings.GitHubStack.installHint,
                    installCommand: GitHubStackProvider.findGhBinary() == nil
                        ? nil : Strings.Settings.GitHubStack.installCommand)

                Divider()

                stackingSharedSettings
            }
            .padding(.vertical, 4)
        } header: {
            Text(Strings.Settings.Stacking.section)
        }
        .onAppear {
            Task { await stackService.probe() }
        }
    }

    // MARK: - Per-provider card

    /// One backend's detection state. Shape is identical for every provider so the two
    /// cards stay visually comparable — only the naming text and install command differ.
    ///
    /// `installCommand` is nil when there is nothing the user can usefully copy (gh-stack
    /// without `gh` present). TermQ displays it and never runs it: installing another
    /// tool is the user's decision, matching the detect-never-bundle rule these providers
    /// follow everywhere else.
    @ViewBuilder
    func stackProviderCard(
        id: StackProviderID,
        title: String,
        description: String,
        info: String,
        detectedPath: String?,
        notInstalledDescription: String,
        installHint: String,
        installCommand: String?
    ) -> some View {
        let availability = stackService.availability(for: id)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .font(.title2)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                switch availability {
                case .ready:
                    installedBadge
                case .unusable:
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(Strings.Settings.notInstalled)
                            .foregroundColor(.orange)
                    }
                    .font(.caption)
                case .missing:
                    notInstalledBadge
                }
            }

            if case .missing = availability {
                stackProviderInstallContent(
                    notInstalledDescription: notInstalledDescription,
                    installHint: installHint,
                    installCommand: installCommand)
            } else {
                stackProviderDetailContent(
                    availability: availability, info: info, detectedPath: detectedPath)
            }
        }
    }

    @ViewBuilder
    func stackProviderDetailContent(
        availability: StackProviderAvailability, info: String, detectedPath: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .ready(let version) = availability {
                HStack {
                    Text(Strings.Settings.Stacking.version)
                        .foregroundColor(.secondary)
                    Text(version)
                        .font(.system(.body, design: .monospaced))
                }
                .font(.caption)
            }

            if let detectedPath {
                HStack {
                    Text(Strings.Settings.Stacking.path)
                        .foregroundColor(.secondary)
                    Text(detectedPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.caption)
            }

            if case .unusable(let reason) = availability {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(Strings.Settings.Stacking.statusUnusable(reason))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text(info)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    func stackProviderInstallContent(
        notInstalledDescription: String, installHint: String, installCommand: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(notInstalledDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(installHint)
                .font(.caption)
                .foregroundColor(.secondary)

            if let installCommand {
                HStack {
                    Text(installCommand)
                        .font(.system(.body, design: .monospaced))
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installCommand, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help(Strings.Settings.copyToClipboard)
                }
            }
        }
    }

    // MARK: - Shared settings

    /// Settings that describe the FEATURE rather than a backend, so they apply whichever
    /// tool ends up driving a given repository.
    @ViewBuilder
    var stackingSharedSettings: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                Strings.Settings.Stacking.preferred, selection: $settings.preferredStackProvider
            ) {
                Text(Strings.Settings.Stacking.preferredAutomatic).tag(PreferredStackProvider.automatic)
                Text(Strings.Settings.Stacking.gitSpiceName).tag(PreferredStackProvider.gitSpice)
                Text(Strings.Settings.Stacking.gitHubName).tag(PreferredStackProvider.gitHub)
            }
            .pickerStyle(.radioGroup)
            .font(.caption)
            .help(Strings.Settings.Stacking.preferredHelp)
            .onChange(of: settings.preferredStackProvider) {
                // Repos with initialization evidence are unaffected — evidence beats
                // preference — so this only re-resolves the ones decided by fallback.
                Task { await stackService.preferredProviderDidChange() }
            }

            Divider()

            Picker(Strings.Settings.Stacking.newStackMode, selection: $settings.newStackMode) {
                Text(Strings.Stacks.newStackModeDefault).tag(NewStackMode.branchOffDefault)
                Text(Strings.Stacks.newStackModeIntegration).tag(NewStackMode.branchOffIntegration)
            }
            .pickerStyle(.radioGroup)
            .font(.caption)
            .help(Strings.Settings.Stacking.newStackModeHelp)

            Toggle(
                Strings.Settings.Stacking.hideStackedWorktrees, isOn: $settings.hideStackedWorktrees
            )
            .font(.caption)
            .help(Strings.Settings.Stacking.hideStackedWorktreesHelp)

            HStack {
                Spacer()
                Button(Strings.Settings.Stacking.checkAgain) {
                    Task { await stackService.probe() }
                }
                .font(.caption)
            }
        }
    }
}
