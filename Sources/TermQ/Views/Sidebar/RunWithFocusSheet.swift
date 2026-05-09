import SwiftUI
import TermQCore
import TermQShared

/// Sheet for launching a "Review with Focus" harness run on a PR-linked worktree.
///
/// Presents harness/focus/profile pickers, a prompt textarea (read-only when a
/// focus is selected unless Customize is pressed), and a Run action.
///
/// Invocation rules (§4 of the plan):
/// - Focus selected + no Customize → `ynh run <h> --focus <name>`
/// - Focus selected + Customize pressed → `ynh run <h> [--profile <p>] "<prompt>"`
/// - No focus selected → `ynh run <h> [--profile <p>] "<prompt>"`
struct RunWithFocusSheet: View {
    let context: RunWithFocusContext
    let onLaunch: (HarnessLaunchConfig) -> Void
    let onCancel: () -> Void

    @ObservedObject private var harnessRepository: HarnessRepository = .shared
    @ObservedObject private var ynhPersistence: YNHPersistence = .shared
    @Environment(SettingsStore.self) private var settings

    @State private var selectedHarnessId: String = ""
    @State private var selectedFocus: String = ""
    @State private var selectedProfile: String = ""
    @State private var isCustomizing: Bool = false
    @State private var customPrompt: String = ""
    @State private var detail: HarnessDetail?
    @State private var isLoadingDetail: Bool = false

    private var focuses: [String: ComposedFocus] {
        detail?.composition.focuses ?? [:]
    }

    private var profiles: [String] {
        detail?.composition.profiles ?? []
    }

    /// The profile derived from the selected focus (or empty for harness default).
    private var resolvedProfile: String {
        focuses[selectedFocus]?.profile ?? ""
    }

    /// The prompt text to display — from focus or blank.
    private var focusPrompt: String {
        focuses[selectedFocus]?.prompt ?? ""
    }

    /// The profile to pass to ynh run:
    /// - Focus selected (no customize): N/A — using --focus flag instead
    /// - Focus selected + customize: profile derived from that focus
    /// - No focus (ad-hoc): user's explicit picker choice
    private var effectiveProfile: String {
        selectedFocus.isEmpty ? selectedProfile : resolvedProfile
    }

    /// The harness to launch with.
    private var selectedHarness: Harness? {
        harnessRepository.harnesses.first { $0.id == selectedHarnessId || $0.name == selectedHarnessId }
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
                        selectedFocus = ""
                        selectedProfile = ""
                        isCustomizing = false
                        customPrompt = ""
                        loadDetail(for: newId)
                    }
                }

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
                        // Ad-hoc: user picks freely
                        Picker(Strings.RemotePRs.runProfileLabel, selection: $selectedProfile) {
                            Text(Strings.RemotePRs.runProfileHarnessDefault).tag("")
                            ForEach(profiles, id: \.self) { Text($0).tag($0) }
                        }
                    } else {
                        // Focus selected: profile is derived, read-only
                        Picker(Strings.RemotePRs.runProfileLabel, selection: .constant(resolvedProfile)) {
                            Text(Strings.RemotePRs.runProfileHarnessDefault).tag("")
                            ForEach(profiles, id: \.self) { Text($0).tag($0) }
                        }
                        .disabled(true)
                    }
                }

                // Prompt
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

                    Button(Strings.RemotePRs.runRun) { run() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedHarnessId.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 500)
        .onAppear { applyDefaults() }
    }

    // MARK: - Helpers

    private func applyDefaults() {
        let repoPath = context.repo.path
        // Restore per-repo last-used harness, falling back to worktree then repo default
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

        let savedFocus = ynhPersistence.runFocus(for: repoPath) ?? ""
        selectedFocus = savedFocus

        loadDetail(for: selectedHarnessId)
    }

    private func loadDetail(for harnessId: String) {
        guard !harnessId.isEmpty else { return }
        // Always bypass the session cache — the sheet needs live composition data
        // since the user may have edited the harness's plugin.json since last open.
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

        // Persist per-repo choice
        ynhPersistence.setRunHarness(harness.id, for: context.repo.path)
        if !selectedFocus.isEmpty {
            ynhPersistence.setRunFocus(selectedFocus, for: context.repo.path)
        }

        let config = HarnessLaunchConfig(
            harnessID: harness.id,
            vendorID: "",
            defaultVendor: harness.defaultVendor,
            focus: effectiveFocus,
            profile: effectiveFocus == nil ? (effectiveProfile.isEmpty ? nil : effectiveProfile) : nil,
            workingDirectory: context.worktree.path,
            prompt: effectivePrompt,
            backend: settings.backend,
            branch: context.worktree.branch
        )
        onLaunch(config)
    }
}
