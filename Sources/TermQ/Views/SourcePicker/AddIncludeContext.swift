import SwiftUI
import TermQShared

/// `SourcePickerContext` for adding an include to a harness.
///
/// **Library tab** lists plugins from configured marketplaces. The user
/// searches/picks; if the plugin matches an already-installed include,
/// the row routes to the editor's edit sheet instead of attempting a
/// duplicate add. Picking a fresh plugin enters a Configure stage where
/// the user toggles which artifact paths to bring in (the picks tree).
///
/// **Git URL tab** takes a direct git URL plus optional ref / path. No
/// picks (raw URLs aren't introspected); apply runs immediately on the
/// review preview.
///
/// Apply invokes `IncludeApplier` (`ynh include add`) and on success
/// hands off to `HarnessIncludeEditor.didFinishAddingInclude(harnessID:)`
/// which dismisses the sheet and reloads detail.
@MainActor
final class AddIncludeContext: SourcePickerContext {
    let title: String

    let harnessID: String
    var existingIncludes: [IncludeEditTarget]
    let editor: HarnessIncludeEditor

    let applier: IncludeApplier
    private let detector: any YNHDetectorProtocol

    /// Library stage state — drives whether the Library tab shows the
    /// plugin browser or the Configure picks panel.
    enum LibraryStage {
        case browsing
        case configuring(plugin: MarketplacePlugin, marketplace: Marketplace)
    }

    @Published var libraryStage: LibraryStage = .browsing
    @Published var pluginSearch: String = ""

    // Git URL state
    @Published var gitURL: String = ""
    @Published var gitRef: String = ""
    @Published var gitPath: String = ""

    // Picks state (populated when entering Configure stage)
    @Published var resolvedPicks: [String] = []
    @Published var selectedPicks: Set<String> = []
    @Published var isLoadingPicks: Bool = false
    @Published var picksLoadError: String?

    // Apply state
    @Published var isApplying: Bool = false
    @Published var errorMessage: String?

    init(
        harnessID: String,
        existingIncludes: [IncludeEditTarget],
        editor: HarnessIncludeEditor,
        detector: any YNHDetectorProtocol = YNHDetector.shared,
        applier: IncludeApplier = IncludeApplier()
    ) {
        self.title = Strings.Harnesses.addIncludeButton
        self.harnessID = harnessID
        self.existingIncludes = existingIncludes
        self.editor = editor
        self.detector = detector
        self.applier = applier
    }

    @ViewBuilder
    var library: some View { AddIncludeLibraryView(context: self) }

    @ViewBuilder
    var gitURLView: some View { AddIncludeGitURLView(context: self) }

    // MARK: - Library helpers

    func pickPlugin(_ plugin: MarketplacePlugin, marketplace: Marketplace) {
        resolvedPicks = plugin.picks
        selectedPicks = Set(plugin.picks)
        picksLoadError = nil
        libraryStage = .configuring(plugin: plugin, marketplace: marketplace)
        if plugin.skillsState != .eager && plugin.picks.isEmpty {
            Task { await loadPicksForSelectedPlugin() }
        }
    }

    func backToBrowsing() {
        libraryStage = .browsing
        resolvedPicks = []
        selectedPicks = []
        isLoadingPicks = false
        picksLoadError = nil
        errorMessage = nil
    }

    func existingMatch(for plugin: MarketplacePlugin, in marketplace: Marketplace) -> IncludeEditTarget? {
        let resolved = plugin.source.resolved(marketplaceURL: marketplace.url)
        return existingIncludes.first { target in
            IncludeKey(url: target.sourceURL, path: target.path)
                .matches(url: resolved.url, path: resolved.path)
        }
    }

    /// Refresh picks for the currently-configured plugin (lazy-load case).
    func loadPicksForSelectedPlugin() async {
        guard case .configuring(let plugin, let marketplace) = libraryStage else { return }
        isLoadingPicks = true
        defer { isLoadingPicks = false }
        do {
            let picks = try await MarketplaceFetcher.fetchSkills(for: plugin)
            resolvedPicks = picks
            selectedPicks = Set(picks)
            // Update marketplace store with newly-fetched picks so we don't
            // re-fetch next time.
            if var market = MarketplaceStore.shared.marketplaces.first(where: { $0.id == marketplace.id }),
                let idx = market.plugins.firstIndex(where: { $0.id == plugin.id })
            {
                market.plugins[idx].picks = picks
                market.plugins[idx].skillsState = .eager
                MarketplaceStore.shared.update(market)
                libraryStage = .configuring(plugin: market.plugins[idx], marketplace: market)
            }
        } catch {
            picksLoadError = error.localizedDescription
        }
    }

    // MARK: - Apply

    func selectAllPicks() { selectedPicks = Set(resolvedPicks) }
    func selectNoPicks() { selectedPicks = [] }

    /// Resolved `(url, path)` for the currently-configuring plugin.
    var libraryResolvedSource: (url: String, path: String?)? {
        guard case .configuring(let plugin, let marketplace) = libraryStage else { return nil }
        let resolved = plugin.source.resolved(marketplaceURL: marketplace.url)
        return (resolved.url, resolved.path)
    }

    /// Effective ref for the configuring plugin — inherited from its
    /// marketplace.
    var libraryResolvedRef: String? {
        guard case .configuring(_, let marketplace) = libraryStage else { return nil }
        return marketplace.ref
    }

    func libraryCommandPreview() -> String {
        guard let source = libraryResolvedSource else { return "" }
        return commandPreview(
            sourceURL: source.url,
            path: source.path,
            ref: libraryResolvedRef,
            picks: pickArgument()
        )
    }

    func gitURLCommandPreview() -> String {
        let trimmed = gitURL.trimmingCharacters(in: .whitespaces)
        let url = trimmed.isEmpty ? "<url>" : trimmed
        let path = gitPath.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let ref = gitRef.trimmingCharacters(in: .whitespaces).nilIfEmpty
        return commandPreview(sourceURL: url, path: path, ref: ref, picks: nil)
    }

    private func commandPreview(sourceURL: String, path: String?, ref: String?, picks: [String]?)
        -> String
    {
        var parts = ["ynh", "include", "add", harnessID, sourceURL]
        if let path = path { parts += ["--path", path] }
        if let ref = ref, !ref.isEmpty { parts += ["--ref", ref] }
        if let picks = picks, !picks.isEmpty {
            parts += ["--pick", picks.joined(separator: ",")]
        }
        return parts.joined(separator: " ")
    }

    /// Picks argument to pass to `ynh include add`. nil/empty means no
    /// flag — selecting all = no flag (YNH default), empty selection
    /// from a non-empty list = no flag (treated as "use default").
    private func pickArgument() -> [String]? {
        guard !resolvedPicks.isEmpty else { return nil }
        if selectedPicks.count == resolvedPicks.count { return nil }
        if selectedPicks.isEmpty { return nil }
        return Array(selectedPicks).sorted()
    }

    func applyLibrary() async {
        guard let source = libraryResolvedSource, let ynhPath = readyYnhPath() else { return }
        let picks = pickArgument() ?? []
        let opts = IncludeApplicationOptions(
            harness: harnessID,
            sourceURL: source.url,
            path: source.path,
            ref: libraryResolvedRef?.nilIfEmpty,
            pick: picks
        )
        await runApply(opts: opts, ynhPath: ynhPath)
    }

    func applyGitURL() async {
        let trimmedURL = gitURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty, let ynhPath = readyYnhPath() else { return }
        let opts = IncludeApplicationOptions(
            harness: harnessID,
            sourceURL: trimmedURL,
            path: gitPath.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            ref: gitRef.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            pick: []
        )
        await runApply(opts: opts, ynhPath: ynhPath)
    }

    private func runApply(opts: IncludeApplicationOptions, ynhPath: String) async {
        isApplying = true
        errorMessage = nil
        TermQLogger.session.info("AddInclude: apply starting")
        await applier.apply(opts, ynhPath: ynhPath, environment: ynhEnvironment())
        isApplying = false
        if applier.succeeded {
            TermQLogger.session.info("AddInclude: apply succeeded; dismissing")
            await editor.didFinishAddingInclude(harnessID: harnessID)
        } else {
            // applier.errorMessage may contain user-visible command output;
            // log presence only, not content (logging-rules: terminal output
            // is sensitive). The full message renders inline in the sheet.
            TermQLogger.session.error(
                "AddInclude: apply FAILED (errorMessage \(applier.errorMessage == nil ? "absent" : "present"))"
            )
            errorMessage = applier.errorMessage ?? "Apply failed"
        }
    }

    private func readyYnhPath() -> String? {
        if case .ready(let ynhPath, _, _) = detector.status { return ynhPath }
        return nil
    }

    private func ynhEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = detector.ynhHomeOverride {
            env["YNH_HOME"] = override
        }
        return env
    }
}

extension Optional where Wrapped == String {
    fileprivate var nilIfEmpty: String? {
        guard let value = self, !value.isEmpty else { return nil }
        return value
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Library content

private struct AddIncludeLibraryView: View {
    @ObservedObject var context: AddIncludeContext

    var body: some View {
        switch context.libraryStage {
        case .browsing:
            AddIncludeLibraryBrowseView(context: context)
        case .configuring(let plugin, let marketplace):
            AddIncludeLibraryConfigureView(
                context: context,
                plugin: plugin,
                marketplace: marketplace
            )
        }
    }
}

private struct AddIncludeLibraryBrowseView: View {
    @ObservedObject var context: AddIncludeContext
    @ObservedObject private var marketplaceStore = MarketplaceStore.shared

    var body: some View {
        VStack(spacing: 0) {
            TextField(
                Strings.Harnesses.addIncludeSearchPlaceholder,
                text: $context.pluginSearch
            )
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
                marketplaceStore.marketplaces.isEmpty
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
        marketplaceStore.marketplaces.flatMap { market in
            market.plugins.map { PluginEntry(marketplace: market, plugin: $0) }
        }
    }

    private var filteredEntries: [PluginEntry] {
        let query = context.pluginSearch
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !query.isEmpty else { return allEntries }
        return allEntries.filter {
            $0.plugin.name.lowercased().contains(query)
                || ($0.plugin.description?.lowercased().contains(query) ?? false)
                || $0.marketplace.name.lowercased().contains(query)
        }
    }

    @ViewBuilder
    private func pluginRow(entry: PluginEntry) -> some View {
        let existingMatch = context.existingMatch(for: entry.plugin, in: entry.marketplace)
        let alreadyInstalled = existingMatch != nil

        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.plugin.name).font(.body).fontWeight(.medium)
                    if alreadyInstalled {
                        Text(Strings.Harnesses.addIncludeAlreadyInstalled)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())
                    }
                }
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
            if let match = existingMatch {
                Button(Strings.Harnesses.addIncludeEditExisting) {
                    context.editor.switchToEditing(match)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(Strings.Harnesses.addIncludeAlreadyInstalledHelp)
            } else {
                Button(Strings.Harnesses.addDelegatePick) {
                    context.pickPlugin(entry.plugin, marketplace: entry.marketplace)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}

private struct AddIncludeLibraryConfigureView: View {
    @ObservedObject var context: AddIncludeContext
    let plugin: MarketplacePlugin
    let marketplace: Marketplace
    @Environment(\.dismiss) private var dismiss

    private enum Step { case artifacts, apply }
    @State private var step: Step = .artifacts

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader
                .padding(.bottom, 12)

            switch step {
            case .artifacts:
                artifactsStep
            case .apply:
                applyStep
            }
        }
        .padding(16)
    }

    // MARK: - Step header

    private var stepHeader: some View {
        HStack(spacing: 16) {
            Button {
                context.backToBrowsing()
            } label: {
                Label(
                    Strings.Harnesses.addDelegateBack,
                    systemImage: "chevron.left"
                )
            }
            .buttonStyle(.borderless)

            Spacer()

            stepIndicator(index: 0, label: "Artifacts", isCurrent: step == .artifacts, isDone: step == .apply)
            stepDivider
            stepIndicator(index: 1, label: "Apply", isCurrent: step == .apply, isDone: false)
        }
    }

    private func stepIndicator(index: Int, label: String, isCurrent: Bool, isDone: Bool) -> some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(
                        isCurrent
                            ? Color.accentColor
                            : (isDone ? Color.green : Color.secondary.opacity(0.3))
                    )
                    .frame(width: 20, height: 20)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundColor(isCurrent ? .primary : .secondary)
        }
    }

    private var stepDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 24, height: 1)
    }

    // MARK: - Step 1: Artifacts

    private var artifactsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            pluginHeaderCard
            IncludePicksSelector(
                availablePicks: context.resolvedPicks,
                selected: $context.selectedPicks,
                isLoading: context.isLoadingPicks,
                loadError: context.picksLoadError
            )
            Spacer()
            HStack {
                Spacer()
                Button("Next") { step = .apply }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        context.isLoadingPicks
                            || (!context.resolvedPicks.isEmpty && context.selectedPicks.isEmpty)
                    )
            }
        }
    }

    // MARK: - Step 2: Apply

    private var applyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            pluginHeaderCard

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Marketplace.Picker.commandPreview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(context.libraryCommandPreview())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let err = context.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            HStack {
                Button("Back") { step = .artifacts }
                    .buttonStyle(.bordered)
                Spacer()
                Button(Strings.Harnesses.addIncludeApplyButton) {
                    Task { await context.applyLibrary() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(context.isApplying)
            }
        }
    }

    // MARK: - Shared plugin header

    private var pluginHeaderCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plugin.name)
                .font(.body)
                .fontWeight(.medium)
            if let desc = plugin.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(marketplace.name)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .clipShape(Capsule())
            if let inheritedRef = marketplace.ref, !inheritedRef.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill").imageScale(.small)
                    Text("Pinned to ")
                        .font(.caption)
                    Text(inheritedRef)
                        .font(.system(size: 11, design: .monospaced))
                    Text("(inherited from marketplace)")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath").imageScale(.small)
                    Text("Tracks marketplace HEAD (unpinned)")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Git URL content

private struct AddIncludeGitURLView: View {
    @ObservedObject var context: AddIncludeContext

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Harnesses.addIncludeGitURLLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(
                    Strings.Harnesses.addIncludeGitURLPlaceholder,
                    text: $context.gitURL
                )
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Harnesses.addIncludeGitRefLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(
                    Strings.Harnesses.addIncludeGitRefPlaceholder,
                    text: $context.gitRef
                )
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Harnesses.addIncludeGitPathLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(
                    Strings.Harnesses.addIncludeGitPathPlaceholder,
                    text: $context.gitPath
                )
                .textFieldStyle(.roundedBorder)
            }

            Text(Strings.Harnesses.addIncludeGitURLHint)
                .font(.caption)
                .foregroundColor(.secondary)

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
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
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
}
