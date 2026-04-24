import AppKit
import SwiftUI
import TermQShared

/// Sidebar content for the Harnesses tab.
///
/// Shows detection state and, when YNH is ready, harnesses grouped into
/// collapsible disclosure sections: Default, GitHub orgs, registries, and local.
///
/// The `.missing` state is handled by the parent `SidebarView` which hides
/// the tab entirely, so this view never receives it.
struct HarnessesSidebarTab: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var detector: YNHDetector
    @ObservedObject var repository: HarnessRepository
    var onLaunchHarness: ((Harness) -> Void)?
    var onInstall: (() -> Void)?
    var onUninstall: ((String) -> Void)?
    var onUpdate: ((String) -> Void)?
    var onExport: ((String, String) -> Void)?
    var onNewHarness: (() -> Void)?
    @ObservedObject private var ynhPersistence: YNHPersistence = .shared
    @ObservedObject private var editorRegistry: EditorRegistry = .shared
    @State private var harnessToUninstall: Harness?
    @State private var harnessToDelete: Harness?
    @State private var harnessToDuplicate: Harness?
    @State private var showWizard = false
    @State private var showAddRegistry = false
    @State private var collapsedGroups: Set<String> = []
    @StateObject private var sampleRunner = RegistryAddRunner()
    @StateObject private var registryService = YNHRegistryService()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            switch detector.status {
            case .missing:
                emptyState(
                    icon: "exclamationmark.triangle",
                    message: Strings.Harnesses.notInstalled
                )

            case .binaryOnly:
                initRequiredState

            case .outdated(_, _, let capabilities):
                outdatedState(reportedCapabilities: capabilities)

            case .ready:
                harnessList
            }
        }
        .sheet(
            isPresented: $showWizard,
            onDismiss: { Task { await repository.refresh() } },
            content: { HarnessWizardSheet(detector: detector, harnessRepository: repository) }
        )
        .sheet(isPresented: $showAddRegistry) {
            AddRegistrySheet(detector: detector)
        }
        .sheet(item: $harnessToDuplicate) { harness in
            DuplicateHarnessSheet(harness: harness, detector: detector, repository: repository)
        }
        .onAppear {
            if repository.harnesses.isEmpty { Task { await repository.refresh() } }
            refreshRegistryService()
        }
        .onChange(of: detector.status) { _, _ in
            Task { await repository.refresh() }
            refreshRegistryService()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshRegistryService()
        }
    }

    private func refreshRegistryService() {
        guard case .ready(let ynhPath, _, _) = detector.status else { return }
        var env = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride { env["YNH_HOME"] = override }
        Task { await registryService.refresh(ynhPath: ynhPath, environment: env) }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(Strings.Harnesses.title)
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            if repository.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                showAddRegistry = true
            } label: {
                Image(systemName: "globe")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help(Strings.Harnesses.addRegistryToolbarHelp)

            if case .ready = detector.status {
                Button {
                    showWizard = true
                } label: {
                    Image(systemName: "wand.and.stars")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help(Strings.Harnesses.wizardToolbarHelp)

                Button {
                    onInstall?()
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help(Strings.Harnesses.installToolbarHelp)
            }

            Button {
                Task {
                    await detector.detect()
                    await repository.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help(Strings.Harnesses.refreshHelp)
            .disabled(repository.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Harness List

    @ViewBuilder
    private var harnessList: some View {
        if repository.harnesses.isEmpty && !repository.isLoading {
            harnessesEmptyState
        } else {
            List(selection: $repository.selectedHarnessName) {
                ForEach(groupedHarnesses, id: \.title) { group in
                    DisclosureGroup(
                        isExpanded: expandedBinding(for: group.title)
                    ) {
                        ForEach(group.harnesses) { harness in
                            harnessRow(harness)
                        }
                    } label: {
                        Label(group.title, systemImage: "puzzlepiece.extension")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .contextMenu { groupContextMenu(for: group) }
                    }
                }
            }
            .listStyle(.sidebar)
            .confirmationDialog(
                harnessToUninstall.map { Strings.Harnesses.uninstallAlertTitle($0.name) } ?? "",
                isPresented: Binding(
                    get: { harnessToUninstall != nil },
                    set: { if !$0 { harnessToUninstall = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let harness = harnessToUninstall {
                    Button(Strings.Harnesses.uninstallAlertConfirm, role: .destructive) {
                        onUninstall?(harness.name)
                        harnessToUninstall = nil
                    }
                    Button(Strings.Harnesses.installCancel, role: .cancel) {
                        harnessToUninstall = nil
                    }
                }
            } message: {
                if let harness = harnessToUninstall {
                    let linked = ynhPersistence.worktrees(for: harness.name).count
                    Text(
                        linked > 0
                            ? Strings.Harnesses.uninstallAlertWorktrees(linked)
                            : Strings.Harnesses.uninstallAlertMessage
                    )
                }
            }
            .confirmationDialog(
                harnessToDelete.map { Strings.Harnesses.deleteLocalTitle($0.name) } ?? "",
                isPresented: Binding(
                    get: { harnessToDelete != nil },
                    set: { if !$0 { harnessToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let harness = harnessToDelete {
                    Button(Strings.Harnesses.deleteLocalConfirm, role: .destructive) {
                        performDeleteLocalHarness(harness)
                        harnessToDelete = nil
                    }
                    Button(Strings.Harnesses.installCancel, role: .cancel) {
                        harnessToDelete = nil
                    }
                }
            } message: {
                Text(Strings.Harnesses.deleteLocalMessage)
            }
        }
    }

    private func harnessRow(_ harness: Harness) -> some View {
        HarnessRowView(harness: harness)
            .tag(harness.name)
            .contextMenu {
                Button {
                    onLaunchHarness?(harness)
                } label: {
                    Label(Strings.Harnesses.launchButton, systemImage: "play.fill")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("ynh run \(harness.name)", forType: .string)
                } label: {
                    Label(Strings.Harnesses.copyRunCommand, systemImage: "doc.on.clipboard")
                }

                Divider()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: harness.path)]
                    )
                } label: {
                    Label(Strings.Sidebar.revealInFinder, systemImage: "folder")
                }
                Button {
                    openInTerminal(path: harness.path)
                } label: {
                    Label(Strings.Sidebar.openInTerminal, systemImage: "apple.terminal")
                }
                if !editorRegistry.available.isEmpty {
                    Menu(Strings.Sidebar.openIn) {
                        ForEach(editorRegistry.available) { editor in
                            Button(editor.displayName) {
                                openIn(editor: editor, path: harness.path)
                            }
                        }
                    }
                }

                if let source = harness.installedFrom?.source,
                    let url = GitURLHelper.browserURL(
                        for: source,
                        path: harness.installedFrom?.path
                    )
                {
                    Divider()
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(Strings.Harnesses.openInBrowser, systemImage: "safari")
                    }
                }

                Divider()
                Button {
                    onUpdate?(harness.name)
                } label: {
                    Label(Strings.Harnesses.updateButton, systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    harnessToDuplicate = harness
                } label: {
                    Label(Strings.HarnessDuplicate.duplicateButton, systemImage: "doc.on.doc")
                }
                Button {
                    Task { @MainActor in
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = true
                        panel.prompt = Strings.Harnesses.exportButton
                        let response = await panel.begin()
                        if response == .OK, let url = panel.url {
                            onExport?(harness.name, url.path)
                        }
                    }
                } label: {
                    Label(Strings.Harnesses.exportButton, systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    harnessToUninstall = harness
                } label: {
                    Label(Strings.Harnesses.uninstallButton, systemImage: "trash")
                }
                if harness.installedFrom == nil || harness.installedFrom?.sourceType == "local" {
                    Button(role: .destructive) {
                        harnessToDelete = harness
                    } label: {
                        Label(Strings.Harnesses.deleteLocalButton, systemImage: "trash.fill")
                    }
                }
            }
    }

    // MARK: - Grouping

    private enum GroupKind {
        case `default`, github, registry, local
    }

    private struct HarnessGroup {
        let title: String
        let harnesses: [Harness]
        let kind: GroupKind
    }

    private var groupedHarnesses: [HarnessGroup] {
        let alphaSorted: ([Harness]) -> [Harness] = { harnesses in
            harnesses.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        let defaults = repository.harnesses.filter { KnownHarnesses.defaultNames.contains($0.name) }
        let remaining = repository.harnesses.filter { !KnownHarnesses.defaultNames.contains($0.name) }

        var groups: [HarnessGroup] = []

        if !defaults.isEmpty {
            groups.append(
                HarnessGroup(title: Strings.Harnesses.groupDefault, harnesses: alphaSorted(defaults), kind: .default))
        }

        var byOrg: [String: [Harness]] = [:]
        var byRegistry: [String: [Harness]] = [:]
        var local: [Harness] = []

        for harness in remaining {
            switch harness.installedFrom?.sourceType {
            case "git":
                let org = harness.installedFrom.flatMap { GitURLHelper.repoOwner($0.source) } ?? "Other"
                byOrg[org, default: []].append(harness)
            case "registry":
                let name = harness.installedFrom?.registryName ?? Strings.Harnesses.sourceRegistry
                byRegistry[name, default: []].append(harness)
            default:
                local.append(harness)
            }
        }

        // Order: DEFAULT → REGISTRY (alpha) → GitHub (alpha) → LOCAL
        for (name, harnesses) in byRegistry.sorted(by: { $0.key < $1.key }) {
            groups.append(
                HarnessGroup(
                    title: Strings.Harnesses.groupRegistry(name), harnesses: alphaSorted(harnesses), kind: .registry))
        }
        for (org, harnesses) in byOrg.sorted(by: { $0.key < $1.key }) {
            groups.append(
                HarnessGroup(
                    title: Strings.Harnesses.groupGitHub(org), harnesses: alphaSorted(harnesses), kind: .github))
        }
        if !local.isEmpty {
            groups.append(
                HarnessGroup(title: Strings.Harnesses.groupLocal, harnesses: alphaSorted(local), kind: .local))
        }

        return groups
    }

    private func expandedBinding(for title: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(title) },
            set: { expanded in
                if expanded { collapsedGroups.remove(title) } else { collapsedGroups.insert(title) }
            }
        )
    }

    // MARK: - States

    private func outdatedState(reportedCapabilities: String?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text(Strings.Harnesses.outdatedHeadline)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text(
                Strings.Harnesses.outdatedDetail(
                    reported: reportedCapabilities ?? Strings.Harnesses.outdatedCapabilitiesUnknown,
                    minimum: YNHDetector.minimumCapabilitiesVersion
                )
            )
            .font(.caption)
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var initRequiredState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text(Strings.Harnesses.initRequired)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text(Strings.Harnesses.initHint)
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var hasRegistries: Bool {
        !registryService.registries.isEmpty
    }

    private var harnessesEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            if hasRegistries {
                Text(Strings.Harnesses.emptyMessage)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button(Strings.Harnesses.searchButton) {
                    onInstall?()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Text(Strings.Harnesses.emptyNoRegistriesMessage)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button(Strings.Harnesses.addSampleButton) {
                    Task { await addSampleRegistry() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(sampleRunner.isRunning || ynhPathFromDetector == nil)

                Button(Strings.Harnesses.addRegistryButton) {
                    showAddRegistry = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(Strings.Harnesses.createHarnessButton) {
                showWizard = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var ynhPathFromDetector: String? {
        if case .ready(let ynhPath, _, _) = detector.status { return ynhPath }
        return nil
    }

    private func addSampleRegistry() async {
        guard let ynhPath = ynhPathFromDetector else { return }
        var env = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride { env["YNH_HOME"] = override }
        await sampleRunner.run(
            ynhPath: ynhPath,
            url: "https://github.com/eyelock/assistants",
            environment: env
        )
        if sampleRunner.succeeded, let ynhPath = ynhPathFromDetector {
            var env = ProcessInfo.processInfo.environment
            if let override = YNHDetector.shared.ynhHomeOverride { env["YNH_HOME"] = override }
            Task {
                await repository.refresh()
                await registryService.refresh(ynhPath: ynhPath, environment: env)
            }
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Helpers

extension HarnessesSidebarTab {
    @ViewBuilder
    private func groupContextMenu(for group: HarnessGroup) -> some View {
        switch group.kind {
        case .registry, .github:
            Button {
                SettingsCoordinator.shared.requestedTab = .marketplaces
                openSettings()
            } label: {
                Label(Strings.Harnesses.groupMenuSettings, systemImage: "gearshape")
            }
            if let source = group.harnesses.first?.installedFrom?.source,
                let url = GitURLHelper.browserURL(for: source)
            {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(Strings.Harnesses.openInBrowser, systemImage: "safari")
                }
            }

        case .default:
            Button {
                SettingsCoordinator.shared.requestedTab = .marketplaces
                openSettings()
            } label: {
                Label(Strings.Harnesses.groupMenuSettings, systemImage: "gearshape")
            }

        case .local:
            Button {
                SettingsCoordinator.shared.requestedTab = .marketplaces
                openSettings()
            } label: {
                Label(Strings.Harnesses.groupMenuSettings, systemImage: "gearshape")
            }
            Button {
                revealLocalGroupInFinder(group)
            } label: {
                Label(Strings.Sidebar.revealInFinder, systemImage: "folder")
            }
        }
    }

    fileprivate func performDeleteLocalHarness(_ harness: Harness) {
        onUninstall?(harness.name)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: harness.path))
    }

    private func revealLocalGroupInFinder(_ group: HarnessGroup) {
        let path =
            group.harnesses.first?.installedFrom?.source
            ?? UserDefaults.standard.string(forKey: "defaultHarnessAuthorDirectory")
        guard let path, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    fileprivate func openInTerminal(path: String) {
        guard !path.contains("\n"), !path.contains("\r") else {
            TermQLogger.ui.error("openInTerminal: path contains newline, aborting")
            return
        }
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
            tell application "Terminal"
                activate
                do script "cd '\(escaped)'"
            end tell
            """
        Task.detached {
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
                    if TermQLogger.fileLoggingEnabled {
                        TermQLogger.ui.error("openInTerminal AppleScript error=\(error)")
                    } else {
                        TermQLogger.ui.error("openInTerminal AppleScript failed code=\(code)")
                    }
                }
            }
        }
    }

    fileprivate func openIn(editor: ExternalEditor, path: String) {
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.addsToRecentItems = false
        NSWorkspace.shared.open([url], withApplicationAt: editor.appURL, configuration: config)
    }
}
