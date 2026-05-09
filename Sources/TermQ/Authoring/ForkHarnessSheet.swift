import AppKit
import SwiftUI
import TermQShared

/// Sheet for forking a registry harness to a local editable copy.
///
/// Runs `ynh fork <source-id> --to <destination> [--name <new-name>] --format json`.
/// Self-registers via the pointer model — writes `~/.ynh/installed/<name>.json`
/// and generates the launcher so no follow-up `ynh install` is needed. On
/// success calls `onForkCompleted` with the new fork's canonical id.
///
/// Note: YNH currently exposes `--name <new-name>` for renaming the fork on
/// disk, but does not yet accept a full `--as <canonical-id>` flag. The
/// new fork's canonical id is assigned by YNH (typically `local/<name>`).
struct ForkHarnessSheet: View {
    let harness: Harness
    @ObservedObject var detector: YNHDetector
    @ObservedObject var repository: HarnessRepository
    let onForkCompleted: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var authorPreferences = HarnessAuthorPreferences.shared

    @State private var destination = ""
    /// Optional new name for the fork (passed as `--name <new-name>`). Empty
    /// keeps the source's name. The canonical id will be `local/<name>`.
    @State private var renameTo = ""
    @State private var phase: Phase = .form
    @State private var errorMessage: String?
    @StateObject private var runnerState = CommandSheetState()

    private enum Phase { case form, running, succeeded, failed }

    private var ynhPath: String? {
        if case .ready(let path, _, _) = detector.status { return path }
        return nil
    }
    private var ynhEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride { env["YNH_HOME"] = override }
        return env
    }
    private var trimmedDest: String { destination.trimmingCharacters(in: .whitespaces) }
    private var trimmedRename: String { renameTo.trimmingCharacters(in: .whitespaces) }

    /// Validation: when a rename is provided, it must not collide with any
    /// existing local harness's name. Empty rename is valid (keeps source
    /// name). Returns nil when valid.
    private var renameValidationMessage: String? {
        guard !trimmedRename.isEmpty else { return nil }
        let candidateID = "local/\(trimmedRename)"
        if repository.harnesses.contains(where: { $0.id == candidateID }) {
            return Strings.HarnessFork.identityCollision
        }
        return nil
    }

    var body: some View {
        // Frame is applied at the `.sheet` content closure in ContentView, not
        // here, so NSWindow sees a definitive size at first paint regardless
        // of which phase is active.
        VStack(spacing: 0) {
            switch phase {
            case .form:
                sheetHeader
                Divider()
                formView
            case .running, .succeeded, .failed:
                runnerPhaseView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadDefaultDestination() }
    }

    @ViewBuilder
    private var runnerPhaseView: some View {
        CommandRunnerSheet(
            title: Strings.HarnessFork.progressTitle(harness.name),
            state: runnerState,
            onRerun: phase == .failed ? { Task { await runFork() } } : nil,
            onDismiss: {
                if phase == .succeeded {
                    dismiss()
                } else {
                    phase = .form
                }
            }
        )
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            Text(Strings.HarnessFork.title(harness.name))
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Form

    private var formView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Text(Strings.HarnessFork.explanation)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Section {
                    HStack {
                        TextField("/path/to/harnesses", text: $destination)
                            .textFieldStyle(.roundedBorder)
                        Button(Strings.Common.browse) { browseDestination() }
                    }
                } header: {
                    Text(Strings.HarnessWizard.destinationLabel)
                }

                Section {
                    TextField(harness.name, text: $renameTo)
                        .textFieldStyle(.roundedBorder)
                    if let msg = renameValidationMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text(Strings.HarnessFork.renameLabel)
                } footer: {
                    Text(Strings.HarnessFork.renameHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(height: 320)

            if let err = errorMessage {
                Text(err)
                    .font(.caption).foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Divider()

            HStack {
                Spacer()
                Button(Strings.Common.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(Strings.HarnessFork.forkButton) {
                    Task { await runFork() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedDest.isEmpty || renameValidationMessage != nil)
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func browseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = Strings.Common.select
        if !trimmedDest.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: trimmedDest)
        }
        if panel.runModal() == .OK, let url = panel.url {
            destination = url.path
        }
    }

    private func loadDefaultDestination() {
        if !authorPreferences.defaultDirectory.isEmpty {
            destination = authorPreferences.defaultDirectory
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            destination = docs?.path ?? NSHomeDirectory()
        }
    }

    private func runFork() async {
        guard let ynhBin = ynhPath else { return }
        guard renameValidationMessage == nil else { return }
        errorMessage = nil
        phase = .running
        runnerState.begin()

        let forkName = trimmedRename.isEmpty ? harness.name : trimmedRename
        let destPath = (trimmedDest as NSString).appendingPathComponent(forkName)

        // Single-call flow: `ynh fork --to <path> [--name <new>]` self-registers
        // via the pointer model — writes ~/.ynh/installed/<name>.json,
        // generates the launcher. No follow-up `ynh install` needed.
        var args = ["fork", harness.id, "--to", destPath]
        if !trimmedRename.isEmpty {
            args += ["--name", trimmedRename]
        }
        args += ["--format", "json"]

        do {
            let result = try await CommandRunner.run(
                executable: ynhBin,
                arguments: args,
                environment: ynhEnvironment,
                onStdoutLine: { line in Task { @MainActor in runnerState.append(line: line) } },
                onStderrLine: { line in Task { @MainActor in runnerState.append(line: line) } }
            )
            runnerState.finish(result: result)

            if result.didSucceed {
                phase = .succeeded
                await repository.refresh()
                // Match the new fork by its on-disk path — unique and
                // independent of how YNH stamps the canonical id. Falls
                // back to the conventional `local/<name>` form if the
                // refresh somehow missed the new entry.
                let resolvedID =
                    repository.harnesses
                    .first { $0.path == destPath }?.id
                    ?? "local/\(forkName)"
                onForkCompleted(resolvedID)
            } else {
                phase = .failed
            }
        } catch {
            runnerState.append(line: error.localizedDescription)
            runnerState.finish(
                result: CommandRunner.Result(
                    exitCode: 1, stdout: "", stderr: error.localizedDescription, duration: 0))
            phase = .failed
        }
    }
}
