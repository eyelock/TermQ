import AppKit
import SwiftUI
import TermQShared

/// Identifiable wrapper so sheet(item:) can present a specific marketplace.
struct MarketplaceSelection: Identifiable {
    let id: UUID
    var marketplace: Marketplace
}

/// Top-level content for the Marketplaces sidebar tab.
///
/// Shows marketplaces grouped into collapsible disclosure sections:
/// Default (known marketplaces) and dynamic GitHub org groups.
/// Selecting a marketplace opens `MarketplaceDetailView` as a sheet.
struct MarketplaceSidebarTab: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var detector: YNHDetector
    @ObservedObject var harnessRepository: HarnessRepository
    @ObservedObject private var store: MarketplaceStore = .shared

    @State private var selectedMarketplace: MarketplaceSelection?
    @State private var showAddSheet = false
    @State private var showWizard = false
    @State private var collapsedGroups: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .sheet(isPresented: $showAddSheet) {
            AddMarketplaceSheet { marketplace in
                store.add(marketplace)
                Task { await refresh(marketplace) }
            }
        }
        .sheet(item: $selectedMarketplace) { selection in
            if let current = store.marketplaces.first(where: { $0.id == selection.id }) {
                MarketplaceDetailView(
                    marketplace: current,
                    detector: detector,
                    harnessRepository: harnessRepository
                )
            }
        }
        .sheet(isPresented: $showWizard) {
            HarnessWizardSheet(detector: detector, harnessRepository: harnessRepository)
        }
        .onAppear {
            if let preID = store.preselectedMarketplaceID,
                let marketplace = store.marketplaces.first(where: { $0.id == preID })
            {
                selectedMarketplace = MarketplaceSelection(id: marketplace.id, marketplace: marketplace)
                store.preselectedMarketplaceID = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(Strings.Marketplace.title)
                .font(.headline)

            Spacer()

            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help(Strings.Marketplace.addHelp)

            Button {
                Task {
                    for marketplace in store.marketplaces {
                        await refresh(marketplace)
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help(Strings.Marketplace.refreshAllHelp)
            .disabled(store.marketplaces.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.marketplaces.isEmpty {
            emptyState
        } else {
            marketplaceList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "storefront")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(Strings.Marketplace.empty)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(Strings.Marketplace.restoreDefaults) {
                store.restoreDefaults()
                Task {
                    for marketplace in store.marketplaces {
                        await refresh(marketplace)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help(Strings.Marketplace.restoreDefaultsHelp)
            Button(Strings.Marketplace.addButton) { showAddSheet = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var marketplaceList: some View {
        List {
            ForEach(groupedMarketplaces, id: \.title) { group in
                DisclosureGroup(
                    isExpanded: expandedBinding(for: group.title)
                ) {
                    ForEach(group.marketplaces) { marketplace in
                        marketplaceRow(marketplace)
                    }
                } label: {
                    Label(group.title, systemImage: "storefront")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .contextMenu { groupContextMenu(for: group) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func marketplaceRow(_ marketplace: Marketplace) -> some View {
        MarketplaceRowView(
            marketplace: marketplace,
            onRefresh: { Task { await refresh(marketplace) } }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedMarketplace = MarketplaceSelection(id: marketplace.id, marketplace: marketplace)
        }
        .contextMenu {
            Button(Strings.Marketplace.rowRefresh) { Task { await refresh(marketplace) } }
            if let url = marketplaceBrowserURL(marketplace) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(Strings.Harnesses.openInBrowser, systemImage: "safari")
                }
            }
            Divider()
            Button(Strings.Marketplace.rowRemove, role: .destructive) { store.remove(id: marketplace.id) }
        }
    }

    // MARK: - Grouping

    private enum MarketplaceGroupKind {
        case `default`
        case github(String)
    }

    private struct MarketplaceGroup {
        let title: String
        let marketplaces: [Marketplace]
        let kind: MarketplaceGroupKind
    }

    private var groupedMarketplaces: [MarketplaceGroup] {
        let knownURLs = Set(KnownMarketplaces.all.map { $0.url })
        let defaults = store.marketplaces.filter { knownURLs.contains($0.url) }
        let remaining = store.marketplaces.filter { !knownURLs.contains($0.url) }

        var groups: [MarketplaceGroup] = []

        if !defaults.isEmpty {
            groups.append(
                MarketplaceGroup(title: Strings.Marketplace.groupDefault, marketplaces: defaults, kind: .default))
        }

        var byOrg: [String: [Marketplace]] = [:]
        for marketplace in remaining {
            let org = GitURLHelper.repoOwner(marketplace.url) ?? "Other"
            byOrg[org, default: []].append(marketplace)
        }

        for (org, marketplaces) in byOrg.sorted(by: { $0.key < $1.key }) {
            groups.append(
                MarketplaceGroup(
                    title: Strings.Marketplace.groupGitHub(org), marketplaces: marketplaces, kind: .github(org)))
        }

        return groups
    }

    @ViewBuilder
    private func groupContextMenu(for group: MarketplaceGroup) -> some View {
        Button {
            SettingsCoordinator.shared.requestedTab = .marketplaces
            openSettings()
        } label: {
            Label(Strings.Harnesses.groupMenuSettings, systemImage: "gearshape")
        }
        if case .github(let org) = group.kind,
            let url = URL(string: "https://github.com/\(org)")
        {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label(Strings.Harnesses.openInBrowser, systemImage: "safari")
            }
        }
    }

    private func marketplaceBrowserURL(_ marketplace: Marketplace) -> URL? {
        // marketplace.url may already include the scheme
        if marketplace.url.hasPrefix("http") {
            return URL(string: marketplace.url)
        }
        return GitURLHelper.browserURL(for: marketplace.url)
    }

    private func expandedBinding(for title: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(title) },
            set: { expanded in
                if expanded { collapsedGroups.remove(title) } else { collapsedGroups.insert(title) }
            }
        )
    }

    // MARK: - Fetch

    private func refresh(_ marketplace: Marketplace) async {
        store.markFetching(id: marketplace.id)
        do {
            let updated = try await MarketplaceFetcher.fetch(marketplace: marketplace)
            store.update(updated)
        } catch {
            var failed = marketplace
            failed.fetchError = error.localizedDescription
            store.update(failed)
        }
    }
}

// MARK: - Row

struct MarketplaceRowView: View {
    let marketplace: Marketplace
    let onRefresh: () -> Void

    private var isStale: Bool {
        guard let last = marketplace.lastFetched else { return false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return last < cutoff
    }

    private var displayName: String {
        GitURLHelper.shortURL(marketplace.url)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                    vendorBadge
                    if marketplace.ref != nil {
                        pinIcon
                    }
                }
                subtitle
            }
            Spacer()
            Button {
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise").imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(Strings.Marketplace.rowRefreshHelp)
        }
        .padding(.vertical, 2)
    }

    private var pinIcon: some View {
        Image(systemName: marketplace.isPinnedToSHA ? "pin.fill" : "pin")
            .imageScale(.small)
            .foregroundColor(marketplace.isPinnedToSHA ? .accentColor : .secondary)
            .help(marketplace.ref.map { Strings.Marketplace.rowPinnedHelp($0) } ?? "")
    }

    private var vendorBadge: some View {
        Text(marketplace.vendor.displayName)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15))
            .foregroundColor(.accentColor)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var subtitle: some View {
        if let err = marketplace.fetchError {
            Text(err)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(1)
        } else if let last = marketplace.lastFetched {
            let count = marketplace.plugins.count
            let rel = RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date())
            let staleLabel = isStale ? Strings.Marketplace.rowStale : ""
            Text("\(count) plugin\(count == 1 ? "" : "s") · \(rel)\(staleLabel)")
                .font(.caption)
                .foregroundColor(isStale ? .orange : .secondary)
                .lineLimit(1)
        } else {
            Text(Strings.Marketplace.rowNeverFetched)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
