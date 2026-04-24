import AppKit
import SwiftUI

struct SettingsMarketplacesView: View {
    @ObservedObject private var store = MarketplaceStore.shared
    @ObservedObject private var ynhDetector: YNHDetector = .shared
    @StateObject private var marketplaceService = YNHMarketplaceService()
    @AppStorage("marketplaceAutoRefresh") private var autoRefresh = true
    @AppStorage("defaultHarnessAuthorDirectory") private var defaultHarnessAuthorDirectory = ""

    @State private var showAddSheet = false
    @State private var marketplaceToRemove: Marketplace?
    @State private var showRemoveConfirmation = false
    @State private var showAddYNHMarketplaceSheet = false
    @State private var ynhMarketplaceToRemove: YNHMarketplace?
    @State private var showRemoveYNHMarketplaceConfirmation = false

    var body: some View {
        Group {
            Section(Strings.Settings.Marketplaces.sectionMarketplaces) {
                if store.marketplaces.isEmpty {
                    Text(Strings.Settings.Marketplaces.noMarketplaces)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.marketplaces) { marketplace in
                        marketplaceRow(marketplace)
                    }
                }
                Button(Strings.Settings.Marketplaces.addMarketplace) {
                    showAddSheet = true
                }
            }

            if case .ready(let ynhPath, _, _) = ynhDetector.status {
                Section(Strings.Settings.Marketplaces.sectionYNHMarketplaces) {
                    if marketplaceService.isLoading {
                        ProgressView().controlSize(.small)
                    } else if marketplaceService.marketplaces.isEmpty {
                        Text(Strings.Settings.Marketplaces.noYNHMarketplaces)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(marketplaceService.marketplaces) { ynhMarketplace in
                            ynhMarketplaceRow(ynhMarketplace, ynhPath: ynhPath)
                        }
                    }
                    Button(Strings.Settings.Marketplaces.addYNHMarketplace) {
                        showAddYNHMarketplaceSheet = true
                    }
                }
            }

            Section {
                Toggle(Strings.Settings.Marketplaces.autoRefresh, isOn: $autoRefresh)
            } header: {
                Text(Strings.Settings.Marketplaces.sectionBehaviour)
            } footer: {
                Text(Strings.Settings.Marketplaces.autoRefreshHelp)
                    .foregroundStyle(.secondary)
            }

            Section(Strings.Settings.Marketplaces.sectionAuthoring) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(Strings.Settings.Marketplaces.defaultAuthorDirectory)
                        Text(effectiveAuthorDirectory)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(Strings.Common.browse) { browseForAuthorDirectory() }
                    if !defaultHarnessAuthorDirectory.isEmpty {
                        Button(Strings.Settings.Marketplaces.reset) { defaultHarnessAuthorDirectory = "" }
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            if case .ready(let ynhPath, _, _) = ynhDetector.status {
                Task { await marketplaceService.refresh(ynhPath: ynhPath, environment: ynhEnvironment) }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMarketplaceSheet { marketplace in
                store.add(marketplace)
            }
        }
        .sheet(
            isPresented: $showAddYNHMarketplaceSheet,
            onDismiss: {
                if case .ready(let ynhPath, _, _) = ynhDetector.status {
                    Task { await marketplaceService.refresh(ynhPath: ynhPath, environment: ynhEnvironment) }
                }
            },
            content: { AddYNHMarketplaceSheet(detector: ynhDetector) }
        )
        .confirmationDialog(
            Strings.Settings.Marketplaces.removeConfirmTitle,
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(Strings.Marketplace.rowRemove, role: .destructive) {
                if let marketplace = marketplaceToRemove { store.remove(id: marketplace.id) }
            }
            Button(Strings.Common.cancel, role: .cancel) {}
        } message: {
            if let marketplace = marketplaceToRemove {
                Text(Strings.Settings.Marketplaces.removeConfirmMessage(marketplace.vendor.displayName))
            }
        }
        .confirmationDialog(
            Strings.Settings.Marketplaces.removeYNHMarketplaceConfirmTitle,
            isPresented: $showRemoveYNHMarketplaceConfirmation,
            titleVisibility: .visible
        ) {
            if let ynhMarketplace = ynhMarketplaceToRemove,
                case .ready(let ynhPath, _, _) = ynhDetector.status
            {
                Button(Strings.Settings.Marketplaces.removeYNHMarketplaceConfirm, role: .destructive) {
                    Task {
                        await marketplaceService.remove(
                            url: ynhMarketplace.url, ynhPath: ynhPath, environment: ynhEnvironment)
                    }
                }
            }
            Button(Strings.Common.cancel, role: .cancel) {}
        } message: {
            if let ynhMarketplace = ynhMarketplaceToRemove {
                Text(Strings.Settings.Marketplaces.removeYNHMarketplaceConfirmMessage(ynhMarketplace.name))
            }
        }
    }

    @ViewBuilder
    private func marketplaceRow(_ marketplace: Marketplace) -> some View {
        let name = marketplace.name.isEmpty ? GitURLHelper.shortURL(marketplace.url) : marketplace.name
        let browserURL: URL? =
            marketplace.url.hasPrefix("http")
            ? URL(string: marketplace.url)
            : GitURLHelper.browserURL(for: marketplace.url)
        HStack {
            ExternalSourceRowLabel(
                name: name,
                shortURL: GitURLHelper.shortURL(marketplace.url),
                description: marketplace.description,
                browserURL: browserURL
            )
            Spacer()
            Button(role: .destructive) {
                marketplaceToRemove = marketplace
                showRemoveConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func ynhMarketplaceRow(_ ynhMarketplace: YNHMarketplace, ynhPath: String) -> some View {
        HStack {
            ExternalSourceRowLabel(
                name: ynhMarketplace.name,
                shortURL: GitURLHelper.shortURL(ynhMarketplace.url),
                description: ynhMarketplace.description,
                browserURL: GitURLHelper.browserURL(for: ynhMarketplace.url)
            )
            Spacer()
            Button(role: .destructive) {
                ynhMarketplaceToRemove = ynhMarketplace
                showRemoveYNHMarketplaceConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }

    private var effectiveAuthorDirectory: String {
        defaultHarnessAuthorDirectory.isEmpty
            ? Strings.Settings.Marketplaces.authorDirectoryDetectedHint
            : defaultHarnessAuthorDirectory
    }

    private var ynhEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride { env["YNH_HOME"] = override }
        return env
    }

    private func browseForAuthorDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        Task {
            let response = await panel.begin()
            if response == .OK, let url = panel.url {
                defaultHarnessAuthorDirectory = url.path(percentEncoded: false)
            }
        }
    }
}

/// Standardised label for marketplace and registry rows: name (clickable link) + org/repo + description.
private struct ExternalSourceRowLabel: View {
    let name: String
    let shortURL: String
    let description: String?
    let browserURL: URL?

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let url = browserURL {
                    Text(name)
                        .fontWeight(.medium)
                        .foregroundStyle(isHovering ? Color.accentColor : Color.primary)
                        .underline(isHovering)
                        .onHover { hovering in
                            isHovering = hovering
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                        .onTapGesture { NSWorkspace.shared.open(url) }
                } else {
                    Text(name)
                        .fontWeight(.medium)
                }
            }
            Text(shortURL)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let desc = description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
