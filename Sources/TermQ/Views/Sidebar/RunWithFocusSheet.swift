import SwiftUI
import TermQCore
import TermQShared

/// Sentinel — "use harness default vendor, don't pass -v".
private let defaultVendorTag = "__default__"

/// Mode that controls what kind of run this sheet configures.
///
/// - `.interactive` — the original "Run with Focus" flow: a worktree (a
///   PR-linked checkout or a plain local worktree) wants to launch a
///   `ynh run <harness>` session interactively.
/// - `.agent` — the agent-loop flow: an existing agent card wants to launch a
///   `ynh agent run --harness <h> --task <prompt> …` loop. Harness and backend
///   are locked to the card; the sheet still picks focus / profile / prompt.
enum RunSheetMode {
    case interactive(context: RunWithFocusContext)
    case agent(card: TerminalCard)
}

/// What the sheet hands back to its caller. The two cases mirror `RunSheetMode`.
enum RunSheetPayload {
    case interactive(HarnessLaunchConfig)
    /// Agent-loop payload. Mutually exclusive:
    /// - `focus` non-nil → `prompt` is nil; caller passes `--focus <name>`
    ///   (focus carries its own prompt and profile binding inside ynh).
    /// - `focus` nil → `prompt` is the user's task text and `profile` is
    ///   the optional profile override.
    case agent(
        cardId: UUID,
        harness: String,
        focus: String?,
        profile: String?,
        prompt: String?
    )
}

/// Sheet for launching a "Run with Focus" harness run (interactive) or
/// an agent-loop run, depending on `mode`.
///
/// Presents harness/vendor/focus/profile pickers, a prompt textarea (read-only when a
/// focus is selected unless Customize is pressed), an optional --interactive toggle
/// (interactive mode only), and a Run action.
///
/// Invocation rules (interactive — §4 of the plan):
/// - Focus selected + no Customize → `ynh run <h> --focus <name>`
/// - Focus selected + Customize pressed → `ynh run <h> [--profile <p>] "<prompt>"`
/// - No focus selected → `ynh run <h> [--profile <p>] "<prompt>"`
/// - Interactive toggle on → appends `--interactive` (only when vendor supports it)
///
/// Invocation rules (agent):
/// - Always `ynh agent run --harness <h> --task "<prompt>" [--profile <p>]
///   --backend <b>`; --focus is not yet honored by `ynh agent run`, so a focus
///   selection is flattened to its prompt text on our side. Mode/budget flags
///   are added by the AgentSessionController, not the sheet.
struct RunWithFocusSheet: View {
    let mode: RunSheetMode
    let onLaunch: (RunSheetPayload) -> Void
    let onCancel: () -> Void

    private var isAgentMode: Bool {
        if case .agent = mode { return true }
        return false
    }

    /// Card backing the agent mode, or nil for interactive.
    private var agentCard: TerminalCard? {
        if case .agent(let card) = mode { return card }
        return nil
    }

    /// PR context backing the interactive mode, or nil for agent.
    private var interactiveContext: RunWithFocusContext? {
        if case .interactive(let ctx) = mode { return ctx }
        return nil
    }

    private var headerTitle: String {
        switch mode {
        case .interactive: return Strings.RemotePRs.runSheetTitle
        case .agent: return "Run Agent"
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .interactive(let ctx):
            // `#N` for PR-linked runs; the branch (or commit) for plain
            // local worktrees — see #341.
            if let prNumber = ctx.prNumber {
                return "#\(prNumber)"
            }
            return ctx.worktree.branch ?? ctx.worktree.commitHash
        case .agent(let card):
            return card.agentConfig?.harness ?? card.title
        }
    }

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
    @State private var isInteractive: Bool = false
    @State private var detail: HarnessDetail?
    @State private var isLoadingDetail: Bool = false

    // Agent-mode advanced knobs. Seeded from the card's AgentConfig in
    // applyAgentDefaults and written back in runAgent so the card reflects
    // the most recent run.
    @State private var advancedExpanded: Bool = false
    @State private var selectedMode: AgentMode = .plan
    @State private var selectedInteraction: AgentInteractionMode = .confirm
    @State private var maxTurns: Int = AgentBudget.default.maxTurns
    @State private var maxTokens: Int = AgentBudget.default.maxTokens
    @State private var maxWallMinutes: Int =
        max(1, AgentBudget.default.maxWallSeconds / 60)
    @State private var maxPlanIterations: Int = AgentBudget.default.maxPlanIterations

    /// Working directory the agent process runs in. Seeded from the card's
    /// `workingDirectory`; user can override via the directory picker. The
    /// chosen path is written back to the card on Run.
    @State private var agentWorkingDirectory: String = ""

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

    /// Whether the currently selected vendor (or harness default) supports --interactive.
    private var selectedVendorSupportsInteractive: Bool {
        let lookupID =
            selectedVendorID == defaultVendorTag
            ? (selectedHarness?.defaultVendor ?? "")
            : selectedVendorID
        return vendorService.vendors.first { $0.vendorID == lookupID }?.supportsInitialPrompt ?? false
    }

    /// Whether there is something to run interactively (a focus or a prompt).
    private var hasPromptOrFocus: Bool {
        !selectedFocus.isEmpty || !effectivePromptText.isEmpty
    }

    private var effectivePromptText: String {
        isCustomizing ? customPrompt : (selectedFocus.isEmpty ? customPrompt : focusPrompt)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headerTitle)
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
                    .disabled(isAgentMode)
                    .onChange(of: selectedHarnessId) { _, newId in
                        selectedVendorID = defaultVendorTag
                        selectedFocus = ""
                        selectedProfile = ""
                        isCustomizing = false
                        customPrompt = ""
                        isInteractive = false
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
                    .onChange(of: selectedVendorID) { _, _ in
                        // Clear interactive if the new vendor doesn't support it
                        if !selectedVendorSupportsInteractive {
                            isInteractive = false
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

                // Interactive toggle — only when vendor supports it and there's a prompt/focus
                // Hidden in agent mode (an agent run is never interactive in this sense).
                if !isAgentMode && selectedVendorSupportsInteractive && hasPromptOrFocus {
                    Section {
                        Toggle(Strings.RemotePRs.runInteractiveLabel, isOn: $isInteractive)
                        if isInteractive {
                            Text(Strings.RemotePRs.runInteractiveHelp)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Working directory — agent mode only. ynh and its agent
                // operate inside this directory; defaults from the card.
                if isAgentMode {
                    Section {
                        HStack(spacing: 8) {
                            TextField(
                                Strings.Fleet.cwdEmpty,
                                text: $agentWorkingDirectory
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity)
                            Button(Strings.Fleet.cwdChoose) {
                                pickAgentWorkingDirectory()
                            }
                            .controlSize(.small)
                        }
                    } header: {
                        Text(Strings.Fleet.cwdLabel)
                    }
                }

                // Advanced (agent mode only) — Mode / Interaction / Budget,
                // collapsed by default. These mirror the Card Editor's Agent
                // tab so per-run tweaks don't require a round-trip through
                // edit details.
                if isAgentMode {
                    Section {
                        DisclosureGroup(isExpanded: $advancedExpanded) {
                            // Two visually distinct sub-groups, each with a
                            // small caption header so the user can parse the
                            // shape of the disclosure at a glance.
                            VStack(alignment: .leading, spacing: 12) {
                                Text(Strings.Editor.Agent.sectionConfig)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                Picker(
                                    Strings.Editor.Agent.fieldMode,
                                    selection: $selectedMode
                                ) {
                                    ForEach(AgentMode.allCases, id: \.self) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)
                                Picker(
                                    Strings.Editor.Agent.fieldInteraction,
                                    selection: $selectedInteraction
                                ) {
                                    ForEach(AgentInteractionMode.allCases, id: \.self) { interaction in
                                        Text(interaction.rawValue).tag(interaction)
                                    }
                                }
                                .pickerStyle(.menu)

                                Divider().padding(.vertical, 2)

                                Text(Strings.Editor.Agent.sectionBudget)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Stepper(value: $maxTurns, in: 1...500) {
                                    LabeledContent(
                                        Strings.Editor.Agent.fieldMaxTurns,
                                        value: "\(maxTurns)")
                                }
                                Stepper(
                                    value: $maxTokens,
                                    in: 10_000...10_000_000, step: 10_000
                                ) {
                                    LabeledContent(
                                        Strings.Editor.Agent.fieldMaxTokens,
                                        value: "\(maxTokens / 1000)k")
                                }
                                Stepper(value: $maxWallMinutes, in: 1...1440) {
                                    LabeledContent(
                                        Strings.Editor.Agent.fieldMaxWallMinutes,
                                        value: "\(maxWallMinutes) min")
                                }
                                Stepper(value: $maxPlanIterations, in: 1...20) {
                                    LabeledContent(
                                        "Max plan iterations",
                                        value: "\(maxPlanIterations)")
                                }
                            }
                        } label: {
                            Text(Strings.Fleet.runAdvanced)
                                .font(.body.weight(.medium))
                        }
                    }
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

                    Button(Strings.RemotePRs.runRun) { run() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedHarnessId.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 560)
        .onAppear {
            applyDefaults()
            if vendorService.vendors.isEmpty {
                Task { await vendorService.refresh() }
            }
        }
    }

    // MARK: - Helpers

    private func applyDefaults() {
        switch mode {
        case .interactive(let ctx):
            applyInteractiveDefaults(context: ctx)
        case .agent(let card):
            applyAgentDefaults(card: card)
        }
    }

    private func applyInteractiveDefaults(context: RunWithFocusContext) {
        let repoPath = context.repo.path
        let savedHarness =
            ynhPersistence.runHarness(for: repoPath)
            ?? ynhPersistence.harness(for: context.worktree.path)
            ?? ynhPersistence.repoDefaultHarness(for: repoPath)

        if let harnessId = savedHarness,
            harnessRepository.harnesses.contains(where: { $0.id == harnessId || $0.name == harnessId })
        {
            selectedHarnessId = harnessId
        } else if let first = harnessRepository.harnesses.first {
            selectedHarnessId = first.id
        }

        loadDetail(for: selectedHarnessId)

        // Defer focus restore: onChange(of: selectedHarnessId) fires after this returns
        // and unconditionally clears selectedFocus. Scheduling on the next main-actor
        // iteration ensures we restore after the clear.
        let savedFocus = ynhPersistence.runFocus(for: repoPath) ?? ""
        Task { @MainActor in
            selectedFocus = savedFocus
        }
    }

    private func applyAgentDefaults(card: TerminalCard) {
        // Harness and vendor are locked to the card's config in agent mode.
        let harnessId = card.agentConfig?.harness ?? ""
        selectedHarnessId = harnessId
        let backendID = card.agentConfig?.backend.rawValue ?? ""
        selectedVendorID = backendID.isEmpty ? defaultVendorTag : backendID

        // Seed Advanced from the card's current config.
        if let cfg = card.agentConfig {
            selectedMode = cfg.mode
            selectedInteraction = cfg.interactionMode
            maxTurns = cfg.budget.maxTurns
            maxTokens = cfg.budget.maxTokens
            maxWallMinutes = max(1, cfg.budget.maxWallSeconds / 60)
            maxPlanIterations = cfg.budget.maxPlanIterations
        }

        agentWorkingDirectory = card.workingDirectory

        loadDetail(for: selectedHarnessId)
    }

    /// Run a folder-picker NSOpenPanel and assign the chosen path. macOS
    /// app-sandboxed builds get an implicit security-scoped bookmark for
    /// the duration of the run.
    private func pickAgentWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if !agentWorkingDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: agentWorkingDirectory)
        }
        if panel.runModal() == .OK, let url = panel.url {
            agentWorkingDirectory = url.path
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

}

// MARK: - Command preview & launch helpers

extension RunWithFocusSheet {
    func commandPreview() -> String {
        guard let harness = selectedHarness else {
            return isAgentMode ? "ynh agent run …" : "ynh run …"
        }
        if isAgentMode {
            return agentCommandPreview(harness: harness)
        }
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
        if isInteractive {
            parts.append("--interactive")
        }
        return parts.joined(separator: " ")
    }

    private func agentCommandPreview(harness: Harness) -> String {
        // Mirrors runAgent's payload shape and the controller's command build.
        // Budget flags are added by the controller, not the sheet.
        var parts = ["ynh", "agent", "run", "--harness", harness.id]
        if !effectiveVendorID.isEmpty {
            parts.append(contentsOf: ["--backend", effectiveVendorID])
        }
        let useFocusFlag = !selectedFocus.isEmpty && !isCustomizing
        if useFocusFlag {
            parts.append(contentsOf: ["--focus", selectedFocus])
        } else {
            if !effectiveProfile.isEmpty {
                parts.append(contentsOf: ["--profile", effectiveProfile])
            }
            if !effectivePromptText.isEmpty {
                parts.append(contentsOf: ["--task", "\"…\""])
            }
        }
        return parts.joined(separator: " ")
    }

    private func run() {
        guard let harness = selectedHarness else { return }

        switch mode {
        case .interactive(let context):
            runInteractive(harness: harness, context: context)
        case .agent(let card):
            runAgent(harness: harness, card: card)
        }
    }

    private func runInteractive(harness: Harness, context: RunWithFocusContext) {
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

        ynhPersistence.setRunHarness(harness.id, for: context.repo.path)
        if !selectedFocus.isEmpty {
            ynhPersistence.setRunFocus(selectedFocus, for: context.repo.path)
        }

        let instructions: String? = context.prNumber.map {
            "PR #\($0) in \(Self.repoSlug(from: context.repo.path))"
        }

        let config = HarnessLaunchConfig(
            harnessID: harness.id,
            vendorID: effectiveVendorID,
            defaultVendor: harness.defaultVendor,
            focus: effectiveFocus,
            profile: effectiveFocus == nil ? (effectiveProfile.isEmpty ? nil : effectiveProfile) : nil,
            workingDirectory: context.worktree.path,
            prompt: effectivePrompt,
            instructions: instructions,
            backend: settings.backend,
            branch: context.worktree.branch,
            interactive: isInteractive,
            cardTitle: makeCardTitle(focus: effectiveFocus, profile: effectiveProfile, context: context)
        )
        onLaunch(.interactive(config))
    }

    private func runAgent(harness: Harness, card: TerminalCard) {
        // Persist the Advanced knobs back to the card before the controller
        // reads them to build the command line. Backend can change via the
        // vendor picker even when Advanced is collapsed.
        if var cfg = card.agentConfig {
            if let backend = AgentBackend(rawValue: effectiveVendorID) {
                cfg.backend = backend
            }
            cfg.mode = selectedMode
            cfg.interactionMode = selectedInteraction
            cfg.budget = AgentBudget(
                maxTurns: maxTurns,
                maxTokens: maxTokens,
                maxWallSeconds: maxWallMinutes * 60,
                maxPlanIterations: maxPlanIterations
            )
            card.agentConfig = cfg
        }
        // Working directory write-back — the controller reads
        // `card.workingDirectory` when spawning, so this needs to land
        // before `controller.start()` runs.
        if card.workingDirectory != agentWorkingDirectory {
            card.workingDirectory = agentWorkingDirectory
        }

        // Same mutual-exclusion rules `ynh run` and `ynh agent run` enforce:
        //   focus + no Customize → pass --focus <name>; prompt/profile are nil
        //   focus + Customize    → pass --task <custom-text>; focus is nil
        //   no focus             → pass --task <custom-text> + optional --profile
        let useFocusFlag = !selectedFocus.isEmpty && !isCustomizing
        let payloadFocus: String?
        let payloadProfile: String?
        let payloadPrompt: String?

        if useFocusFlag {
            payloadFocus = selectedFocus
            payloadProfile = nil
            payloadPrompt = nil
        } else {
            payloadFocus = nil
            payloadProfile = effectiveProfile.isEmpty ? nil : effectiveProfile
            let promptText = effectivePromptText
            guard !promptText.isEmpty else { return }
            payloadPrompt = promptText
        }

        onLaunch(
            .agent(
                cardId: card.id,
                harness: harness.id,
                focus: payloadFocus,
                profile: payloadProfile,
                prompt: payloadPrompt
            ))
    }

    /// Builds a card title: `focus: org/repo#N` (or `focus: org/repo` without a PR),
    /// truncating the repo slug when long.
    private func makeCardTitle(focus: String?, profile: String, context: RunWithFocusContext) -> String {
        let label: String
        if let focusName = focus, !focusName.isEmpty {
            label = focusName
        } else if !profile.isEmpty {
            label = profile
        } else {
            label = selectedHarness?.id ?? selectedHarnessId
        }
        return Self.buildTitle(label: label, repoPath: context.repo.path, prNumber: context.prNumber)
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
