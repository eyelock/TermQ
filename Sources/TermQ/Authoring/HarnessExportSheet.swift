import SwiftUI
import TermQShared

/// Sheet that runs `ynd export <harness-path> -o <output-dir>` with live
/// output through `CommandRunnerSheet`. Replaces the prior transient terminal
/// card.
struct HarnessExportSheet: View {
    let harnessName: String
    let harnessPath: String
    let outputDir: String
    @ObservedObject var detector: YNHDetector
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .running
    @StateObject private var runnerState = CommandSheetState()

    private enum Phase { case running, succeeded, failed }

    private var yndPath: String? {
        if case .ready(_, let path?, _) = detector.status { return path }
        return nil
    }
    private var ynhEnvironment: [String: String] {
        var environ = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride { environ["YNH_HOME"] = override }
        return environ
    }

    var body: some View {
        CommandRunnerSheet(
            title: Strings.HarnessExport.progressTitle(harnessName),
            state: runnerState,
            onRerun: phase == .failed ? { Task { await runExport() } } : nil,
            onDismiss: { dismiss() }
        )
        .task {
            if runnerState.outputLines.isEmpty {
                await runExport()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runExport() async {
        guard let yndBin = yndPath else {
            runnerState.begin()
            runnerState.append(line: Strings.HarnessExport.yndUnavailable)
            runnerState.finish(
                result: CommandRunner.Result(
                    exitCode: 1, stdout: "", stderr: Strings.HarnessExport.yndUnavailable,
                    duration: 0))
            phase = .failed
            return
        }

        runnerState.begin()
        phase = .running

        do {
            let result = try await CommandRunner.run(
                executable: yndBin,
                arguments: ["export", harnessPath, "-o", outputDir],
                environment: ynhEnvironment,
                onStdoutLine: { line in Task { @MainActor in runnerState.append(line: line) } },
                onStderrLine: { line in Task { @MainActor in runnerState.append(line: line) } }
            )
            runnerState.finish(result: result)
            phase = result.didSucceed ? .succeeded : .failed
            if !result.didSucceed {
                TermQLogger.ui.error(
                    "HarnessExport: \(harnessName) ynd export failed exitCode=\(result.exitCode)"
                )
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
