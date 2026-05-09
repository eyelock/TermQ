import SwiftUI
import TermQCore
import TermQShared

/// Sentinel — "use harness default vendor, don't pass -v".
private let defaultVendorTag = "__default__"

/// Sheet for launching a "Run with Focus" harness run on a PR-linked worktree.
///
/// Presents harness/vendor/focus/profile pickers, a prompt textarea (read-only when a
/// focus is selected unless Customize is pressed), an optional --interactive toggle,
/// and a Run action.
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
    @State private var isInteractive: Bool = false
    @State private var detail: HarnessDetail?
    @State private var isLoadingDetail: Bool = false

    private var focuses: [String: ComposedFocus] {
        detail?.composition.focuses ?? [:]
    }

    private var profiles: [String] {
        detail?.composition.profiles ?? []
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
        let lookupID = selectedVendorID == defaultVendorTag
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
                    Text(Strings.RemotePRs.runSheetTitle)
                        .font(.headline)
                    Text("#\(context.prNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
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
                if selectedVendorSupportsInteractive && hasPromptOrFocus {
                    Section {
                        Toggle(Strings.RemotePRs.runInteractiveLabel, isOn: $isInteractive)
                        if isInteractive {
                            Text(Strings.RemotePRs.runInteractiveHelp)
                                .font(.caption)
                                .foregroundColor(.secondary)
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

        selectedFocus = ynhPersistence.runFocus(for: repoPath) ?? ""
        loadDetail(for: selectedHarnessId)
    }

    private func loadDetail(for harnessId: String) {
        guard !harnessId.isEmpty else { return }
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
            let prompt = isCustomizing ? customPrompt : focusPrompt
            if !prompt.isEmpty {
                parts.append("--")
                parts.append("\"…\"")
            }
        }
        if isInteractive {
            parts.append("--interactive")
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
            let promptText = isCustomizing ? customPrompt : focusPrompt
            effectivePrompt = promptText.isEmpty ? nil : promptText
        }

        ynhPersistence.setRunHarness(harness.id, for: context.repo.path)
        if !selectedFocus.isEmpty {
            ynhPersistence.setRunFocus(selectedFocus, for: context.repo.path)
        }

        let config = HarnessLaunchConfig(
            harnessID: harness.id,
            vendorID: effectiveVendorID,
            defaultVendor: harness.defaultVendor,
            focus: effectiveFocus,
            profile: effectiveFocus == nil ? (effectiveProfile.isEmpty ? nil : effectiveProfile) : nil,
            workingDirectory: context.worktree.path,
            prompt: effectivePrompt,
            backend: settings.backend,
            branch: context.worktree.branch,
            interactive: isInteractive
        )
        onLaunch(config)
    }
}
