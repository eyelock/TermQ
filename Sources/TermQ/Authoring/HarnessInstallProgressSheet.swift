import SwiftUI
import TermQShared

/// Sheet that runs `ynh install` for a chosen `HarnessInstallConfig` and
/// surfaces live output through `CommandRunnerSheet`. Replaces the prior
/// transient terminal card so install behaves like update / fork.
struct HarnessInstallProgressSheet: View {
    let config: HarnessInstallConfig
    @ObservedObject var detector: YNHDetector
    @ObservedObject var repository: HarnessRepository
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .running
    @StateObject private var runnerState = CommandSheetState()

    private enum Phase { case running, succeeded, failed }

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
        CommandRunnerSheet(
            title: Strings.HarnessInstall.progressTitle(config.displayName),
            state: runnerState,
            onRerun: phase == .failed ? { Task { await runInstall() } } : nil,
            onDismiss: { dismiss() }
        )
        .task {
            if runnerState.outputLines.isEmpty {
                await runInstall()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runInstall() async {
        guard let ynhBin = ynhPath else {
            runnerState.begin()
            runnerState.append(line: Strings.HarnessInstall.ynhUnavailable)
            runnerState.finish(
                result: CommandRunner.Result(
                    exitCode: 1, stdout: "", stderr: Strings.HarnessInstall.ynhUnavailable,
                    duration: 0))
            phase = .failed
            return
        }

        runnerState.begin()
        phase = .running

        do {
            let result = try await CommandRunner.run(
                executable: ynhBin,
                arguments: ["install"] + config.installArgs,
                environment: ynhEnvironment,
                onStdoutLine: { line in Task { @MainActor in runnerState.append(line: line) } },
                onStderrLine: { line in Task { @MainActor in runnerState.append(line: line) } }
            )
            runnerState.finish(result: result)

            if result.didSucceed {
                phase = .succeeded
                await repository.refresh()
            } else {
                TermQLogger.ui.error(
                    "HarnessInstall: \(config.displayName) ynh install failed exitCode=\(result.exitCode)"
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
