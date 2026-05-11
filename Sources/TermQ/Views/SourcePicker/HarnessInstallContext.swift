import AppKit
import SwiftUI
import TermQShared

/// `SourcePickerContext` for installing a new harness.
///
/// **Library tab** combines the previous Search + Sources tabs:
/// - search field at the top with a gear affordance for managing sources
/// - default browse mode shows Installed / Available from Registries /
///   Available Locally sections
/// - active search shows filtered registry + source results inline
///
/// **Git URL tab** is unchanged from the prior implementation: URL / ref /
/// subpath fields with a command preview and an Install button.
@MainActor
final class HarnessInstallContext: SourcePickerContext {
    let title: String = Strings.Harnesses.installTitle

    let installedNames: Set<String>
    let installedHarnesses: [Harness]
    let onInstall: (HarnessInstallConfig) -> Void

    let searchService = HarnessSearchService()
    let sourcesService = SourcesService()

    @Published var searchQuery: String = ""
    @Published var gitURL: String = ""
    @Published var gitRef: String = ""
    @Published var gitSubpath: String = ""
    @Published var showManageSources: Bool = false

    init(
        installedNames: Set<String>,
        installedHarnesses: [Harness],
        onInstall: @escaping (HarnessInstallConfig) -> Void
    ) {
        self.installedNames = installedNames
        self.installedHarnesses = installedHarnesses
        self.onInstall = onInstall
    }

    @ViewBuilder
    var library: some View {
        HarnessInstallLibraryView(context: self)
    }

    @ViewBuilder
    var gitURLView: some View {
        HarnessInstallGitURLView(context: self)
    }

    func gitURLPreview() -> String {
        let trimmedURL = gitURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else { return "ynh install <url>" }
        var parts = ["ynh", "install", trimmedURL]
        let trimmedSubpath = gitSubpath.trimmingCharacters(in: .whitespaces)
        if !trimmedSubpath.isEmpty { parts.append(contentsOf: ["--path", trimmedSubpath]) }
        let trimmedRef = gitRef.trimmingCharacters(in: .whitespaces)
        if !trimmedRef.isEmpty { parts.append(contentsOf: ["--ref", trimmedRef]) }
        return parts.joined(separator: " ")
    }

    func applyGitURL() -> HarnessInstallConfig? {
        let trimmedURL = gitURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else { return nil }
        let trimmedSubpath = gitSubpath.trimmingCharacters(in: .whitespaces)
        let trimmedRef = gitRef.trimmingCharacters(in: .whitespaces)
        var args = [trimmedURL]
        if !trimmedSubpath.isEmpty { args += ["--path", trimmedSubpath] }
        if !trimmedRef.isEmpty { args += ["--ref", trimmedRef] }
        let name = trimmedURL.components(separatedBy: "/").last ?? trimmedURL
        return HarnessInstallConfig(displayName: name, installArgs: args)
    }

    func applyLibrary(result: SearchResult) -> HarnessInstallConfig {
        let ref: String
        if let repo = result.repo, !repo.isEmpty {
            // Build a path-shaped canonical ref: "github.com/org/repo/path" or
            // "github.com/org/repo/name". YNH install resolves this as a git
            // source — no registry lookup required, so it works across machines
            // regardless of which registries are configured.
            let within: String
            if let path = result.path, !path.isEmpty {
                within = path
            } else {
                within = result.name
            }
            ref = "\(repo)/\(within)"
        } else {
            ref = result.name
        }
        return HarnessInstallConfig(displayName: result.name, installArgs: [ref])
    }
}

// MARK: - Library content

private struct HarnessInstallLibraryView: View {
    @ObservedObject var context: HarnessInstallContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField(
                    Strings.Harnesses.installSearchPlaceholder,
                    text: $context.searchQuery
                )
                .textFieldStyle(.roundedBorder)

                Button {
                    context.showManageSources = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help(Strings.Harnesses.installManageSourcesHelp)
                .sheet(isPresented: $context.showManageSources) {
                    SourcePickerManageSourcesSheet(sourcesService: context.sourcesService)
                        .frame(width: 420, height: 320)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            content

            Divider()

            HStack {
                Button {
                    chooseLocalDirectory()
                } label: {
                    Label(Strings.Harnesses.browseLocal, systemImage: "folder.badge.plus")
                }
                .help(Strings.Harnesses.browseLocalHelp)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear {
            Task { await context.sourcesService.refresh() }
            context.searchService.search(context.searchQuery)
        }
        .onChange(of: context.searchQuery) { _, query in
            context.searchService.search(query)
        }
    }

    private func chooseLocalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        Task {
            let response = await panel.begin()
            if response == .OK, let url = panel.url {
                await context.sourcesService.addSource(
                    path: url.path(percentEncoded: false),
                    name: nil
                )
                // Re-run search so newly-registered source's harnesses surface.
                context.searchService.search(context.searchQuery)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let trimmed = context.searchQuery
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        let installed = filterInstalled(context.installedHarnesses, query: trimmed)
        let uninstalled = context.searchService.results.filter {
            !context.installedNames.contains($0.name)
        }
        let fromLocal =
            uninstalled
            .filter { $0.from.type == .source }
            .filter { matches($0, query: trimmed) }
            .sorted { $0.name < $1.name }
        let fromRegistry =
            uninstalled
            .filter { $0.from.type == .registry }
            .filter { matches($0, query: trimmed) }
            .sorted { $0.name < $1.name }

        List {
            if !installed.isEmpty {
                Section(Strings.Harnesses.installSectionInstalled) {
                    ForEach(installed) { harness in
                        installedRow(harness)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }
            }
            if !fromLocal.isEmpty {
                Section(Strings.Harnesses.installSectionLocal) {
                    ForEach(fromLocal) { result in
                        searchResultRow(result)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }
            }
            if shouldShowRegistrySection(fromRegistry: fromRegistry, isFiltering: !trimmed.isEmpty) {
                Section {
                    registryRows(fromRegistry: fromRegistry, isFiltering: !trimmed.isEmpty)
                } header: {
                    Text(Strings.Harnesses.installSectionAvailable)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if !trimmed.isEmpty,
                installed.isEmpty,
                fromLocal.isEmpty,
                fromRegistry.isEmpty,
                !context.searchService.isSearching,
                context.searchService.error == nil
            {
                emptyState(
                    icon: "magnifyingglass",
                    message: Strings.Harnesses.installSearchEmpty
                )
            }
        }
    }

    @ViewBuilder
    private func registryRows(fromRegistry: [SearchResult], isFiltering: Bool) -> some View {
        // Treat "haven't searched yet" the same as "actively searching" so
        // the empty-state copy doesn't flash before the initial search lands.
        if context.searchService.isSearching || !context.searchService.hasSearched {
            HStack {
                ProgressView().controlSize(.small)
                Text(Strings.Harnesses.installBrowsing)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } else if let err = context.searchService.error {
            VStack(alignment: .leading, spacing: 6) {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                Button(Strings.Harnesses.installRetry) {
                    context.searchService.search("")
                }
                .font(.caption)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } else if fromRegistry.isEmpty, !isFiltering {
            Text(Strings.Harnesses.installSectionAvailableEmpty)
                .font(.caption)
                .foregroundColor(.secondary)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } else if !fromRegistry.isEmpty {
            ForEach(fromRegistry) { result in
                searchResultRow(result)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
        }
    }

    private func shouldShowRegistrySection(fromRegistry: [SearchResult], isFiltering: Bool) -> Bool {
        // Always show while loading or when an error needs surfacing — those are
        // global states orthogonal to the filter. Otherwise, only show when there
        // are matching rows, or when nothing is being filtered (so the
        // "No marketplaces configured" empty-state row can be displayed).
        if context.searchService.isSearching { return true }
        if context.searchService.error != nil { return true }
        if !fromRegistry.isEmpty { return true }
        return !isFiltering
    }

    private func filterInstalled(_ harnesses: [Harness], query: String) -> [Harness] {
        guard !query.isEmpty else { return harnesses }
        return harnesses.filter { harness in
            harness.name.lowercased().contains(query)
                || (harness.description?.lowercased().contains(query) ?? false)
        }
    }

    private func matches(_ result: SearchResult, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if result.name.lowercased().contains(query) { return true }
        if let description = result.description, description.lowercased().contains(query) {
            return true
        }
        return false
    }

    @ViewBuilder
    private func installedRow(_ harness: Harness) -> some View {
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
    private func searchResultRow(_ result: SearchResult) -> some View {
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
                    let isRegistry = result.from.type == .registry
                    Text(result.from.name)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(isRegistry ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.15))
                        .foregroundColor(isRegistry ? .blue : .secondary)
                        .clipShape(Capsule())
                }
            }
            Spacer()
            if context.installedNames.contains(result.name) {
                Text(Strings.Harnesses.installAlreadyInstalled)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button(Strings.Harnesses.installConfirm) {
                    context.onInstall(context.applyLibrary(result: result))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
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

// MARK: - Git URL content

private struct HarnessInstallGitURLView: View {
    @ObservedObject var context: HarnessInstallContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Harnesses.installGitURL)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(
                        Strings.Harnesses.installGitURLPlaceholder,
                        text: $context.gitURL
                    )
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Harnesses.installGitRef)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(
                        Strings.Harnesses.installGitRefPlaceholder,
                        text: $context.gitRef
                    )
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Harnesses.installGitSubpath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(
                        Strings.Harnesses.installGitSubpathPlaceholder,
                        text: $context.gitSubpath
                    )
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Harnesses.installCommandPreview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(context.gitURLPreview())
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
                    if let config = context.applyGitURL() {
                        context.onInstall(config)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(context.gitURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }
}
