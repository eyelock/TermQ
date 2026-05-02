import AppKit
import SwiftUI
import TermQShared

/// Sheet for forking a registry harness to a local editable copy.
///
/// Runs `ynh fork <name> --to <destination> --format json` followed by
/// `ynh install <destination>`. On success calls `onForkCompleted` with the
/// new harness name so the caller can navigate to it.
struct ForkHarnessSheet: View {
    let harness: Harness
    @ObservedObject var detector: YNHDetector
    @ObservedObject var repository: HarnessRepository
    let onForkCompleted: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("defaultHarnessAuthorDirectory") private var defaultHarnessAuthorDirectory = ""

    @State private var destination = ""
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
            }
            .formStyle(.grouped)
            .frame(height: 220)

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
                .disabled(trimmedDest.isEmpty)
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
        if !defaultHarnessAuthorDirectory.isEmpty {
            destination = defaultHarnessAuthorDirectory
            return
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        destination = docs?.path ?? NSHomeDirectory()
    }

    private func runFork() async {
        guard let ynhBin = ynhPath else { return }
        errorMessage = nil
        phase = .running
        runnerState.begin()

        let destPath = (trimmedDest as NSString).appendingPathComponent(harness.name)

        // Single-call flow: `ynh fork --to <path>` self-registers via the
        // pointer model (writes ~/.ynh/installed/<name>.json, generates
        // launcher) so no follow-up `ynh install` is needed. Edits in the
        // fork tree are live to `ynh run` because the loader resolves the
        // pointer back to <path>.
        do {
            let result = try await CommandRunner.run(
                executable: ynhBin,
                arguments: ["fork", harness.name, "--to", destPath, "--format", "json"],
                environment: ynhEnvironment,
                onStdoutLine: { line in Task { @MainActor in runnerState.append(line: line) } },
                onStderrLine: { line in Task { @MainActor in runnerState.append(line: line) } }
            )
            runnerState.finish(result: result)

            if result.didSucceed {
                phase = .succeeded
                await repository.refresh()
                onForkCompleted(harness.name)
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
