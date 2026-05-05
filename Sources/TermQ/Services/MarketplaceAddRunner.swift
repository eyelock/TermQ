import Foundation

/// Runs `ynh registry add <url>` and streams output back.
@MainActor
final class MarketplaceAddRunner: ObservableObject {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false
    @Published private(set) var errorMessage: String?

    private let commandRunner: any YNHCommandRunner

    init(commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func run(ynhPath: String, url: String, environment: [String: String]) async {
        isRunning = true
        outputLines = []
        succeeded = false
        errorMessage = nil

        let exitCode = await streamProcess(
            executable: ynhPath,
            args: ["registry", "add", url],
            environment: environment
        )

        isRunning = false
        if exitCode == 0 {
            succeeded = true
        } else {
            errorMessage = outputLines.last ?? "Command failed with exit code \(exitCode)"
        }
    }

    private func streamProcess(
        executable: String,
        args: [String],
        environment: [String: String]
    ) async -> Int32 {
        let onLine: @Sendable (String) -> Void = { [weak self] line in
            guard !line.isEmpty else { return }
            Task { @MainActor [weak self] in self?.outputLines.append(line) }
        }
        do {
            let result = try await commandRunner.run(
                executable: executable,
                arguments: args,
                environment: environment,
                currentDirectory: nil,
                onStdoutLine: onLine,
                onStderrLine: onLine
            )
            return result.exitCode
        } catch {
            outputLines.append("Error: \(error.localizedDescription)")
            return 1
        }
    }
}
