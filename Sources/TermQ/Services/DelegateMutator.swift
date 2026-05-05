import Foundation

struct DelegateAddOptions {
    let harness: String
    let sourceURL: String
    let ref: String?
    let path: String?
}

struct DelegateRemoveOptions {
    let harness: String
    let sourceURL: String
    let path: String?
}

struct DelegateUpdateOptions {
    let harness: String
    let sourceURL: String
    let fromPath: String?
    let path: String?
    let ref: String?
}

/// Runs `ynh delegate add/remove/update` and streams output back. Sibling to
/// `IncludeMutator`; delegates differ only in that they cannot narrow with
/// `--pick` (the whole referenced harness is merged in).
@MainActor
final class DelegateMutator: ObservableObject {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false
    @Published private(set) var errorMessage: String?

    private let commandRunner: any YNHCommandRunner

    init(commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func add(_ options: DelegateAddOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildDelegateAddArgs(options), ynhPath: ynhPath, environment: environment)
    }

    func remove(_ options: DelegateRemoveOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildDelegateRemoveArgs(options), ynhPath: ynhPath, environment: environment)
    }

    func update(_ options: DelegateUpdateOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildDelegateUpdateArgs(options), ynhPath: ynhPath, environment: environment)
    }

    /// Builds the `ynh delegate add` argument vector. Pure — exposed for testing.
    nonisolated static func buildDelegateAddArgs(_ options: DelegateAddOptions) -> [String] {
        var args = ["delegate", "add", options.harness, options.sourceURL]
        if let ref = options.ref, !ref.isEmpty {
            args += ["--ref", ref]
        }
        if let path = options.path, !path.isEmpty {
            args += ["--path", path]
        }
        return args
    }

    /// Builds the `ynh delegate remove` argument vector. Pure — exposed for testing.
    nonisolated static func buildDelegateRemoveArgs(_ options: DelegateRemoveOptions) -> [String] {
        var args = ["delegate", "remove", options.harness, options.sourceURL]
        if let path = options.path, !path.isEmpty {
            args += ["--path", path]
        }
        return args
    }

    /// Builds the `ynh delegate update` argument vector. Pure — exposed for testing.
    nonisolated static func buildDelegateUpdateArgs(_ options: DelegateUpdateOptions) -> [String] {
        var args = ["delegate", "update", options.harness, options.sourceURL]
        if let fromPath = options.fromPath, !fromPath.isEmpty {
            args += ["--from-path", fromPath]
        }
        if let path = options.path, !path.isEmpty {
            args += ["--path", path]
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
