import Foundation

struct HarnessHookAddOptions {
    let harness: String
    let event: String
    let command: String
    let matcher: String?
}

struct HarnessMCPAddOptions {
    let harness: String
    let serverName: String
    let command: String?
    let args: [String]
    let env: [String: String]
    let url: String?
    let headers: [String: String]
}

struct HarnessHookRemoveOptions {
    let harness: String
    let event: String
    let index: Int
}

struct HarnessMCPRemoveOptions {
    let harness: String
    let serverName: String
}

/// Runs `ynh hook` and `ynh mcp` mutation commands at the harness level.
@MainActor
final class HarnessHookMutator: ObservableObject {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false
    @Published private(set) var errorMessage: String?

    private let commandRunner: any YNHCommandRunner

    init(commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func addHook(_ options: HarnessHookAddOptions, ynhPath: String, environment: [String: String]) async {
        var args = ["hook", "add", options.harness, options.event, options.command]
        if let matcher = options.matcher, !matcher.isEmpty { args += ["--matcher", matcher] }
        await run(args: args, ynhPath: ynhPath, environment: environment)
    }

    func addMCP(_ options: HarnessMCPAddOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildMCPAddArgs(options), ynhPath: ynhPath, environment: environment)
    }

    func removeHook(_ options: HarnessHookRemoveOptions, ynhPath: String, environment: [String: String]) async {
        let args = ["hook", "remove", options.harness, options.event, String(options.index)]
        await run(args: args, ynhPath: ynhPath, environment: environment)
    }

    func removeMCP(_ options: HarnessMCPRemoveOptions, ynhPath: String, environment: [String: String]) async {
        let args = ["mcp", "remove", options.harness, options.serverName]
        await run(args: args, ynhPath: ynhPath, environment: environment)
    }

    nonisolated static func buildMCPAddArgs(_ options: HarnessMCPAddOptions) -> [String] {
        var args = ["mcp", "add", options.harness, options.serverName]
        if let command = options.command, !command.isEmpty { args += ["--command", command] }
        for arg in options.args { args += ["--arg", arg] }
        for (key, value) in options.env.sorted(by: { $0.key < $1.key }) { args += ["--env", "\(key)=\(value)"] }
        if let url = options.url, !url.isEmpty { args += ["--url", url] }
        for (key, value) in options.headers.sorted(by: { $0.key < $1.key }) { args += ["--header", "\(key)=\(value)"] }
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
