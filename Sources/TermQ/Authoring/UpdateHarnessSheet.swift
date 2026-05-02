import SwiftUI
import TermQShared

/// Sheet for updating an installed harness.
///
/// Runs `ynh update <name>` via `CommandRunner` and surfaces progress through a
/// `CommandRunnerSheet`. On success the repository is refreshed so version and
/// update-availability state propagate immediately. No transient terminal is
/// spawned.
///
/// When the harness has unversioned upstream drift (content changed without a
/// `version` bump — a potential supply-chain warning signal) the sheet inserts
/// a confirm step that lists which include SHAs are about to move, before
/// running. Versioned bumps (or harnesses with no drift signal at all) skip
/// the confirm step and run immediately.
struct UpdateHarnessSheet: View {
    let harnessName: String
    @ObservedObject var detector: YNHDetector
    @ObservedObject var repository: HarnessRepository
    var availabilityService: any UpdateAvailabilityService = LiveUpdateAvailabilityService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase
    @StateObject private var runnerState = CommandSheetState()
    private let initialDriftedIncludes: [HarnessUpdateSignal.DriftedInclude]

    init(
        harnessName: String,
        detector: YNHDetector,
        repository: HarnessRepository,
        availabilityService: any UpdateAvailabilityService = LiveUpdateAvailabilityService.shared
    ) {
        self.harnessName = harnessName
        self.detector = detector
        self.repository = repository
        self.availabilityService = availabilityService

        // Resolve initial signal at sheet open: if it's unversioned drift,
        // start in the confirm phase. Otherwise run immediately.
        if let snapshot = availabilityService.snapshot(forHarness: harnessName) {
            let store = HarnessUpdateBadgeStore(service: availabilityService)
            switch store.signal(for: snapshot) {
            case .unversionedDrift(let drifted):
                self._phase = State(initialValue: .confirm)
                self.initialDriftedIncludes = drifted
            case .versioned, .none:
                self._phase = State(initialValue: .running)
                self.initialDriftedIncludes = []
            }
        } else {
            self._phase = State(initialValue: .running)
            self.initialDriftedIncludes = []
        }
    }

    private enum Phase { case confirm, running, succeeded, failed }

    private var ynhPath: String? {
        if case .ready(let path, _, _) = detector.status { return path }
        return nil
    }
    private var ynhEnvironment: [String: String] {
        var environ = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride { environ["YNH_HOME"] = override }
        return environ
    }

    var body: some View {
        // Frame on the outermost view (not inside switch branches) so NSWindow
        // has a stable intrinsic size from first paint. Branch-local frames
        // cause a first-paint race where the window briefly renders as a
        // small placeholder until the layout pass picks a branch.
        VStack(spacing: 0) {
            switch phase {
            case .confirm:
                confirmView
            case .running, .succeeded, .failed:
                CommandRunnerSheet(
                    title: Strings.HarnessUpdate.title(harnessName),
                    state: runnerState,
                    onRerun: phase == .failed ? { Task { await runUpdate() } } : nil,
                    onDismiss: { dismiss() }
                )
                .onAppear {
                    // Only auto-fire begin/runUpdate when the user didn't go
                    // through the confirm step (i.e. we started in .running).
                    if runnerState.outputLines.isEmpty {
                        runnerState.begin()
                    }
                }
                .task {
                    if runnerState.outputLines.isEmpty && phase == .running {
                        await runUpdate()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Confirm step (unversioned drift)

    private var confirmView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(Strings.Harnesses.unversionedDriftConfirmTitle)
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

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Strings.Harnesses.unversionedDriftConfirmBody)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(initialDriftedIncludes, id: \.path) { drift in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(drift.path)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.semibold)
                                HStack(spacing: 4) {
                                    Text(drift.installedSHA.prefix(12))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(drift.availableSHA.prefix(12))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .padding()
            }
            .frame(maxHeight: 280)

            Divider()

            HStack {
                Spacer()
                Button(Strings.Common.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(Strings.Harnesses.unversionedDriftProceed) {
                    phase = .running
                    runnerState.begin()
                    Task { await runUpdate() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    // MARK: - Run

    private func runUpdate() async {
        guard let ynhBin = ynhPath else {
            runnerState.append(line: Strings.HarnessUpdate.ynhUnavailable)
            runnerState.finish(
                result: CommandRunner.Result(
                    exitCode: 1, stdout: "", stderr: Strings.HarnessUpdate.ynhUnavailable,
                    duration: 0))
            phase = .failed
            return
        }

        phase = .running

        do {
            let result = try await CommandRunner.run(
                executable: ynhBin,
                arguments: ["update", harnessName],
                environment: ynhEnvironment,
                onStdoutLine: { line in Task { @MainActor in runnerState.append(line: line) } },
                onStderrLine: { line in Task { @MainActor in runnerState.append(line: line) } }
            )
            runnerState.finish(result: result)

            if result.didSucceed {
                phase = .succeeded
                await repository.refresh()
                TermQLogger.ui.notice(
                    "HarnessUpdate: \(harnessName) ynh update succeeded, re-probing availability"
                )
                await availabilityService.refreshAll()
            } else {
                TermQLogger.ui.error(
                    "HarnessUpdate: \(harnessName) ynh update failed exitCode=\(result.exitCode)"
                )
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
