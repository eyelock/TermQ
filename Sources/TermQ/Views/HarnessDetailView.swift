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
    let harness: Harness
    let detail: HarnessDetail?
    let isLoadingDetail: Bool
    let detailError: String?
    let onDismiss: () -> Void
    @AppStorage("sidebar.selectedTab") private var sidebarTab = "repositories"
    @ObservedObject private var marketplaceStore: MarketplaceStore = .shared
    /// Called when the user requests a launch. Optional path pre-fills the working directory.
    let onLaunch: (String?) -> Void
    let onUpdate: (String) -> Void
    let onUninstall: (String) -> Void
    @ObservedObject private var ynhPersistence: YNHPersistence = .shared
    @ObservedObject private var boardVM: BoardViewModel = .shared
    @State private var popoverForPath: String?
    @State private var showUninstallAlert = false

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
                    harness: harness, detail: detail)
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
                    Button {
                        onUpdate(harness.name)
                    } label: {
                        Label(Strings.Harnesses.updateButton, systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("ynh run \(harness.name)", forType: .string)
                    } label: {
                        Label(Strings.Harnesses.copyRunCommand, systemImage: "doc.on.clipboard")
                    }
                    Divider()
                    Button {
                        if let url = URL(string: "https://eyelock.github.io/ynh/") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label(Strings.Harnesses.ynhDocumentation, systemImage: "questionmark.circle")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showUninstallAlert = true
                    } label: {
                        Label(Strings.Harnesses.uninstallButton, systemImage: "trash")
                    }
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
                    vendorBadge(harness.defaultVendor)
                }

                if let provenance = harness.installedFrom {
                    sourceBadge(provenance)
                }
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
                Text(harness.path)
                    .font(.body)
                    .textSelection(.enabled)
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: harness.path)
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

    private func sourceBadge(_ provenance: HarnessProvenance) -> some View {
        let label: String
        switch provenance.sourceType {
        case "git":
            label = GitURLHelper.shortURL(provenance.source)
        case "local":
            label = Strings.Harnesses.sourceLocal
        case "registry":
            label = provenance.registryName ?? Strings.Harnesses.sourceMarketplace
        default:
            label = provenance.sourceType
        }

        return Text(label)
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
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
