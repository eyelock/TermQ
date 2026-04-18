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
    @ObservedObject var detector: YNHDetector
    @ObservedObject var repository: HarnessRepository
    var onLaunchHarness: ((Harness) -> Void)?
    var onInstall: (() -> Void)?
    var onUninstall: ((String) -> Void)?
    var onUpdate: ((String) -> Void)?
    var onExport: ((String, String) -> Void)?
    var onNewHarness: (() -> Void)?
    @ObservedObject private var ynhPersistence: YNHPersistence = .shared
    @State private var harnessToUninstall: Harness?
    @State private var showWizard = false
    @State private var showAddRegistry = false
    @State private var collapsedGroups: Set<String> = []

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
        .onAppear {
            if case .ready = detector.status, repository.harnesses.isEmpty {
                Task { await repository.refresh() }
            }
        }
        .onChange(of: detector.status) { _, newStatus in
            if case .ready = newStatus {
                Task { await repository.refresh() }
            }
        }
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
            emptyState(
                icon: "puzzlepiece.extension",
                message: Strings.Harnesses.emptyMessage
            )
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
                    onUpdate?(harness.name)
                } label: {
                    Label(Strings.Harnesses.updateButton, systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    Task { @MainActor in
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.prompt = Strings.Harnesses.exportButton
                        let response = await panel.begin()
                        if response == .OK, let url = panel.url {
                            onExport?(harness.name, url.path)
                        }
                    }
                } label: {
                    Label(Strings.Harnesses.exportButton, systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    harnessToUninstall = harness
                } label: {
                    Label(Strings.Harnesses.uninstallButton, systemImage: "trash")
                }
            }
    }

    // MARK: - Grouping

    private struct HarnessGroup {
        let title: String
        let harnesses: [Harness]
    }

    private var groupedHarnesses: [HarnessGroup] {
        let defaults = repository.harnesses.filter { KnownHarnesses.defaultNames.contains($0.name) }
        let remaining = repository.harnesses.filter { !KnownHarnesses.defaultNames.contains($0.name) }

        var groups: [HarnessGroup] = []

        if !defaults.isEmpty {
            groups.append(HarnessGroup(title: Strings.Harnesses.groupDefault, harnesses: defaults))
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

        for (org, harnesses) in byOrg.sorted(by: { $0.key < $1.key }) {
            groups.append(HarnessGroup(title: Strings.Harnesses.groupGitHub(org), harnesses: harnesses))
        }
        for (name, harnesses) in byRegistry.sorted(by: { $0.key < $1.key }) {
            groups.append(HarnessGroup(title: Strings.Harnesses.groupRegistry(name), harnesses: harnesses))
        }
        if !local.isEmpty {
            groups.append(HarnessGroup(title: Strings.Harnesses.groupLocal, harnesses: local))
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
