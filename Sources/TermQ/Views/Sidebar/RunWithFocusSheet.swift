import AppKit
import SwiftUI
import TermQCore
import TermQShared

/// Sentinel — "use harness default vendor, don't pass -v".
private let defaultVendorTag = "__default__"

/// The launch sheet: the one dialog every "Launch …" menu item opens, for a
/// worktree, a PR, a terminal card, a harness or a Wheelhouse seat.
///
/// Presents harness/vendor/focus/profile pickers, then (where the context
/// allows) the folder, backend and resume choices, a "Stay interactive"
/// toggle (on by default, above the prompt so it isn't missed), a prompt
/// textarea (read-only when a focus is selected unless Customize is pressed)
/// and a Launch action.
///
/// Invocation rules (§4 of the plan):
/// - Focus selected + no Customize → `ynh run <h> --focus <name>`
/// - Focus selected + Customize pressed → `ynh run <h> [--profile <p>] "<prompt>"`
/// - No focus selected → `ynh run <h> [--profile <p>] "<prompt>"`
/// - Interactive toggle on → appends `--interactive` (only when vendor supports it)
struct RunWithFocusSheet: View {
    let context: RunWithFocusContext
    let onLaunch: (HarnessLaunchConfig) -> Void
    let onCancel: () -> Void

    @ObservedObject private var harnessRepository: HarnessRepository = .shared
    @ObservedObject private var ynhPersistence: YNHPersistence = .shared
    @ObservedObject private var vendorService: VendorService = .shared
    @Environment(SettingsStore.self) private var settings

    @State private var selectedHarnessId: String = ""
    @State private var selectedVendorID: String = defaultVendorTag
    @State private var selectedFocus: String = ""
    @State private var selectedProfile: String = ""
    @State private var isCustomizing: Bool = false
    @State private var customPrompt: String = ""
    /// On by default: a focus run that exits when done is the exception.
    @State private var isInteractive: Bool = true
    @State private var workingDirectory: String = ""
    @State private var selectedBackend: TerminalBackend = .direct
    @State private var resumeSession: Bool = false
    /// The context's vendor, held until the first harness is chosen.
    @State private var initialVendor = OneShot<String>()
    @State private var detail: HarnessDetail?
    @State private var isLoadingDetail: Bool = false

    private var focuses: [String: ComposedFocus] {
        detail?.composition.focuses ?? [:]
    }

    private var profiles: [String] {
        detail.map { Array($0.composition.profiles.keys).sorted() } ?? []
    }

    private var resolvedProfile: String {
        focuses[selectedFocus]?.profile ?? ""
    }

    private var focusPrompt: String {
        focuses[selectedFocus]?.prompt ?? ""
    }

    private var effectiveProfile: String {
        selectedFocus.isEmpty ? selectedProfile : resolvedProfile
    }

    private var selectedHarness: Harness? {
        harnessRepository.harnesses.first { $0.id == selectedHarnessId || $0.name == selectedHarnessId }
    }

    /// The vendor ID to pass via `-v` (empty = use harness default).
    private var effectiveVendorID: String {
        selectedVendorID == defaultVendorTag ? "" : selectedVendorID
    }

    /// Whether the vendor the launch will use supports `feature`. With no
    /// vendor picked and none declared by the harness, ynh falls back to its
    /// own default, which TermQ can't see; the feature is offered then only
    /// when every known vendor supports it.
    private func effectiveVendorSupports(_ feature: KeyPath<Vendor, Bool>) -> Bool {
        let lookupID =
            selectedVendorID == defaultVendorTag
            ? (selectedHarness?.defaultVendor ?? "")
            : selectedVendorID
        return Self.vendor(lookupID, among: vendorService.vendors, supports: feature)
    }

    /// `vendorID` empty means ynh picks the vendor itself: offered only when
    /// every known vendor supports `feature` (and none when nothing is known).
    static func vendor(_ vendorID: String, among vendors: [Vendor], supports feature: KeyPath<Vendor, Bool>) -> Bool {
        if vendorID.isEmpty {
            return !vendors.isEmpty && vendors.allSatisfy { $0[keyPath: feature] }
        }
        return vendors.first { $0.vendorID == vendorID }?[keyPath: feature] ?? false
    }

    /// Whether the effective vendor supports --interactive.
    private var selectedVendorSupportsInteractive: Bool { effectiveVendorSupports(\.supportsInitialPrompt) }

    /// Whether the launch can continue a previous session: the context
    /// allows it and the effective vendor's CLI can.
    private var showsResume: Bool { context.offersResume && effectiveVendorSupports(\.supportsResume) }

    /// The toggle shows whenever the vendor supports `--interactive`, so it is
    /// seen before a focus or prompt is chosen; it is only passed once there
    /// is a focus or prompt to respond to.
    private var showsInteractive: Bool { selectedVendorSupportsInteractive }
    private var effectiveInteractive: Bool { showsInteractive && hasPromptOrFocus && isInteractive }

    /// Whether there is something to run interactively (a focus or a prompt).
    private var hasPromptOrFocus: Bool {
        !selectedFocus.isEmpty || !effectivePromptText.isEmpty
    }

    private var effectivePromptText: String {
        isCustomizing ? customPrompt : (selectedFocus.isEmpty ? customPrompt : focusPrompt)
    }

    /// The seat; `#N` for PR-linked runs; the branch (or commit) for plain
    /// local worktrees; else the harness.
    private var headerSubtitle: String {
        if let seat = context.seat { return seat.seat.name }
        if let prNumber = context.prNumber {
            return "#\(prNumber)"
        }
        return context.branch ?? context.commitHash ?? selectedHarness?.name ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Harnesses.launchTitle)
                        .font(.headline)
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    loadDetail(for: selectedHarnessId, force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .disabled(isLoadingDetail)
                .help(Strings.RemotePRs.runRefreshDetail)
            }
            .padding()

            Divider()

            Form {
                // Harness picker
                Section {
                    Picker(Strings.RemotePRs.runHarnessLabel, selection: $selectedHarnessId) {
                        ForEach(harnessRepository.harnesses) { harness in
                            Text(harness.name).tag(harness.id)
                        }
                    }
                    // A seat's harness is the seat.
                    .disabled(context.fixesHarness)
                    .onChange(of: selectedHarnessId) { _, newId in
                        // The context's vendor applies to the harness it opened
                        // with; picking another harness goes back to its default.
                        selectedVendorID = initialVendor.take() ?? defaultVendorTag
                        selectedFocus = ""
                        selectedProfile = ""
                        isCustomizing = false
                        customPrompt = ""
                        isInteractive = true
                        loadDetail(for: newId)
                    }

                    // Vendor picker — always visible so the user can override the default
                    Picker(Strings.RemotePRs.runVendorLabel, selection: $selectedVendorID) {
                        if let harness = selectedHarness, !harness.defaultVendor.isEmpty {
                            Text(Strings.Harnesses.launchVendorDefault(harness.defaultVendor))
                                .tag(defaultVendorTag)
                        } else {
                            Text(Strings.RemotePRs.runVendorDefault).tag(defaultVendorTag)
                        }
                        ForEach(vendorService.vendors) { vendor in
                            HStack {
                                Text(vendor.displayName)
                                if !vendor.available {
                                    Text(Strings.Harnesses.launchVendorUnavailable)
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            .tag(vendor.vendorID)
                        }
                    }
                }

                if isLoadingDetail {
                    Section {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(Strings.RemotePRs.runLoadingDetail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    // Focus picker (only if harness has focuses)
                    if !focuses.isEmpty {
                        Section {
                            Picker(Strings.RemotePRs.runFocusLabel, selection: $selectedFocus) {
                                Text(Strings.RemotePRs.runFocusNone).tag("")
                                ForEach(focuses.keys.sorted(), id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .onChange(of: selectedFocus) { _, _ in
                                isCustomizing = false
                                customPrompt = ""
                            }
                        }
                    }

                    // Profile — interactive in ad-hoc mode; locked (derived) when focus is set
                    Section {
                        if selectedFocus.isEmpty {
                            Picker(Strings.RemotePRs.runProfileLabel, selection: $selectedProfile) {
                                Text(Strings.RemotePRs.runProfileHarnessDefault).tag("")
                                ForEach(profiles, id: \.self) { Text($0).tag($0) }
                            }
                        } else {
                            Picker(Strings.RemotePRs.runProfileLabel, selection: .constant(resolvedProfile)) {
                                Text(Strings.RemotePRs.runProfileHarnessDefault).tag("")
                                ForEach(profiles, id: \.self) { Text($0).tag($0) }
                            }
                            .disabled(true)
                        }
                    }
                }

                launchPlaceSections

                // Stay interactive — above the prompt, where it is seen.
                if showsInteractive {
                    Section {
                        Toggle(Strings.RemotePRs.runInteractiveLabel, isOn: $isInteractive)
                            .help(Strings.RemotePRs.runInteractiveHelp)
                    }
                }

                // Prompt + customize
                Section {
                    HStack(alignment: .top) {
                        Group {
                            if isCustomizing || selectedFocus.isEmpty {
                                TextEditor(text: $customPrompt)
                                    .font(.body)
                                    .frame(minHeight: 80)
                            } else {
                                Text(focusPrompt.isEmpty ? " " : focusPrompt)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                            }
                        }
                        if !selectedFocus.isEmpty {
                            Button(Strings.RemotePRs.runCustomize) {
                                if !isCustomizing {
                                    customPrompt = focusPrompt
                                }
                                isCustomizing.toggle()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                } header: {
                    Text(Strings.RemotePRs.runPromptLabel)
                }

            }
            .formStyle(.grouped)

            Divider()

            // Command preview + actions
            VStack(spacing: 12) {
                HStack {
                    Text(commandPreview())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                }

                HStack {
                    Button(Strings.RemotePRs.runCancel) { onCancel() }
                        .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(Strings.Harnesses.launchButton) { run() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedHarnessId.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 520, height: 600)
        .onAppear {
            applyDefaults()
            if vendorService.vendors.isEmpty {
                Task { await vendorService.refresh() }
            }
        }
    }

    /// Where the new terminal runs, for contexts that let it be chosen.
    @ViewBuilder
    private var launchPlaceSections: some View {
        if context.choosesDirectory {
            Section {
                LabeledContent(Strings.Harnesses.launchWorkingDirectory) {
                    HStack {
                        TextField("", text: $workingDirectory)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .truncationMode(.head)
                        Button(Strings.Harnesses.launchBrowse) { chooseDirectory() }
                    }
                    .frame(minWidth: 280)
                }
            }
        }
        if context.choosesBackend {
            Section {
                Picker(Strings.Harnesses.launchBackend, selection: $selectedBackend) {
                    ForEach(TerminalBackend.allCases, id: \.self) { backend in
                        Text(Self.backendName(backend)).tag(backend)
                    }
                }
            }
        }
        if showsResume {
            Section {
                Toggle(Strings.Harnesses.launchResume, isOn: $resumeSession)
                    .help(Strings.Harnesses.launchResumeHelp)
            }
        }
    }

    private static func backendName(_ backend: TerminalBackend) -> String {
        switch backend {
        case .direct: return Strings.Editor.backendDirect
        case .tmuxAttach: return Strings.Editor.backendTmuxAttach
        case .tmuxControl: return Strings.Editor.backendTmuxControl
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectory)
        Task {
            if await panel.begin() == .OK, let url = panel.url {
                workingDirectory = url.path
            }
        }
    }

    // MARK: - Helpers

    private func applyDefaults() {
        workingDirectory = context.workingDirectory
        selectedBackend = settings.backend
        if let vendor = context.vendorOverride { initialVendor.set(vendor) }
        // Card-origin launches preselect the card's effective harness; both
        // origins then fall back to saved run-harness / worktree / repo default.
        let savedHarness =
            context.preferredHarnessId
            ?? context.repoPath.flatMap { ynhPersistence.runHarness(for: $0) }
            ?? ynhPersistence.harness(for: context.workingDirectory)
            ?? context.repoPath.flatMap { ynhPersistence.repoDefaultHarness(for: $0) }

        if let harnessId = savedHarness,
            harnessRepository.harnesses.contains(where: { $0.id == harnessId || $0.name == harnessId })
        {
            selectedHarnessId = harnessId
        } else if !context.fixesHarness, let first = harnessRepository.harnesses.first {
            // A seat's harness is fixed: never stand another in for it. With
            // none chosen, Launch stays disabled.
            selectedHarnessId = first.id
        }

        loadDetail(for: selectedHarnessId)

        // Defer focus restore: onChange(of: selectedHarnessId) fires after this returns
        // and unconditionally clears selectedFocus. Scheduling on the next main-actor
        // iteration ensures we restore after the clear.
        let savedFocus = context.repoPath.flatMap { ynhPersistence.runFocus(for: $0) } ?? ""
        Task { @MainActor in
            selectedFocus = savedFocus
        }
    }

    private func loadDetail(for harnessId: String, force: Bool = false) {
        guard !harnessId.isEmpty else { return }
        if !force, let cached = harnessRepository.cachedDetail(for: harnessId) {
            detail = cached
            return
        }
        harnessRepository.invalidateDetail(for: harnessId)
        isLoadingDetail = true
        Task {
            await harnessRepository.fetchDetail(for: harnessId)
            detail = harnessRepository.selectedDetail
            isLoadingDetail = false
        }
    }

    private func commandPreview() -> String {
        guard let harness = selectedHarness else { return "ynh run …" }
        var parts = ["ynh", "run", harness.id]
        if !effectiveVendorID.isEmpty {
            parts.append(contentsOf: ["-v", effectiveVendorID])
        }
        if !selectedFocus.isEmpty && !isCustomizing {
            parts.append(contentsOf: ["--focus", selectedFocus])
        } else {
            if !effectiveProfile.isEmpty {
                parts.append(contentsOf: ["--profile", effectiveProfile])
            }
            if !effectivePromptText.isEmpty {
                parts.append("--")
                parts.append("\"…\"")
            }
        }
        if effectiveInteractive {
            parts.append("--interactive")
        }
        if showsResume && resumeSession {
            parts.append("--resume")
        }
        return parts.joined(separator: " ")
    }

    private func run() {
        guard let harness = selectedHarness else { return }

        let useFocusFlag = !selectedFocus.isEmpty && !isCustomizing
        let effectivePrompt: String?
        let effectiveFocus: String?

        if useFocusFlag {
            effectiveFocus = selectedFocus
            effectivePrompt = nil
        } else {
            effectiveFocus = nil
            effectivePrompt = effectivePromptText.isEmpty ? nil : effectivePromptText
        }

        // Persist run-harness / focus only when the launch resolves to a repo.
        if let repoPath = context.repoPath {
            ynhPersistence.setRunHarness(harness.id, for: repoPath)
            if !selectedFocus.isEmpty {
                ynhPersistence.setRunFocus(selectedFocus, for: repoPath)
            }
        }

        let instructions: String? = context.prNumber.map {
            "PR #\($0) in \(Self.repoSlug(from: context.repoPath ?? context.workingDirectory))"
        }

        var config = HarnessLaunchConfig(
            harnessID: harness.id,
            vendorID: effectiveVendorID,
            defaultVendor: harness.defaultVendor,
            focus: effectiveFocus,
            profile: effectiveFocus == nil ? (effectiveProfile.isEmpty ? nil : effectiveProfile) : nil,
            workingDirectory: workingDirectory.isEmpty ? context.workingDirectory : workingDirectory,
            prompt: effectivePrompt,
            instructions: instructions,
            backend: context.choosesBackend ? selectedBackend : settings.backend,
            branch: context.branch,
            interactive: effectiveInteractive,
            cardTitle: cardTitle(focus: effectiveFocus, profile: effectiveProfile),
            resumeSession: showsResume && resumeSession
        )
        if let seat = context.seat {
            config.extraTags = WheelhouseCardMatcher.tags(
                wheelhouseRoot: seat.wheelhouse.root, seatCommand: seat.seat.command)
        }
        onLaunch(config)
    }

    /// A seat's card is named for the seat; a harness launched from anywhere
    /// keeps the launcher's default title (its branch or harness); the rest
    /// get `focus: org/repo#N`.
    private func cardTitle(focus: String?, profile: String) -> String? {
        if let seat = context.seat { return seat.seat.name }
        if context.choosesDirectory { return nil }
        return makeCardTitle(focus: focus, profile: profile)
    }

    /// Builds a card title: `focus: org/repo#N` (or `focus: org/repo` without a PR),
    /// truncating the repo slug when long.
    private func makeCardTitle(focus: String?, profile: String) -> String {
        let label: String
        if let focusName = focus, !focusName.isEmpty {
            label = focusName
        } else if !profile.isEmpty {
            label = profile
        } else {
            label = selectedHarness?.id ?? selectedHarnessId
        }
        return Self.buildTitle(
            label: label, repoPath: context.repoPath ?? context.workingDirectory, prNumber: context.prNumber)
    }

    /// Static entry point for building a card title outside the sheet (e.g. quick-launch).
    static func makeCardTitleStatic(
        focus: String?, profile: String, harnessId: String, repoPath: String, prNumber: Int?
    ) -> String {
        let label: String
        if let focusName = focus, !focusName.isEmpty {
            label = focusName
        } else if !profile.isEmpty {
            label = profile
        } else {
            label = harnessId
        }
        return buildTitle(label: label, repoPath: repoPath, prNumber: prNumber)
    }

    private static func buildTitle(label: String, repoPath: String, prNumber: Int?) -> String {
        let slug = repoSlug(from: repoPath)
        let prSuffix = prNumber.map { "#\($0)" } ?? ""
        let repoAndPR = "\(slug)\(prSuffix)"
        let budget = 40 - label.count - 2
        let truncated =
            budget > prSuffix.count + 1
            ? truncateMiddle(repoAndPR, to: budget)
            : (prSuffix.isEmpty ? "…" : prSuffix)
        return "\(label): \(truncated)"
    }

    /// Extracts `org/repo` from a filesystem path (last two path components).
    static func repoSlug(from path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else { return components.last.map(String.init) ?? path }
        return "\(components[components.count - 2])/\(components[components.count - 1])"
    }

    /// Truncates `str` to `max` chars, replacing the middle with `…`.
    private static func truncateMiddle(_ str: String, to max: Int) -> String {
        guard str.count > max else { return str }
        guard max > 1 else { return "…" }
        let half = (max - 1) / 2
        let head = str.prefix(half)
        let tail = str.suffix(max - 1 - half)
        return "\(head)…\(tail)"
    }
}

/// A value read once: `take()` returns it the first time and nil after.
/// A class, so taking it inside a view's onChange doesn't need a state write.
private final class OneShot<Value> {
    private var value: Value?
    func set(_ newValue: Value) { value = newValue }
    func take() -> Value? {
        defer { value = nil }
        return value
    }
}
