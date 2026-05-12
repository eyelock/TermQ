import SwiftUI
import TermQShared

/// Sheet that runs `ynh uninstall <canonicalID>` with live output through
/// `CommandRunnerSheet`. On success, clears YNHPersistence associations and
/// refreshes the harness list. Replaces the prior transient terminal card.
struct HarnessUninstallSheet: View {
    let canonicalID: String
    let harnessName: String
    @ObservedObject var detector: YNHDetector
    @ObservedObject var repository: HarnessRepository
    var ynhPersistence: YNHPersistence = .shared
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
            title: Strings.HarnessUninstall.progressTitle(harnessName),
            state: runnerState,
            onRerun: phase == .failed ? { Task { await runUninstall() } } : nil,
            onDismiss: { dismiss() }
        )
        .task {
            if runnerState.outputLines.isEmpty {
                await runUninstall()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runUninstall() async {
        guard let ynhBin = ynhPath else {
            runnerState.begin()
            runnerState.append(line: Strings.HarnessUninstall.ynhUnavailable)
            runnerState.finish(
                result: CommandRunner.Result(
                    exitCode: 1, stdout: "", stderr: Strings.HarnessUninstall.ynhUnavailable,
                    duration: 0))
            phase = .failed
            return
        }

        runnerState.begin()
        phase = .running

        do {
            let result = try await CommandRunner.run(
                executable: ynhBin,
                arguments: ["uninstall", canonicalID],
                environment: ynhEnvironment,
                onStdoutLine: { line in Task { @MainActor in runnerState.append(line: line) } },
                onStderrLine: { line in Task { @MainActor in runnerState.append(line: line) } }
            )
            runnerState.finish(result: result)

            if result.didSucceed {
                phase = .succeeded
                ynhPersistence.removeAllAssociations(for: harnessName)
                await repository.refresh()
            } else {
                TermQLogger.ui.error(
                    "HarnessUninstall: \(harnessName) ynh uninstall failed exitCode=\(result.exitCode)"
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
