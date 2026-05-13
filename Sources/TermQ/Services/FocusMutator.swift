import Foundation

struct FocusAddOptions {
    let harness: String
    let name: String
    let prompt: String
    let profile: String?
}

struct FocusRemoveOptions {
    let harness: String
    let name: String
}

struct FocusUpdateOptions {
    let harness: String
    let name: String
    let prompt: String?
    let profile: String?
    let clearProfile: Bool
}

/// Runs `ynh focus add/remove/update` and streams output back.
@MainActor
final class FocusMutator: ObservableObject {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false
    @Published private(set) var errorMessage: String?

    private let commandRunner: any YNHCommandRunner

    init(commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func add(_ options: FocusAddOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildAddArgs(options), ynhPath: ynhPath, environment: environment)
    }

    func remove(_ options: FocusRemoveOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildRemoveArgs(options), ynhPath: ynhPath, environment: environment)
    }

    func update(_ options: FocusUpdateOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildUpdateArgs(options), ynhPath: ynhPath, environment: environment)
    }

    nonisolated static func buildAddArgs(_ options: FocusAddOptions) -> [String] {
        var args = ["focus", "add", options.harness, options.name, options.prompt]
        if let profile = options.profile, !profile.isEmpty {
            args += ["--profile", profile]
        }
        return args
    }

    nonisolated static func buildRemoveArgs(_ options: FocusRemoveOptions) -> [String] {
        ["focus", "remove", options.harness, options.name]
    }

    nonisolated static func buildUpdateArgs(_ options: FocusUpdateOptions) -> [String] {
        var args = ["focus", "update", options.harness, options.name]
        if let prompt = options.prompt, !prompt.isEmpty {
            args += ["--prompt", prompt]
        }
        if options.clearProfile {
            args += ["--clear-profile"]
        } else if let profile = options.profile, !profile.isEmpty {
            args += ["--profile", profile]
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
