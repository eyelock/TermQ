import SwiftUI
import TermQShared

/// Full-width detail view for a marketplace — header, search, plugin list.
///
/// Presented as a sheet from `MarketplaceSidebarTab`.
struct MarketplaceDetailView: View {
    let marketplace: Marketplace
    @ObservedObject var detector: YNHDetector
    @ObservedObject var harnessRepository: HarnessRepository
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: MarketplaceStore = .shared

    @State private var searchText = ""
    @State private var pickerPlugin: MarketplacePlugin?
    @State private var fetchingPluginID: UUID?
    @State private var isRefreshing = false

    private var filteredPlugins: [MarketplacePlugin] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return marketplace.plugins
        }
        let query = searchText.lowercased()
        return marketplace.plugins.filter {
            $0.name.lowercased().contains(query)
                || ($0.description?.lowercased().contains(query) ?? false)
                || ($0.category?.lowercased().contains(query) ?? false)
                || $0.tags.contains { $0.lowercased().contains(query) }
                || $0.picks.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()

            if marketplace.plugins.isEmpty {
                emptyState
            } else {
                pluginList
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .task {
            if marketplace.lastFetched == nil {
                await refreshMarketplace()
            }
        }
        .sheet(item: $pickerPlugin) { plugin in
            let targetHarness = store.preselectedHarnessTarget
            NavigationStack {
                HarnessIncludePicker(
                    plugin: plugin,
                    marketplace: marketplace,
                    harnessRepository: harnessRepository,
                    detector: detector,
                    mode: targetHarness.map { .wizard(harnessID: $0) } ?? .standalone,
                    onDone: {
                        store.preselectedHarnessTarget = nil
                        pickerPlugin = nil
                    }
                )
            }
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(marketplace.name)
                        .font(.title3).fontWeight(.semibold)
                    vendorBadge
                }
                if !marketplace.owner.isEmpty {
                    Text(marketplace.owner)
                        .font(.subheadline).foregroundColor(.secondary)
                }
                if let desc = marketplace.description {
                    Text(desc)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(2)
                }
                if let last = marketplace.lastFetched {
                    let rel = RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date())
                    HStack(spacing: 4) {
                        Text(Strings.Marketplace.detailLastFetched(rel))
                            .font(.caption2).foregroundColor(.secondary)
                        Button {
                            Task { await refreshMarketplace() }
                        } label: {
                            if isRefreshing {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isRefreshing)
                    }
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var vendorBadge: some View {
        Text(marketplace.vendor.displayName)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15))
            .foregroundColor(.accentColor)
            .clipShape(Capsule())
    }

    // MARK: - Plugin list

    private var pluginList: some View {
        VStack(spacing: 0) {
            TextField(Strings.Marketplace.detailSearchPlaceholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            if filteredPlugins.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28)).foregroundColor(.secondary)
                    Text(Strings.Marketplace.detailSearchEmpty(searchText))
                        .font(.callout).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredPlugins) { plugin in
                    MarketplacePluginRowView(
                        plugin: plugin,
                        isYNHReady: {
                            if case .ready = detector.status { return true }
                            return false
                        }(),
                        isLoadingSkills: fetchingPluginID == plugin.id,
                        onAddToHarness: {
                            pickerPlugin = plugin
                        },
                        onExpandSkills: {
                            Task { await loadSkills(for: plugin) }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if isRefreshing {
                ProgressView()
                Text(Strings.Marketplace.detailEmptyHint)
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Image(systemName: "storefront")
                    .font(.system(size: 36)).foregroundColor(.secondary)
                Text(Strings.Marketplace.detailEmpty)
                    .font(.callout).foregroundColor(.secondary)
                Text(Strings.Marketplace.detailEmptyHint)
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Refresh

    private func refreshMarketplace() async {
        isRefreshing = true
        defer { isRefreshing = false }
        MarketplaceStore.shared.markFetching(id: marketplace.id)
        do {
            let updated = try await MarketplaceFetcher.fetch(marketplace: marketplace)
            MarketplaceStore.shared.update(updated)
        } catch {
            var failed = marketplace
            failed.fetchError = error.localizedDescription
            MarketplaceStore.shared.update(failed)
        }
    }

    // MARK: - Lazy skill loading

    private func loadSkills(for plugin: MarketplacePlugin) async {
        guard plugin.skillsState == .pending else { return }
        fetchingPluginID = plugin.id
        defer { fetchingPluginID = nil }

        do {
            let skills = try await MarketplaceFetcher.fetchSkills(for: plugin)
            // Update the plugin in store
            var updated = marketplace
            if let idx = updated.plugins.firstIndex(where: { $0.id == plugin.id }) {
                updated.plugins[idx].picks = skills
                updated.plugins[idx].skillsState = .eager
                MarketplaceStore.shared.update(updated)
            }
        } catch {
            var updated = marketplace
            if let idx = updated.plugins.firstIndex(where: { $0.id == plugin.id }) {
                updated.plugins[idx].skillsState = .failed(error.localizedDescription)
                MarketplaceStore.shared.update(updated)
            }
        }
    }
}
