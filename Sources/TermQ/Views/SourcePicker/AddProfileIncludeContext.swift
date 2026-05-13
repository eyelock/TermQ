import SwiftUI
import TermQShared

/// `SourcePickerContext` for adding an include to a profile.
///
/// **Library tab** lists plugins from configured marketplaces — same browse
/// UI as the harness-level include picker, but applies via
/// `ynh profile include add` (no picks — profile includes pull a whole path).
///
/// **Git URL tab** takes a direct git URL plus optional ref / path.
@MainActor
final class AddProfileIncludeContext: SourcePickerContext {
    let title: String
    let harnessID: String
    let profileName: String
    private let editor: HarnessProfileEditor

    enum LibraryStage {
        case browsing
        case configuring(plugin: MarketplacePlugin, marketplace: Marketplace)
    }

    @Published var libraryStage: LibraryStage = .browsing
    @Published var pluginSearch: String = ""
    @Published var isFinished = false

    // Git URL state
    @Published var gitURL: String = ""
    @Published var gitRef: String = ""
    @Published var gitPath: String = ""

    // Apply state
    @Published var isApplying: Bool = false
    @Published var errorMessage: String?

    init(harnessID: String, profileName: String, editor: HarnessProfileEditor) {
        self.title = Strings.Harnesses.addProfileIncludeTitle
        self.harnessID = harnessID
        self.profileName = profileName
        self.editor = editor
    }

    @ViewBuilder
    var library: some View { AddProfileIncludeLibraryView(context: self) }

    @ViewBuilder
    var gitURLView: some View { AddProfileIncludeGitURLView(context: self) }

    // MARK: - Library helpers

    func pickPlugin(_ plugin: MarketplacePlugin, marketplace: Marketplace) {
        libraryStage = .configuring(plugin: plugin, marketplace: marketplace)
    }

    func backToBrowsing() {
        libraryStage = .browsing
        errorMessage = nil
    }

    var libraryResolvedSource: (url: String, path: String?)? {
        guard case .configuring(let plugin, let marketplace) = libraryStage else { return nil }
        let resolved = plugin.source.resolved(marketplaceURL: marketplace.url)
        return (resolved.url, resolved.path)
    }

    var libraryResolvedRef: String? {
        guard case .configuring(_, let marketplace) = libraryStage else { return nil }
        return marketplace.ref
    }

    func gitURLCommandPreview() -> String {
        let trimmed = gitURL.trimmingCharacters(in: .whitespaces)
        let url = trimmed.isEmpty ? "<url>" : trimmed
        var parts = ["ynh", "profile", "include", "add", harnessID, profileName, url]
        let path = gitPath.trimmingCharacters(in: .whitespaces)
        let ref = gitRef.trimmingCharacters(in: .whitespaces)
        if !path.isEmpty { parts += ["--path", path] }
        if !ref.isEmpty { parts += ["--ref", ref] }
        return parts.joined(separator: " ")
    }

    // MARK: - Apply

    func applyLibrary() async {
        guard let source = libraryResolvedSource else { return }
        let opts = ProfileIncludeAddOptions(
            harness: harnessID,
            profileName: profileName,
            url: source.url,
            path: source.path,
            ref: libraryResolvedRef?.nilIfEmpty,
            replace: false
        )
        await runApply(opts: opts)
    }

    func applyGitURL() async {
        let trimmedURL = gitURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else { return }
        let opts = ProfileIncludeAddOptions(
            harness: harnessID,
            profileName: profileName,
            url: trimmedURL,
            path: gitPath.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            ref: gitRef.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            replace: false
        )
        await runApply(opts: opts)
    }

    private func runApply(opts: ProfileIncludeAddOptions) async {
        isApplying = true
        errorMessage = nil
        let succeeded = await editor.addInclude(opts)
        isApplying = false
        if succeeded {
            isFinished = true
        } else {
            errorMessage = editor.errorMessage ?? "Apply failed"
        }
    }
}

// MARK: - Library content

private struct AddProfileIncludeLibraryView: View {
    @ObservedObject var context: AddProfileIncludeContext

    var body: some View {
        switch context.libraryStage {
        case .browsing:
            browseView
        case .configuring(let plugin, let marketplace):
            configureView(plugin: plugin, marketplace: marketplace)
        }
    }

    private var browseView: some View {
        VStack(spacing: 0) {
            TextField(Strings.Harnesses.addIncludeSearchPlaceholder, text: $context.pluginSearch)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            let entries = filteredEntries
            if entries.isEmpty {
                emptyState
            } else {
                List(entries, id: \.plugin.id) { entry in
                    pluginRow(entry: entry)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(
                MarketplaceStore.shared.marketplaces.isEmpty
                    ? Strings.Harnesses.addIncludeNoMarketplaces
                    : Strings.Harnesses.addIncludeNoPluginMatches
            )
            .font(.callout)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct PluginEntry {
        let marketplace: Marketplace
        let plugin: MarketplacePlugin
    }

    private var allEntries: [PluginEntry] {
        MarketplaceStore.shared.marketplaces.flatMap { market in
            market.plugins.map { PluginEntry(marketplace: market, plugin: $0) }
        }
    }

    private var filteredEntries: [PluginEntry] {
        let query = context.pluginSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return allEntries }
        return allEntries.filter {
            $0.plugin.name.lowercased().contains(query)
                || ($0.plugin.description?.lowercased().contains(query) ?? false)
                || $0.marketplace.name.lowercased().contains(query)
        }
    }

    @ViewBuilder
    private func pluginRow(entry: PluginEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.plugin.name).font(.body).fontWeight(.medium)
                if let desc = entry.plugin.description, !desc.isEmpty {
                    Text(desc).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
                Text(entry.marketplace.name)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
            Spacer()
            Button(Strings.Harnesses.addDelegatePick) {
                context.pickPlugin(entry.plugin, marketplace: entry.marketplace)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func configureView(plugin: MarketplacePlugin, marketplace: Marketplace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    context.backToBrowsing()
                } label: {
                    Label(Strings.Harnesses.addDelegateBack, systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.bottom, 12)

            pluginHeaderCard(plugin: plugin, marketplace: marketplace)
                .padding(.bottom, 12)

            if let source = context.libraryResolvedSource {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Marketplace.Picker.commandPreview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(
                        "ynh profile include add \(context.harnessID) \(context.profileName) \(source.url)"
                            + (source.path.map { " --path \($0)" } ?? "")
                            + (context.libraryResolvedRef.map { " --ref \($0)" } ?? "")
                    )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            if let err = context.errorMessage {
                Text(err).font(.caption).foregroundColor(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button(Strings.Harnesses.addIncludeApplyButton) {
                    Task { await context.applyLibrary() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(context.isApplying)
            }
        }
        .padding(16)
    }

    private func pluginHeaderCard(plugin: MarketplacePlugin, marketplace: Marketplace) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plugin.name).font(.body).fontWeight(.medium)
            if let desc = plugin.description, !desc.isEmpty {
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
            Text(marketplace.name)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .clipShape(Capsule())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Git URL content

private struct AddProfileIncludeGitURLView: View {
    @ObservedObject var context: AddProfileIncludeContext

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(label: Strings.Harnesses.addIncludeGitURLLabel) {
                TextField(Strings.Harnesses.addIncludeGitURLPlaceholder, text: $context.gitURL)
                    .textFieldStyle(.roundedBorder)
            }
            field(label: Strings.Harnesses.addIncludeGitRefLabel) {
                TextField(Strings.Harnesses.addIncludeGitRefPlaceholder, text: $context.gitRef)
                    .textFieldStyle(.roundedBorder)
            }
            field(label: Strings.Harnesses.addIncludeGitPathLabel) {
                TextField(Strings.Harnesses.addIncludeGitPathPlaceholder, text: $context.gitPath)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Marketplace.Picker.commandPreview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(context.gitURLCommandPreview())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let err = context.errorMessage {
                Text(err).font(.caption).foregroundColor(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button(Strings.Harnesses.addIncludeApplyButton) {
                    Task { await context.applyGitURL() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    context.isApplying
                        || context.gitURL.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func field<Content: View>(
        label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            content()
        }
    }
}

// MARK: - Sheet host

/// Thin host that constructs an `AddProfileIncludeContext` and presents
/// the unified `SourcePicker`.
struct AddProfileIncludeSheetHost: View {
    let harnessID: String
    let profileName: String
    let editor: HarnessProfileEditor

    @StateObject private var context: AddProfileIncludeContext
    @Environment(\.dismiss) private var dismiss

    init(harnessID: String, profileName: String, editor: HarnessProfileEditor) {
        self.harnessID = harnessID
        self.profileName = profileName
        self.editor = editor
        _context = StateObject(
            wrappedValue: AddProfileIncludeContext(harnessID: harnessID, profileName: profileName, editor: editor))
    }

    var body: some View {
        SourcePicker(context: context)
            .onChange(of: context.isFinished) { _, finished in
                if finished { dismiss() }
            }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Optional where Wrapped == String {
    fileprivate var nilIfEmpty: String? {
        guard let value = self, !value.isEmpty else { return nil }
        return value
    }
}
