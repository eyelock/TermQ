import AppKit
import SwiftUI
import TermQCore
import TermQShared

/// Changes the cursor to a pointing hand on hover.
struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

/// Full detail view for a selected harness.
///
/// Shows basic identity from the `Harness` list row immediately, then enriches
/// with full composition data from `ynh info` + `ynd compose` once loaded.
struct HarnessDetailView: View {
    let viewModel: HarnessDetailViewModel
    let onDismiss: () -> Void
    /// Called when the user requests a launch. Optional path pre-fills the working directory.
    let onLaunch: (String?) -> Void
    let onUpdate: (String) -> Void
    let onUninstall: (String) -> Void
    let onFork: (String) -> Void
    let onExport: (String, String) -> Void

    @AppStorage("sidebar.selectedTab") private var sidebarTab = "repositories"
    @ObservedObject private var marketplaceStore: MarketplaceStore = .shared
    @ObservedObject private var ynhPersistence: YNHPersistence = .shared
    @ObservedObject private var boardVM: BoardViewModel = .shared
    @ObservedObject private var vendorService: VendorService = .shared
    @ObservedObject private var editorRegistry: EditorRegistry = .shared
    @StateObject private var includeEditor = HarnessIncludeEditor()
    @State private var popoverForPath: String?
    @State private var showUninstallAlert = false
    @State private var harnessToDuplicate: Harness?
    @State private var showDeleteAlert = false
    @State private var showEditManifestSheet = false

    // Convenience accessors so the body and section helpers below keep their
    // existing call sites unchanged. Pure forwarding to the view-model.
    private var harness: Harness { viewModel.harness }
    private var detail: HarnessDetail? { viewModel.detail }
    private var isLoadingDetail: Bool { viewModel.isLoadingDetail }
    private var detailError: String? { viewModel.detailError }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                let linkedPaths = ynhPersistence.worktrees(for: harness.name)
                if !linkedPaths.isEmpty {
                    Divider()
                    linkedWorktreesSection(linkedPaths)
                }

                Divider()
                infoSection
                Divider()
                artifactSection

                Button {
                    marketplaceStore.preselectedHarnessTarget = harness.name
                    sidebarTab = "marketplaces"  // matches SidebarView.SidebarTab.marketplaces.rawValue
                } label: {
                    Label(Strings.Harnesses.configureFromMarketplaces, systemImage: "storefront")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)

                if let detail {
                    HarnessDetailCompositionView(
                        composition: detail.composition
                    )
                }

                let depView = HarnessDetailDependencyView(
                    harness: harness, detail: detail,
                    updateSignal: viewModel.updateSignal,
                    includeEditor: viewModel.editability == .fullyEditable ? includeEditor : nil)
                if depView.hasDependencies {
                    Divider()
                    depView
                }

                if let detail {
                    Divider()
                    manifestSection(detail.info)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(
            Strings.Harnesses.uninstallAlertTitle(harness.name),
            isPresented: $showUninstallAlert
        ) {
            Button(Strings.Harnesses.uninstallAlertConfirm, role: .destructive) {
                onUninstall(harness.name)
            }
            Button(Strings.Harnesses.installCancel, role: .cancel) {}
        } message: {
            Text(uninstallAlertMessage)
        }
        .confirmationDialog(
            Strings.Harnesses.deleteLocalTitle(harness.name),
            isPresented: $showDeleteAlert,
            titleVisibility: .visible
        ) {
            Button(Strings.Harnesses.deleteLocalConfirm, role: .destructive) {
                onUninstall(harness.name)
            }
            Button(Strings.Harnesses.installCancel, role: .cancel) {}
        } message: {
            Text(Strings.Harnesses.deleteLocalMessage)
        }
        .sheet(item: $harnessToDuplicate) { harness in
            DuplicateHarnessSheet(
                harness: harness,
                detector: YNHDetector.shared,
                repository: HarnessRepository.shared
            )
            .frame(width: 480, height: 360)
        }
        .sheet(isPresented: $showEditManifestSheet) {
            EditManifestSheet(
                harness: harness,
                onDismiss: { showEditManifestSheet = false }
            )
            .frame(width: 520, height: 440)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(harness.name)
                    .font(.title)
                    .fontWeight(.bold)

                if !harness.version.isEmpty {
                    Text(harness.version)
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isLoadingDetail {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }

                Button {
                    onLaunch(nil)
                } label: {
                    Label(Strings.Harnesses.launchButton, systemImage: "play.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .controlSize(.regular)
                .help(Strings.Harnesses.launchHelp)

                Menu {
                    actionsMenuContent
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(Strings.Harnesses.moreActionsHelp)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(Strings.Harnesses.closeDetail)
            }

            if let description = harness.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                if !harness.defaultVendor.isEmpty {
                    vendorPickerBadge
                }

                sourceBadgeView(viewModel.sourceBadge)
                if case .registry = viewModel.sourceBadge.source {
                    readOnlyBadge
                }
            }

            switch viewModel.updateSignal {
            case .versioned(let versionAvailable):
                updateBanner(version: versionAvailable, isWarning: false)
            case .unversionedDrift:
                updateBanner(version: nil, isWarning: true)
            case .none:
                EmptyView()
            }

            if let error = detailError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailInfo)
                .font(.headline)

            HStack(alignment: .top, spacing: 8) {
                Text(Strings.Harnesses.detailPath)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
                Text(harness.editablePath)
                    .font(.body)
                    .textSelection(.enabled)
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: harness.editablePath)
                } label: {
                    Image(systemName: "folder")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()
                .help(Strings.Harnesses.revealInFinder)
            }

            if let provenance = harness.installedFrom {
                labeledRow(Strings.Harnesses.detailSource, value: provenance.source)

                if let subpath = provenance.path, !subpath.isEmpty {
                    labeledRow(Strings.Harnesses.detailSubpath, value: subpath)
                }

                labeledRow(Strings.Harnesses.detailInstalledAt, value: provenance.installedAt)
            }
        }
    }

    // MARK: - Artifacts

    private var artifactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailArtifacts)
                .font(.headline)

            if let detail {
                let comp = detail.composition
                artifactList(Strings.Harnesses.detailSkills, items: comp.artifacts.skills)
                artifactList(Strings.Harnesses.detailAgents, items: comp.artifacts.agents)
                artifactList(Strings.Harnesses.detailRules, items: comp.artifacts.rules)
                artifactList(Strings.Harnesses.detailCommands, items: comp.artifacts.commands)

                if comp.counts.total == 0 && !comp.includes.isEmpty {
                    Text(Strings.Harnesses.detailArtifactsFromIncludes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Fallback to counts from ynh ls while detail loads.
                HStack(spacing: 12) {
                    artifactCount(Strings.Harnesses.detailSkills, count: harness.artifacts.skills)
                    artifactCount(Strings.Harnesses.detailAgents, count: harness.artifacts.agents)
                    artifactCount(Strings.Harnesses.detailRules, count: harness.artifacts.rules)
                    artifactCount(Strings.Harnesses.detailCommands, count: harness.artifacts.commands)
                }
            }
        }
    }

    @ViewBuilder
    private func artifactList(_ title: String, items: [ComposedArtifact]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(title) (\(items.count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))

                        Text(Strings.Harnesses.detailFrom)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)

                        Text(item.source)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 12)
                }
            }
        }
    }

    // MARK: - Manifest

    private func manifestSection(_ info: HarnessInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup {
                if let manifest = info.manifest {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(manifest.rawString)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(Strings.Harnesses.detailNoManifest)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } label: {
                Text(Strings.Harnesses.detailManifest)
                    .font(.headline)
            }
        }
    }

    // MARK: - Helpers

    private func updateBanner(version: String?, isWarning: Bool) -> some View {
        let icon = isWarning ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath"
        let tint: Color = isWarning ? .yellow : .orange
        let copy: String
        if isWarning {
            copy = Strings.Harnesses.unversionedDriftBanner
        } else if let version {
            copy = Strings.Harnesses.updateAvailableVersion(version)
        } else {
            copy = Strings.Harnesses.updateAvailable
        }
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(tint)
            Text(copy)
                .font(.caption)
            Spacer()
            Button {
                onUpdate(harness.name)
            } label: {
                Text(Strings.Harnesses.updateButton)
                    .font(.caption)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func artifactCount(_ label: String, count: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(count > 0 ? .primary : .secondary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 50)
    }

    private func vendorBadge(_ vendor: String) -> some View {
        Text(vendor)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.purple.opacity(0.2))
            .foregroundColor(.purple)
            .clipShape(Capsule())
    }

    /// Effective vendor for the badge — the user's override if set, otherwise
    /// the harness's manifest-declared default. Drives both the badge label
    /// and the launch sheet's pre-selected vendor.
    private var effectiveVendor: String {
        ynhPersistence.vendorOverride(for: harness.id) ?? harness.defaultVendor
    }

    @ViewBuilder
    private func vendorMenuButton(_ vendor: Vendor) -> some View {
        let isDefault = vendor.vendorID == harness.defaultVendor
        let isSelected = vendor.vendorID == effectiveVendor
        Button {
            if isDefault {
                ynhPersistence.setVendorOverride(nil, for: harness.id)
            } else {
                ynhPersistence.setVendorOverride(vendor.vendorID, for: harness.id)
            }
        } label: {
            let label =
                isDefault
                ? Strings.Harnesses.launchVendorDefault(vendor.displayName)
                : vendor.displayName
            if isSelected {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    /// Vendor badge that doubles as a picker. Tapping opens a Menu listing
    /// every available vendor plus a "Default (X)" entry to clear an override.
    /// When no vendors have loaded yet (VendorService empty), the badge is
    /// non-interactive and just shows the effective vendor.
    private var vendorPickerBadge: some View {
        Menu {
            ForEach(vendorService.vendors) { vendor in
                vendorMenuButton(vendor)
            }
        } label: {
            vendorBadge(effectiveVendor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .task {
            // Lazy-load vendors the first time the badge appears so the menu
            // is populated by the time the user clicks.
            if vendorService.vendors.isEmpty {
                await vendorService.refresh()
            }
        }
    }

    /// Source badge: an SF Symbol icon + localized label classified from the
    /// harness's `installedFrom`. Treats nil provenance as `.local`.
    private func sourceBadgeView(_ badge: HarnessSourceBadgeViewModel) -> some View {
        Label {
            Text(label(for: badge.source))
        } icon: {
            Image(systemName: badge.iconSystemName)
        }
        .labelStyle(.titleAndIcon)
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.15))
        .clipShape(Capsule())
    }

    /// Read-only indicator shown next to a registry source badge. The plan's
    /// editability model treats registry installs as read-only by default,
    /// with `Fork to local` as the primary path to edit them.
    private var readOnlyBadge: some View {
        Label {
            Text(Strings.Harnesses.sourceReadOnly)
        } icon: {
            Image(systemName: "lock")
        }
        .labelStyle(.titleAndIcon)
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.15))
        .clipShape(Capsule())
    }

    private func label(for source: HarnessSource) -> String {
        switch source {
        case .local:
            return Strings.Harnesses.sourceLocal
        case .git:
            return GitURLHelper.shortURL(harness.installedFrom?.source ?? "")
        case .registry(let name):
            return name ?? Strings.Harnesses.sourceMarketplace
        case .forked(let origin):
            return Strings.Harnesses.sourceForkedFrom(
                origin.registryName ?? GitURLHelper.shortURL(origin.source))
        }
    }

    fileprivate func openInTerminal(path: String) {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            TermQLogger.ui.error("openInTerminal: Terminal.app not found")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.addsToRecentItems = false
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: path)],
            withApplicationAt: terminalURL,
            configuration: config
        )
    }

    fileprivate func openIn(editor: ExternalEditor, path: String) {
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.addsToRecentItems = false
        NSWorkspace.shared.open([url], withApplicationAt: editor.appURL, configuration: config)
    }
}

// MARK: - Actions Menu

extension HarnessDetailView {
    /// Canonical detail-pane actions menu. Five groups, hidden items per
    /// source kind; mirrored in `HarnessesSidebarTab`'s context menu (which
    /// drops Help and Export-as-Marketplace as advanced/help-only).
    @ViewBuilder
    fileprivate var actionsMenuContent: some View {
        // Group 1 — Run (Launch is its own button beside the menu).
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("ynh run \(harness.name)", forType: .string)
        } label: {
            Label(Strings.Harnesses.copyRunCommand, systemImage: "doc.on.clipboard")
        }

        Divider()

        // Group 2 — Location.
        Button {
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: harness.editablePath)])
        } label: {
            Label(Strings.Harnesses.revealInFinder, systemImage: "folder")
        }
        Button {
            openInTerminal(path: harness.editablePath)
        } label: {
            Label(Strings.Sidebar.openInTerminal, systemImage: "apple.terminal")
        }
        if !editorRegistry.available.isEmpty {
            Menu(Strings.Sidebar.openIn) {
                ForEach(editorRegistry.available) { editor in
                    Button(editor.displayName) {
                        openIn(editor: editor, path: harness.editablePath)
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
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label(Strings.Harnesses.openInBrowser, systemImage: "safari")
            }
        }
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(harness.editablePath, forType: .string)
        } label: {
            Label(Strings.Harnesses.copyPath, systemImage: "doc.on.clipboard")
        }

        Divider()

        // Group 3 — Actions.
        if !harness.isFork {
            Button {
                onUpdate(harness.name)
            } label: {
                Label(Strings.Harnesses.updateButton, systemImage: "arrow.triangle.2.circlepath")
            }
        }
        if viewModel.editability == .fullyEditable {
            Button {
                showEditManifestSheet = true
            } label: {
                Label(Strings.Harnesses.editManifestMenu, systemImage: "pencil")
            }
        }
        if case .readOnly(canFork: true) = viewModel.editability, viewModel.phase1Capable {
            Button {
                onFork(harness.name)
            } label: {
                Label(Strings.Harnesses.forkToLocal, systemImage: "tuningfork")
            }
            .help(Strings.Harnesses.forkToLocalHelp)
        }
        if harness.installedFrom?.sourceType != "registry" {
            Button {
                harnessToDuplicate = harness
            } label: {
                Label(Strings.HarnessDuplicate.duplicateButton, systemImage: "doc.on.doc")
            }
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
                    onExport(harness.name, url.path)
                }
            }
        } label: {
            Label(Strings.Harnesses.exportButton, systemImage: "square.and.arrow.up")
        }

        Divider()

        // Group 4 — Help.
        Button {
            if let url = URL(string: "https://eyelock.github.io/ynh/") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label(Strings.Harnesses.ynhDocumentation, systemImage: "questionmark.circle")
        }

        Divider()

        // Group 5 — Destructive.
        Button(role: .destructive) {
            showUninstallAlert = true
        } label: {
            Label(Strings.Harnesses.uninstallButton, systemImage: "trash")
        }
        if harness.installedFrom == nil || harness.installedFrom?.sourceType == "local" {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label(Strings.Harnesses.deleteLocalButton, systemImage: "trash.fill")
            }
        }
    }
}

// MARK: - Linked Worktrees

extension HarnessDetailView {
    fileprivate func linkedWorktreesSection(_ paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.linkedWorktrees)
                .font(.headline)
            ForEach(paths, id: \.self) { path in
                linkedWorktreeRow(path: path)
            }
        }
    }

    @ViewBuilder
    fileprivate func linkedWorktreeRow(path: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.body)
                Text(path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer()

            let terminals = harnessTerminals(path: path)
            if !terminals.isEmpty {
                let count = terminals.count
                let iconName = count <= 50 ? "\(count).circle.fill" : "circle.fill"
                Button {
                    popoverForPath = popoverForPath == path ? nil : path
                } label: {
                    Image(systemName: iconName)
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .help(Strings.Sidebar.terminalBadgeHelp)
                .popover(
                    isPresented: Binding(
                        get: { popoverForPath == path },
                        set: { if !$0 { popoverForPath = nil } }
                    )
                ) {
                    terminalPopover(terminals)
                }
            }

            Button {
                onLaunch(path)
            } label: {
                Image(systemName: "play.fill")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(Strings.Harnesses.launchHelp)
        }
    }

    fileprivate var uninstallAlertMessage: String {
        var parts = [Strings.Harnesses.uninstallBaseMessage(for: harness)]
        let linkedCount = ynhPersistence.worktrees(for: harness.name).count
        if linkedCount > 0 {
            parts.append(Strings.Harnesses.uninstallAlertWorktrees(linkedCount))
        }
        let terminalCount = allHarnessTerminals().count
        if terminalCount > 0 {
            parts.append(Strings.Harnesses.uninstallAlertTerminals(terminalCount))
        }
        return parts.joined(separator: "\n\n")
    }

    fileprivate func allHarnessTerminals() -> [TerminalCard] {
        (boardVM.board.cards + Array(boardVM.tabManager.transientCards.values))
            .filter { $0.tags.contains { tag in tag.key == "harness" && tag.value == harness.name } }
    }

    fileprivate func harnessTerminals(path: String) -> [TerminalCard] {
        (boardVM.board.cards + Array(boardVM.tabManager.transientCards.values))
            .filter {
                ($0.workingDirectory == path || $0.workingDirectory.hasPrefix(path + "/"))
                    && $0.tags.contains { tag in tag.key == "harness" && tag.value == harness.name }
            }
    }

    fileprivate func terminalPopover(_ terminals: [TerminalCard]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(terminals) { card in
                Button {
                    boardVM.selectCard(card)
                    popoverForPath = nil
                } label: {
                    Text(card.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 200)
    }
}
