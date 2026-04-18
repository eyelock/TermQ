import AppKit
import SwiftUI
import TermQShared

/// Configuration for installing a harness, passed from the sheet to ContentView.
///
/// ContentView calls `config.command(ynhPath:)` to build the init command for a
/// transient terminal card, so the user sees `ynh install` output in a dedicated tab.
struct HarnessInstallConfig {
    let displayName: String
    /// Arguments passed after `ynh install` (e.g. `["my-harness"]` or `["github.com/u/r", "--path", "sub"]`).
    let installArgs: [String]

    func command(ynhPath: String) -> String {
        ([ynhPath, "install"] + installArgs).joined(separator: " ")
    }
}

/// Three-tab sheet for installing a harness from a registry/source, Git URL, or local path.
struct HarnessInstallSheet: View {
    /// Names of already-installed harnesses — used to show "Installed" badge in search results.
    let installedNames: Set<String>
    /// Full installed harness list — shown as default content before any search term is entered.
    let harnesses: [Harness]
    let onInstall: (HarnessInstallConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var searchService = HarnessSearchService()
    @StateObject private var sourcesService = SourcesService()

    @State private var selectedTab: InstallTab = .search
    @State private var searchQuery = ""
    @State private var gitURL = ""
    @State private var gitSubpath = ""

    enum InstallTab: String, CaseIterable {
        case search
        case git
        case sources
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            Divider()

            Picker("", selection: $selectedTab) {
                Text(Strings.Harnesses.installTabSearch).tag(InstallTab.search)
                Text(Strings.Harnesses.installTabGit).tag(InstallTab.git)
                Text(Strings.Harnesses.installTabSources).tag(InstallTab.sources)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .search: searchTab
            case .git: gitTab
            case .sources: sourcesTab
            }

            Divider()

            HStack {
                Button(Strings.Harnesses.installCancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding()
        }
        .frame(width: 520, height: 540)
        .onAppear {
            Task { await sourcesService.refresh() }
        }
        .onChange(of: searchQuery) { _, query in
            searchService.search(query)
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .sources {
                Task { await sourcesService.refresh() }
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Text(Strings.Harnesses.installTitle)
                .font(.headline)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Search Tab

extension HarnessInstallSheet {
    private var filteredHarnesses: [Harness] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return harnesses }
        return harnesses.filter {
            $0.name.lowercased().contains(q)
                || ($0.description?.lowercased().contains(q) ?? false)
        }
    }

    fileprivate var searchTab: some View {
        VStack(spacing: 0) {
            TextField(Strings.Harnesses.installSearchPlaceholder, text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            if searchService.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchService.results.isEmpty {
                List(searchService.results) { result in
                    searchResultRow(result)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
            } else if !filteredHarnesses.isEmpty {
                List(filteredHarnesses) { harness in
                    harnessRow(harness)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
            } else {
                emptyState(icon: "magnifyingglass", message: Strings.Harnesses.installSearchEmpty)
            }
        }
    }

    @ViewBuilder
    fileprivate func harnessRow(_ harness: Harness) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(harness.name).font(.body).fontWeight(.medium)
                    if !harness.version.isEmpty {
                        Text(harness.version).font(.caption).foregroundColor(.secondary)
                    }
                }
                if let desc = harness.description, !desc.isEmpty {
                    Text(desc).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
                if !harness.defaultVendor.isEmpty {
                    Text(harness.defaultVendor)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .clipShape(Capsule())
                }
            }
            Spacer()
            Text(Strings.Harnesses.installAlreadyInstalled)
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    fileprivate func searchResultRow(_ result: SearchResult) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.name)
                        .font(.body)
                        .fontWeight(.medium)
                    if let version = result.version, !version.isEmpty {
                        Text(version)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if let description = result.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 4) {
                    Text(Strings.Harnesses.installFrom(result.from.name))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ForEach(result.vendors ?? [], id: \.self) { vendor in
                        Text(vendor)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            if installedNames.contains(result.name) {
                Text(Strings.Harnesses.installAlreadyInstalled)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button(Strings.Harnesses.installConfirm) {
                    onInstall(HarnessInstallConfig(displayName: result.name, installArgs: [result.name]))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - From Git Tab

extension HarnessInstallSheet {
    fileprivate var gitTab: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Harnesses.installGitURL)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(Strings.Harnesses.installGitURLPlaceholder, text: $gitURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Harnesses.installGitSubpath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(Strings.Harnesses.installGitSubpathPlaceholder, text: $gitSubpath)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Harnesses.installCommandPreview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(buildGitPreview())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(16)

            Spacer()

            HStack {
                Spacer()
                Button(Strings.Harnesses.installConfirm) {
                    let trimmedURL = gitURL.trimmingCharacters(in: .whitespaces)
                    let trimmedSubpath = gitSubpath.trimmingCharacters(in: .whitespaces)
                    let args = trimmedSubpath.isEmpty ? [trimmedURL] : [trimmedURL, "--path", trimmedSubpath]
                    let name = trimmedURL.components(separatedBy: "/").last ?? trimmedURL
                    onInstall(HarnessInstallConfig(displayName: name, installArgs: args))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(gitURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }

    private func buildGitPreview() -> String {
        let trimmedURL = gitURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else { return "ynh install <url>" }
        var parts = ["ynh", "install", trimmedURL]
        let trimmedSubpath = gitSubpath.trimmingCharacters(in: .whitespaces)
        if !trimmedSubpath.isEmpty { parts.append(contentsOf: ["--path", trimmedSubpath]) }
        return parts.joined(separator: " ")
    }
}

// MARK: - Sources Tab

extension HarnessInstallSheet {
    fileprivate var sourcesTab: some View {
        VStack(spacing: 0) {
            if sourcesService.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sourcesService.sources.isEmpty {
                emptyState(icon: "folder.badge.questionmark", message: Strings.Harnesses.installSourcesEmpty)
            } else {
                List(sourcesService.sources) { source in
                    sourceRow(source)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Button {
                    chooseSourceDirectory()
                } label: {
                    Label(Strings.Harnesses.installSourcesAdd, systemImage: "plus")
                }
                .help(Strings.Harnesses.installSourcesAddHelp)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    fileprivate func sourceRow(_ source: YNHSource) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(source.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(Strings.Harnesses.installSourcesCount(source.harnesses))
                    .font(.caption2)
                    .foregroundColor(source.harnesses == 0 ? .orange : .secondary)
            }
            Spacer()
            Button(Strings.Harnesses.installSourcesRemove) {
                Task { await sourcesService.removeSource(name: source.name) }
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func chooseSourceDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        Task {
            let response = await panel.begin()
            if response == .OK, let url = panel.url {
                await sourcesService.addSource(path: url.path(percentEncoded: false), name: nil)
            }
        }
    }
}

// MARK: - Shared Helpers

extension HarnessInstallSheet {
    fileprivate func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
