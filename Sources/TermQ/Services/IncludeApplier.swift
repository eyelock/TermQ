import Foundation

struct IncludeApplicationOptions {
    let harness: String
    let sourceURL: String
    let path: String?
    let ref: String?
    let pick: [String]
}

/// Runs `ynh include add` and streams output back.
@MainActor
final class IncludeApplier: ObservableObject {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false
    @Published private(set) var errorMessage: String?

    private let commandRunner: any YNHCommandRunner

    init(commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func apply(_ options: IncludeApplicationOptions, ynhPath: String, environment: [String: String]) async {
        isRunning = true
        outputLines = []
        succeeded = false
        errorMessage = nil

        let args = Self.buildIncludeAddArgs(options)

        let exitCode = await streamProcess(
            executable: ynhPath,
            args: args,
            environment: environment
        )

        isRunning = false
        if exitCode == 0 {
            succeeded = true
        } else {
            errorMessage = outputLines.last ?? "Command failed with exit code \(exitCode)"
        }
    }

    /// Builds the `ynh include add` argument vector. Pure function — exposed for testing.
    /// YNH expects full `type/name[.md]` paths for `--pick`; do not strip the type prefix.
    nonisolated static func buildIncludeAddArgs(_ options: IncludeApplicationOptions) -> [String] {
        var args = ["include", "add", options.harness, options.sourceURL]
        if let path = options.path, !path.isEmpty {
            args += ["--path", path]
        }
        if let ref = options.ref, !ref.isEmpty {
            args += ["--ref", ref]
        }
        if !options.pick.isEmpty {
            args += ["--pick", options.pick.joined(separator: ",")]
        }
        return args
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
