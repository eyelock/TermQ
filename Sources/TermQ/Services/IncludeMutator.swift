import Foundation

struct IncludeRemoveOptions {
    let harness: String
    let sourceURL: String
    let path: String?
}

struct IncludeUpdateOptions {
    let harness: String
    let sourceURL: String
    /// Identifies the existing include when multiple share the same URL.
    let fromPath: String?
    /// Optional new path (rename in place).
    let path: String?
    /// Replacement picks. Empty array means "do not pass --pick".
    let pick: [String]
    /// Optional new ref.
    let ref: String?
}

/// Runs `ynh include remove` / `ynh include update` and streams output back.
///
/// Sibling to `IncludeApplier` (which handles `add`). Kept separate so the picker
/// flow doesn't need to know about update/remove.
@MainActor
final class IncludeMutator: ObservableObject {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false
    @Published private(set) var errorMessage: String?

    private let commandRunner: any YNHCommandRunner

    init(commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func remove(_ options: IncludeRemoveOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildIncludeRemoveArgs(options), ynhPath: ynhPath, environment: environment)
    }

    func update(_ options: IncludeUpdateOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildIncludeUpdateArgs(options), ynhPath: ynhPath, environment: environment)
    }

    /// Builds the `ynh include remove` argument vector. Pure — exposed for testing.
    nonisolated static func buildIncludeRemoveArgs(_ options: IncludeRemoveOptions) -> [String] {
        var args = ["include", "remove", options.harness, options.sourceURL]
        if let path = options.path, !path.isEmpty {
            args += ["--path", path]
        }
        return args
    }

    /// Builds the `ynh include update` argument vector. Pure — exposed for testing.
    nonisolated static func buildIncludeUpdateArgs(_ options: IncludeUpdateOptions) -> [String] {
        var args = ["include", "update", options.harness, options.sourceURL]
        if let fromPath = options.fromPath, !fromPath.isEmpty {
            args += ["--from-path", fromPath]
        }
        if let path = options.path, !path.isEmpty {
            args += ["--path", path]
        }
        if !options.pick.isEmpty {
            args += ["--pick", options.pick.joined(separator: ",")]
        }
        if let ref = options.ref, !ref.isEmpty {
            args += ["--ref", ref]
        }
        return args
    }

    private func run(args: [String], ynhPath: String, environment: [String: String]) async {
        isRunning = true
        outputLines = []
        succeeded = false
        errorMessage = nil

        let exitCode = await streamProcess(executable: ynhPath, args: args, environment: environment)

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
