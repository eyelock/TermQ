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
    let onLaunch: (HarnessLaunchConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVendorID: String = defaultVendorTag
    @State private var selectedFocus: String = ""
    @State private var selectedBackend: TerminalBackend = .direct
    @State private var workingDirectory: String = NSHomeDirectory()
    @State private var prompt: String = ""
    @AppStorage("defaultBackend") private var defaultBackendRaw: String = "direct"

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
                            harnessName: harness.name,
                            vendorID: effectiveVendorID,
                            defaultVendor: harness.defaultVendor,
                            focus: selectedFocus.isEmpty ? nil : selectedFocus,
                            workingDirectory: workingDirectory,
                            prompt: prompt.isEmpty ? nil : prompt,
                            backend: selectedBackend
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
            selectedBackend = TerminalBackend(rawValue: defaultBackendRaw) ?? .direct
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
        var parts = ["ynh", "run", harness.name]
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
    let harnessName: String
    /// Explicit vendor override. Empty means "use harness default".
    let vendorID: String
    /// The harness's declared default vendor (for tagging).
    let defaultVendor: String
    let focus: String?
    let workingDirectory: String
    let prompt: String?
    let backend: TerminalBackend

    /// Build the `ynh run` command string.
    var command: String {
        var parts = ["ynh", "run", harnessName]
        if !vendorID.isEmpty {
            parts.append(contentsOf: ["-v", vendorID])
        }
        if let focus, !focus.isEmpty {
            parts.append(contentsOf: ["--focus", focus])
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

    /// Tags to apply to the created Card.
    var tags: [(key: String, value: String)] {
        let vendorTag = vendorID.isEmpty ? defaultVendor : vendorID
        var result: [(key: String, value: String)] = [
            ("harness", harnessName)
        ]
        if !vendorTag.isEmpty {
            result.append(("vendor", vendorTag))
        }
        if let focus, !focus.isEmpty {
            result.append(("focus", focus))
        }
        return result
    }
}
