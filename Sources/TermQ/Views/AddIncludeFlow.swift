import SwiftUI
import TermQShared

// MARK: - Reusable picks selector

/// Checkbox list of artifact paths used by both the Add Include flow and the
/// Edit Include sheet. Caller owns the selection set; this view is a pure
/// renderer with loading and error states.
struct IncludePicksSelector: View {
    let availablePicks: [String]
    @Binding var selected: Set<String>
    var isLoading: Bool = false
    var loadError: String?
    var emptyMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Strings.Harnesses.addIncludePicksPrompt)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(Strings.Marketplace.Picker.selectAll) {
                    selected = Set(availablePicks)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.caption)
                .disabled(availablePicks.isEmpty)
                Text("·").foregroundColor(.secondary).font(.caption)
                Button(Strings.Marketplace.Picker.selectNone) {
                    selected = []
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.caption)
                .disabled(selected.isEmpty)
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Strings.Marketplace.pluginLoadingArtifacts)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let err = loadError {
            Label(err, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.orange)
        } else if availablePicks.isEmpty {
            Text(emptyMessage ?? Strings.Marketplace.pluginNoArtifacts)
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(availablePicks, id: \.self) { pick in
                        pickRow(pick)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 140, maxHeight: 240)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func pickRow(_ pick: String) -> some View {
        let isSelected = selected.contains(pick)
        return Button {
            if isSelected { selected.remove(pick) } else { selected.insert(pick) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(pick).font(.system(size: 12, design: .monospaced))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - IncludeKey

/// Compact identifier for an existing include used to detect duplicates in
/// the Add Include flow. The match is normalized — trailing `.git` and
/// scheme casing are ignored — so users see a plugin marked already-installed
/// even when the recorded URL form differs slightly from the marketplace's.
struct IncludeKey: Equatable {
    let url: String
    let path: String?

    func matches(url candidate: String, path candidatePath: String?) -> Bool {
        let lhs = Self.normalize(self.url)
        let rhs = Self.normalize(candidate)
        let lhsPath = (self.path?.isEmpty == true) ? nil : self.path
        let rhsPath = (candidatePath?.isEmpty == true) ? nil : candidatePath
        return lhs == rhs && lhsPath == rhsPath
    }

    private static func normalize(_ url: String) -> String {
        var normalized = url
        if normalized.hasSuffix(".git") { normalized.removeLast(4) }
        return normalized.lowercased()
    }
}

// MARK: - Plugin lookup helpers

/// Pure helpers for matching includes to marketplace plugins. Used both to
/// detect already-installed plugins (so we can disable them in the picker)
/// and to discover the available picks for an existing include in the edit
/// sheet.
enum IncludePluginLookup {
    struct PluginMatch {
        let marketplace: Marketplace
        let plugin: MarketplacePlugin
    }

    /// Find the plugin whose `(resolvedURL, resolvedPath)` matches the given
    /// pair. Marketplace `url` comparison uses normalized git URLs to avoid
    /// trailing-`.git` mismatches.
    static func find(
        sourceURL: String,
        path: String?,
        in marketplaces: [Marketplace]
    ) -> PluginMatch? {
        let needleURL = normalize(sourceURL)
        let needlePath = (path?.isEmpty == true) ? nil : path
        for market in marketplaces {
            for plugin in market.plugins {
                let resolved = plugin.source.resolved(marketplaceURL: market.url)
                let foundURL = normalize(resolved.url)
                let foundPath = (resolved.path?.isEmpty == true) ? nil : resolved.path
                if foundURL == needleURL && foundPath == needlePath {
                    return PluginMatch(marketplace: market, plugin: plugin)
                }
            }
        }
        return nil
    }

    /// Strip a trailing `.git` suffix and normalize scheme so two URLs that
    /// only differ in `.git`/scheme casing compare equal.
    private static func normalize(_ url: String) -> String {
        var normalized = url
        if normalized.hasSuffix(".git") { normalized.removeLast(4) }
        return normalized.lowercased()
    }
}

// MARK: - Coordinator

/// Drives the inline "Add Include" flow shown below the includes section of
/// the harness detail pane.
///
/// Step machine:
///   source → picks → review → running → success
///
/// The view binds against the published step + step-specific fields; tests
/// drive transitions directly by invoking the coordinator methods.
@MainActor
final class AddIncludeStore: ObservableObject {
    enum Step: Equatable {
        case source
        case picks
        case review
        case running
    }

    enum SourceMode: String, CaseIterable, Identifiable {
        case marketplace
        case gitURL
        var id: String { rawValue }
    }

    @Published var step: Step = .source

    // MARK: source-step state
    @Published var sourceMode: SourceMode = .marketplace
    /// Marketplace path: chosen plugin (and the marketplace it belongs to).
    @Published var selectedPlugin: MarketplacePlugin?
    @Published var selectedMarketplace: Marketplace?
    /// Search filter for the flat plugin list.
    @Published var pluginSearch: String = ""

    /// Git URL path: free-form fields.
    @Published var gitURL: String = ""
    @Published var gitRef: String = ""
    @Published var gitPath: String = ""

    // MARK: picks-step state
    @Published var resolvedPicks: [String] = []
    @Published var selectedPicks: Set<String> = []
    @Published var isLoadingPicks: Bool = false
    @Published var picksLoadError: String?

    // MARK: review/run state
    @Published private(set) var outputLines: [String] = []
    @Published var errorMessage: String?

    let applier: IncludeApplier
    private let detector: any YNHDetectorProtocol

    init(
        detector: any YNHDetectorProtocol = YNHDetector.shared,
        applier: IncludeApplier = IncludeApplier()
    ) {
        self.detector = detector
        self.applier = applier
    }

    /// Reset to the initial state. Called when the flow is dismissed and re-opened.
    func reset() {
        step = .source
        sourceMode = .marketplace
        selectedPlugin = nil
        selectedMarketplace = nil
        pluginSearch = ""
        gitURL = ""
        gitRef = ""
        gitPath = ""
        resolvedPicks = []
        selectedPicks = []
        isLoadingPicks = false
        picksLoadError = nil
        outputLines = []
        errorMessage = nil
    }

    // MARK: - Resolved source

    /// Effective `(url, path)` for `ynh include add` based on the chosen
    /// source mode. Returns nil when the user has not made a valid selection.
    var resolvedSource: (url: String, path: String?)? {
        switch sourceMode {
        case .marketplace:
            guard let plugin = selectedPlugin, let marketplace = selectedMarketplace else { return nil }
            let resolved = plugin.source.resolved(marketplaceURL: marketplace.url)
            return (resolved.url, resolved.path)
        case .gitURL:
            let trimmedURL = gitURL.trimmingCharacters(in: .whitespaces)
            guard !trimmedURL.isEmpty else { return nil }
            let trimmedPath = gitPath.trimmingCharacters(in: .whitespaces)
            return (trimmedURL, trimmedPath.isEmpty ? nil : trimmedPath)
        }
    }

    /// Effective ref for the chosen source. Marketplace plugins inherit the
    /// marketplace's ref; git URL path uses the manually-typed ref.
    var resolvedRef: String? {
        switch sourceMode {
        case .marketplace:
            return selectedMarketplace?.ref
        case .gitURL:
            let trimmed = gitRef.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// True when the user has supplied enough on the source step to advance.
    var canLeaveSourceStep: Bool {
        resolvedSource != nil
    }

    /// Step displayed when leaving source — picks if the source might offer
    /// any, otherwise jump straight to review.
    func advanceFromSource() {
        guard canLeaveSourceStep else { return }
        switch sourceMode {
        case .marketplace:
            // Picks list comes from the plugin (eager) or needs fetching.
            if let plugin = selectedPlugin {
                resolvedPicks = plugin.picks
                selectedPicks = Set(plugin.picks)
                if plugin.picks.isEmpty && plugin.skillsState != .eager {
                    step = .picks
                    Task { await loadPicksForSelectedPlugin() }
                    return
                }
                step = plugin.picks.isEmpty ? .review : .picks
            } else {
                step = .review
            }
        case .gitURL:
            // Git URL path: no picks introspection. User can add the include
            // wholesale; if they want narrow picks they can edit afterwards.
            resolvedPicks = []
            selectedPicks = []
            step = .review
        }
    }

    func goBack() {
        switch step {
        case .picks:
            step = .source
        case .review:
            step = (resolvedPicks.isEmpty) ? .source : .picks
        case .source, .running:
            break
        }
    }

    func selectAllPicks() { selectedPicks = Set(resolvedPicks) }
    func selectNoPicks() { selectedPicks = [] }
    func togglePick(_ pick: String) {
        if selectedPicks.contains(pick) { selectedPicks.remove(pick) } else { selectedPicks.insert(pick) }
    }

    /// Whether the apply command is ready to run.
    var canApply: Bool {
        readyYnhPath() != nil && resolvedSource != nil
    }

    /// Pure preview of the `ynh include add` command for the review step.
    func commandPreview(harnessName: String) -> String {
        guard let source = resolvedSource else { return "" }
        var parts = ["ynh", "include", "add", harnessName, source.url]
        if let path = source.path { parts += ["--path", path] }
        let pickSubset = pickArgument()
        if let picks = pickSubset, !picks.isEmpty {
            parts += ["--pick", picks.joined(separator: ",")]
        }
        return parts.joined(separator: " ")
    }

    /// The picks argument to pass to `ynh include add`. nil/empty means no flag.
    /// Selecting all = no flag (YNH default behaviour); empty selection from a
    /// non-empty list = no flag (treated the same as none chosen — let YNH default).
    private func pickArgument() -> [String]? {
        guard !resolvedPicks.isEmpty else { return nil }
        if selectedPicks.count == resolvedPicks.count { return nil }
        if selectedPicks.isEmpty { return nil }
        return Array(selectedPicks).sorted()
    }

    /// Apply the include. Returns whether the apply succeeded.
    @discardableResult
    func apply(harnessName: String) async -> Bool {
        guard let source = resolvedSource, let ynhPath = readyYnhPath() else { return false }
        let picks = pickArgument() ?? []
        let opts = IncludeApplicationOptions(
            harness: harnessName,
            sourceURL: source.url,
            path: source.path,
            pick: picks
        )
        step = .running
        outputLines = []
        await applier.apply(opts, ynhPath: ynhPath, environment: ynhEnvironment())
        outputLines = applier.outputLines
        if applier.succeeded {
            return true
        } else {
            errorMessage = applier.errorMessage
            step = .review
            return false
        }
    }

    /// Fetch picks for the currently-selected plugin if the marketplace lazy-loads them.
    func loadPicksForSelectedPlugin() async {
        guard let plugin = selectedPlugin else { return }
        isLoadingPicks = true
        defer { isLoadingPicks = false }
        do {
            let picks = try await MarketplaceFetcher.fetchSkills(for: plugin)
            resolvedPicks = picks
            selectedPicks = Set(picks)
            if var market = selectedMarketplace,
                let idx = market.plugins.firstIndex(where: { $0.id == plugin.id })
            {
                market.plugins[idx].picks = picks
                market.plugins[idx].skillsState = .eager
                MarketplaceStore.shared.update(market)
                selectedMarketplace = market
                selectedPlugin = market.plugins[idx]
            }
        } catch {
            picksLoadError = error.localizedDescription
        }
    }

    private func readyYnhPath() -> String? {
        if case .ready(let ynhPath, _, _) = detector.status { return ynhPath }
        return nil
    }

    private func ynhEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride {
            env["YNH_HOME"] = override
        }
        return env
    }
}

// MARK: - Inline view

/// Inline panel rendered below the includes section while the user adds a
/// new include. Hosts the three-step flow: source → picks → review.
/// On apply success the editor coordinator closes the panel and re-fetches
/// detail; there is no separate success step.
struct AddIncludeFlow: View {
    let harnessName: String
    @ObservedObject var editor: HarnessIncludeEditor
    /// Existing includes on this harness — used to mark plugin rows as
    /// already-added. Clicking such a row opens the Edit sheet for the
    /// matching include rather than attempting a duplicate add.
    var existingIncludes: [IncludeEditTarget] = []
    @StateObject private var store = AddIncludeStore()

    @ObservedObject private var marketplaceStore = MarketplaceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader
            content
            footer
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { store.reset() }
    }

    // MARK: header

    private var stepHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.accentColor)
            Text(stepTitle)
                .font(.subheadline.weight(.semibold))
            Spacer()
            stepDots
        }
    }

    private var stepTitle: String {
        switch store.step {
        case .source: return Strings.Harnesses.addIncludeStepSourceTitle
        case .picks: return Strings.Harnesses.addIncludeStepPicksTitle
        case .review: return Strings.Harnesses.addIncludeStepReviewTitle
        case .running: return Strings.Harnesses.addIncludeStepRunningTitle
        }
    }

    private var stepDots: some View {
        HStack(spacing: 4) {
            stepDot(active: store.step == .source, done: doneOrPast(.source))
            stepDot(active: store.step == .picks, done: doneOrPast(.picks))
            stepDot(active: store.step == .review || store.step == .running, done: false)
        }
    }

    private func stepDot(active: Bool, done: Bool) -> some View {
        Circle()
            .fill(done ? Color.green : (active ? Color.accentColor : Color.secondary.opacity(0.3)))
            .frame(width: 8, height: 8)
    }

    private func doneOrPast(_ step: AddIncludeStore.Step) -> Bool {
        let order: [AddIncludeStore.Step] = [.source, .picks, .review, .running]
        guard
            let target = order.firstIndex(of: step),
            let current = order.firstIndex(of: store.step)
        else { return false }
        return current > target
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        switch store.step {
        case .source:
            sourceStep
        case .picks:
            picksStep
        case .review:
            reviewStep
        case .running:
            runningStep
        }
    }

    // MARK: source

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $store.sourceMode) {
                Text(Strings.Harnesses.addIncludeSourceMarketplace)
                    .tag(AddIncludeStore.SourceMode.marketplace)
                Text(Strings.Harnesses.addIncludeSourceGitURL)
                    .tag(AddIncludeStore.SourceMode.gitURL)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch store.sourceMode {
            case .marketplace:
                marketplacePluginPicker
            case .gitURL:
                gitURLForm
            }
        }
    }

    private var marketplacePluginPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                Strings.Harnesses.addIncludeSearchPlaceholder, text: $store.pluginSearch
            )
            .textFieldStyle(.roundedBorder)

            let entries = filteredEntries
            if entries.isEmpty {
                emptyPluginList
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(entries, id: \.plugin.id) { entry in
                            pluginRow(entry: entry)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 240)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var emptyPluginList: some View {
        Text(
            marketplaceStore.marketplaces.isEmpty
                ? Strings.Harnesses.addIncludeNoMarketplaces
                : Strings.Harnesses.addIncludeNoPluginMatches
        )
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
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
        let query = store.pluginSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return allEntries }
        return allEntries.filter {
            $0.plugin.name.lowercased().contains(query)
                || ($0.plugin.description?.lowercased().contains(query) ?? false)
                || $0.marketplace.name.lowercased().contains(query)
        }
    }

    private func pluginRow(entry: PluginEntry) -> some View {
        let isSelected = store.selectedPlugin?.id == entry.plugin.id
        let existingMatch = existingMatch(for: entry)
        let alreadyInstalled = existingMatch != nil
        return Button {
            if let match = existingMatch {
                editor.switchToEditing(match)
            } else {
                store.selectedPlugin = entry.plugin
                store.selectedMarketplace = entry.marketplace
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(
                    systemName: alreadyInstalled
                        ? "pencil.circle"
                        : (isSelected ? "largecircle.fill.circle" : "circle")
                )
                .foregroundColor(alreadyInstalled ? .secondary : (isSelected ? .accentColor : .secondary))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(entry.plugin.name)
                            .font(.system(size: 12, weight: .medium))
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
                    HStack(spacing: 6) {
                        Text(entry.marketplace.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let desc = entry.plugin.description, !desc.isEmpty {
                            Text("·").foregroundColor(.secondary).font(.caption)
                            Text(desc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(alreadyInstalled ? Strings.Harnesses.addIncludeAlreadyInstalledHelp : "")
    }

    /// Returns the existing edit target matching this plugin, if any. The
    /// matching include's ref/picks are what populate the Edit sheet when
    /// the user clicks an already-added row.
    private func existingMatch(for entry: PluginEntry) -> IncludeEditTarget? {
        let resolved = entry.plugin.source.resolved(marketplaceURL: entry.marketplace.url)
        return existingIncludes.first { target in
            IncludeKey(url: target.sourceURL, path: target.path)
                .matches(url: resolved.url, path: resolved.path)
        }
    }

    private var gitURLForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledField(
                label: Strings.Harnesses.addIncludeGitURLLabel,
                text: $store.gitURL,
                placeholder: Strings.Harnesses.addIncludeGitURLPlaceholder
            )
            labeledField(
                label: Strings.Harnesses.addIncludeGitRefLabel,
                text: $store.gitRef,
                placeholder: Strings.Harnesses.addIncludeGitRefPlaceholder
            )
            labeledField(
                label: Strings.Harnesses.addIncludeGitPathLabel,
                text: $store.gitPath,
                placeholder: Strings.Harnesses.addIncludeGitPathPlaceholder
            )
            Text(Strings.Harnesses.addIncludeGitURLHint)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func labeledField(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: picks

    private var picksStep: some View {
        IncludePicksSelector(
            availablePicks: store.resolvedPicks,
            selected: $store.selectedPicks,
            isLoading: store.isLoadingPicks,
            loadError: store.picksLoadError
        )
    }

    // MARK: review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Marketplace.Picker.commandPreview)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(store.commandPreview(harnessName: harnessName))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var runningStep: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(store.applier.outputLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .id(line)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: store.applier.outputLines.count) { _, _ in
                if let last = store.applier.outputLines.last { proxy.scrollTo(last) }
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Button(Strings.Harnesses.installCancel) {
                editor.cancelAddingInclude()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(store.step == .running)
            Spacer()
            if store.step != .source && store.step != .running {
                Button(Strings.Marketplace.Picker.back) { store.goBack() }
            }
            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch store.step {
        case .source:
            Button(Strings.Marketplace.Picker.next) { store.advanceFromSource() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!store.canLeaveSourceStep)
        case .picks:
            Button(Strings.Marketplace.Picker.next) { store.step = .review }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoadingPicks)
        case .review:
            Button(Strings.Harnesses.addIncludeApplyButton) {
                Task {
                    let ok = await store.apply(harnessName: harnessName)
                    if ok {
                        await editor.didFinishAddingInclude(harnessName: harnessName)
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!store.canApply)
        case .running:
            ProgressView().controlSize(.small)
        }
    }
}
