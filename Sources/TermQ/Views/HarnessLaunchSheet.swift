import SwiftUI
import TermQCore
import TermQShared

/// Sentinel value for the "use harness default vendor" picker option.
/// When selected, `ynh run` omits `-v` so YNH uses the harness's own default.
private let defaultVendorTag = "__default__"

/// Sheet for launching a harness into a terminal Card.
///
/// Presents vendor picker, optional focus, working directory, and prompt.
/// Builds the `ynh run` command and creates a transient Card on confirm.
struct HarnessLaunchSheet: View {
    let harness: Harness
    let detail: HarnessDetail?
    let vendors: [Vendor]
    let initialWorkingDirectory: String?
    let initialBranch: String?
    let onLaunch: (HarnessLaunchConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVendorID: String
    @State private var selectedFocus: String = ""
    @State private var selectedBackend: TerminalBackend = .direct
    @State private var workingDirectory: String
    @State private var prompt: String = ""
    @Environment(SettingsStore.self) private var settings

    init(
        harness: Harness,
        detail: HarnessDetail?,
        vendors: [Vendor],
        initialWorkingDirectory: String?,
        initialBranch: String? = nil,
        initialVendorOverride: String? = nil,
        onLaunch: @escaping (HarnessLaunchConfig) -> Void
    ) {
        self.harness = harness
        self.detail = detail
        self.vendors = vendors
        self.initialWorkingDirectory = initialWorkingDirectory
        self.initialBranch = initialBranch
        self.onLaunch = onLaunch
        self._workingDirectory = State(initialValue: initialWorkingDirectory ?? NSHomeDirectory())
        // Pre-select the user's per-harness vendor override if one is set,
        // otherwise fall back to the harness's manifest default.
        self._selectedVendorID = State(
            initialValue: initialVendorOverride ?? defaultVendorTag)
    }

    /// The effective vendor ID for the command — empty when using the default.
    private var effectiveVendorID: String {
        selectedVendorID == defaultVendorTag ? "" : selectedVendorID
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Harnesses.launchTitle)
                        .font(.headline)
                    Text(harness.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            // Form
            Form {
                // Vendor picker
                Section {
                    Picker(Strings.Harnesses.launchVendor, selection: $selectedVendorID) {
                        // "Default" option — always present when the harness declares one
                        if !harness.defaultVendor.isEmpty {
                            Text(Strings.Harnesses.launchVendorDefault(harness.defaultVendor))
                                .tag(defaultVendorTag)
                        }

                        ForEach(vendors) { vendor in
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

                // Focus picker (only if composition has focuses)
                if let focuses = detail?.composition.focuses, !focuses.isEmpty {
                    Section {
                        Picker(Strings.Harnesses.launchFocus, selection: $selectedFocus) {
                            Text(Strings.Harnesses.launchFocusNone)
                                .tag("")
                            ForEach(focuses.keys.sorted(), id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }

                // Working directory
                Section {
                    HStack {
                        TextField(
                            Strings.Harnesses.launchWorkingDirectory,
                            text: $workingDirectory
                        )
                        .textFieldStyle(.roundedBorder)

                        Button {
                            chooseDirectory()
                        } label: {
                            Text(Strings.Harnesses.launchBrowse)
                        }
                    }
                }

                // Backend mode
                Section {
                    Picker(Strings.Harnesses.launchBackend, selection: $selectedBackend) {
                        ForEach(TerminalBackend.allCases, id: \.self) { backend in
                            Text(localizedBackendName(backend)).tag(backend)
                        }
                    }
                }

                // Prompt
                Section {
                    TextField(
                        Strings.Harnesses.launchPromptPlaceholder,
                        text: $prompt,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                } header: {
                    Text(Strings.Harnesses.launchPrompt)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Command preview + actions
            VStack(spacing: 12) {
                HStack {
                    Text(buildCommand())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                }

                HStack {
                    Button(Strings.Harnesses.launchCancel) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(Strings.Harnesses.launchButton) {
                        let config = HarnessLaunchConfig(
                            harnessID: harness.id,
                            vendorID: effectiveVendorID,
                            defaultVendor: harness.defaultVendor,
                            focus: selectedFocus.isEmpty ? nil : selectedFocus,
                            profile: nil,
                            workingDirectory: workingDirectory,
                            prompt: prompt.isEmpty ? nil : prompt,
                            backend: selectedBackend,
                            branch: initialBranch,
                            interactive: false
                        )
                        onLaunch(config)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 520)
        .onAppear {
            selectedBackend = settings.backend
        }
    }

    // MARK: - Helpers

    private func localizedBackendName(_ backend: TerminalBackend) -> String {
        switch backend {
        case .direct: return Strings.Editor.backendDirect
        case .tmuxAttach: return Strings.Editor.backendTmuxAttach
        case .tmuxControl: return Strings.Editor.backendTmuxControl
        }
    }

    // Intentionally mirrors HarnessLaunchConfig.command — the sheet needs a live
    // preview before HarnessLaunchConfig is created on confirm.
    private func buildCommand() -> String {
        var parts = ["ynh", "run", harness.id]
        if !effectiveVendorID.isEmpty {
            parts.append(contentsOf: ["-v", effectiveVendorID])
        }
        if !selectedFocus.isEmpty {
            parts.append(contentsOf: ["--focus", selectedFocus])
        }
        if !prompt.isEmpty {
            parts.append("--")
            parts.append(prompt)
        }
        return parts.joined(separator: " ")
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectory)
        Task {
            let response = await panel.begin()
            if response == .OK, let url = panel.url {
                workingDirectory = url.path
            }
        }
    }
}

/// Configuration for launching a harness, passed from the sheet to the launcher.
struct HarnessLaunchConfig {
    let harnessID: String
    /// Explicit vendor override. Empty means "use harness default".
    let vendorID: String
    /// The harness's declared default vendor (for tagging).
    let defaultVendor: String
    let focus: String?
    /// Explicit profile override. Mutually exclusive with `focus` (YNH rejects both).
    /// Empty / nil means use the harness default profile.
    let profile: String?
    let workingDirectory: String
    let prompt: String?
    let backend: TerminalBackend
    /// Branch name of the worktree this harness was launched from, if any.
    let branch: String?
    /// When true, passes `--interactive` to `ynh run` so the session stays open
    /// after the LLM responds to the initial prompt.
    let interactive: Bool

    /// Build the `ynh run` command string.
    /// Pass `sessionName` to bind the session to a specific tmux session name.
    func command(sessionName: String? = nil) -> String {
        var parts = ["ynh", "run", harnessID]
        if !vendorID.isEmpty {
            parts.append(contentsOf: ["-v", vendorID])
        }
        if let focus, !focus.isEmpty {
            parts.append(contentsOf: ["--focus", focus])
        } else if let profile, !profile.isEmpty {
            parts.append(contentsOf: ["--profile", profile])
        }
        if interactive {
            parts.append("--interactive")
        }
        if let sessionName {
            parts.append(contentsOf: ["--session-name", sessionName])
        }
        if let prompt, !prompt.isEmpty {
            parts.append("--")
            parts.append(shellQuote(prompt))
        }
        return parts.joined(separator: " ")
    }

    private func shellQuote(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Tags to apply to the created Card (excluding runtime-derived tags added in launchHarness).
    var tags: [(key: String, value: String)] {
        let vendorTag = vendorID.isEmpty ? defaultVendor : vendorID
        var result: [(key: String, value: String)] = [
            ("source", "harness"),
            ("harness", harnessID),
        ]
        if !vendorTag.isEmpty {
            result.append(("vendor", vendorTag))
        }
        if let focus, !focus.isEmpty {
            result.append(("focus", focus))
        }
        if let branch, !branch.isEmpty {
            result.append(("branch", branch))
        }
        return result
    }
}
