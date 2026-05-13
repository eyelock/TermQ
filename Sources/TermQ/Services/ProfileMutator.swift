import Foundation

// MARK: - Profile options

struct ProfileAddOptions {
    let harness: String
    let name: String
}

struct ProfileRemoveOptions {
    let harness: String
    let name: String
}

// MARK: - Hook options

struct ProfileHookAddOptions {
    let harness: String
    let profileName: String
    let event: String
    let command: String
    let matcher: String?
}

struct ProfileHookRemoveOptions {
    let harness: String
    let profileName: String
    let event: String
    let index: Int
}

// MARK: - MCP options

struct ProfileMCPAddOptions {
    let harness: String
    let profileName: String
    let serverName: String
    let command: String?
    let args: [String]
    let env: [String: String]
    let url: String?
    let headers: [String: String]
    let null: Bool
}

struct ProfileMCPRemoveOptions {
    let harness: String
    let profileName: String
    let serverName: String
}

struct ProfileMCPUpdateOptions {
    let harness: String
    let profileName: String
    let serverName: String
    let command: String?
    let args: [String]
    let setArgs: Bool
    let env: [String: String]
    let setEnv: Bool
    let url: String?
    let headers: [String: String]
    let setHeaders: Bool
}

// MARK: - Profile include options

struct ProfileIncludeAddOptions {
    let harness: String
    let profileName: String
    let url: String
    let path: String?
    let ref: String?
    let replace: Bool
}

struct ProfileIncludeRemoveOptions {
    let harness: String
    let profileName: String
    let url: String
    let path: String?
}

struct ProfileIncludeUpdateOptions {
    let harness: String
    let profileName: String
    let url: String
    let fromPath: String?
    let newPath: String?
    let ref: String?
}

/// Runs all `ynh profile …` subcommands and streams output back.
@MainActor
final class ProfileMutator: ObservableObject {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false
    @Published private(set) var errorMessage: String?

    private let commandRunner: any YNHCommandRunner

    init(commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.commandRunner = commandRunner
    }

    // MARK: Profile lifecycle

    func addProfile(_ options: ProfileAddOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: ["profile", "add", options.harness, options.name], ynhPath: ynhPath, environment: environment)
    }

    func removeProfile(_ options: ProfileRemoveOptions, ynhPath: String, environment: [String: String]) async {
        await run(
            args: ["profile", "remove", options.harness, options.name],
            ynhPath: ynhPath, environment: environment
        )
    }

    // MARK: Hooks

    func addHook(_ options: ProfileHookAddOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildHookAddArgs(options), ynhPath: ynhPath, environment: environment)
    }

    func removeHook(_ options: ProfileHookRemoveOptions, ynhPath: String, environment: [String: String]) async {
        await run(
            args: [
                "profile", "hook", "remove",
                options.harness, options.profileName, options.event, "\(options.index)",
            ],
            ynhPath: ynhPath, environment: environment
        )
    }

    // MARK: MCP servers

    func addMCP(_ options: ProfileMCPAddOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildMCPAddArgs(options), ynhPath: ynhPath, environment: environment)
    }

    func removeMCP(_ options: ProfileMCPRemoveOptions, ynhPath: String, environment: [String: String]) async {
        await run(
            args: ["profile", "mcp", "remove", options.harness, options.profileName, options.serverName],
            ynhPath: ynhPath, environment: environment
        )
    }

    func updateMCP(_ options: ProfileMCPUpdateOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildMCPUpdateArgs(options), ynhPath: ynhPath, environment: environment)
    }

    // MARK: Includes

    func addInclude(_ options: ProfileIncludeAddOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildIncludeAddArgs(options), ynhPath: ynhPath, environment: environment)
    }

    func removeInclude(_ options: ProfileIncludeRemoveOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildIncludeRemoveArgs(options), ynhPath: ynhPath, environment: environment)
    }

    func updateInclude(_ options: ProfileIncludeUpdateOptions, ynhPath: String, environment: [String: String]) async {
        await run(args: Self.buildIncludeUpdateArgs(options), ynhPath: ynhPath, environment: environment)
    }

    // MARK: - Arg builders (pure, exposed for testing)

    nonisolated static func buildHookAddArgs(_ options: ProfileHookAddOptions) -> [String] {
        var args = ["profile", "hook", "add", options.harness, options.profileName, options.event, options.command]
        if let matcher = options.matcher, !matcher.isEmpty {
            args += ["--matcher", matcher]
        }
        return args
    }

    nonisolated static func buildMCPAddArgs(_ options: ProfileMCPAddOptions) -> [String] {
        var args = ["profile", "mcp", "add", options.harness, options.profileName, options.serverName]
        if options.null {
            args += ["--null"]
            return args
        }
        if let command = options.command, !command.isEmpty {
            args += ["--command", command]
        }
        for arg in options.args {
            args += ["--arg", arg]
        }
        for (key, value) in options.env.sorted(by: { $0.key < $1.key }) {
            args += ["--env", "\(key)=\(value)"]
        }
        if let url = options.url, !url.isEmpty {
            args += ["--url", url]
        }
        for (key, value) in options.headers.sorted(by: { $0.key < $1.key }) {
            args += ["--header", "\(key)=\(value)"]
        }
        return args
    }

    nonisolated static func buildMCPUpdateArgs(_ options: ProfileMCPUpdateOptions) -> [String] {
        var args = ["profile", "mcp", "update", options.harness, options.profileName, options.serverName]
        if let command = options.command, !command.isEmpty {
            args += ["--command", command]
        }
        if options.setArgs {
            if options.args.isEmpty {
                args += ["--clear-args"]
            } else {
                for arg in options.args { args += ["--arg", arg] }
            }
        }
        if options.setEnv {
            if options.env.isEmpty {
                args += ["--clear-env"]
            } else {
                for (key, value) in options.env.sorted(by: { $0.key < $1.key }) {
                    args += ["--env", "\(key)=\(value)"]
                }
            }
        }
        if let url = options.url, !url.isEmpty {
            args += ["--url", url]
        }
        if options.setHeaders {
            if options.headers.isEmpty {
                args += ["--clear-headers"]
            } else {
                for (key, value) in options.headers.sorted(by: { $0.key < $1.key }) {
                    args += ["--header", "\(key)=\(value)"]
                }
            }
        }
        return args
    }

    nonisolated static func buildIncludeAddArgs(_ options: ProfileIncludeAddOptions) -> [String] {
        var args = ["profile", "include", "add", options.harness, options.profileName, options.url]
        if let path = options.path, !path.isEmpty { args += ["--path", path] }
        if let ref = options.ref, !ref.isEmpty { args += ["--ref", ref] }
        if options.replace { args += ["--replace"] }
        return args
    }

    nonisolated static func buildIncludeRemoveArgs(_ options: ProfileIncludeRemoveOptions) -> [String] {
        var args = ["profile", "include", "remove", options.harness, options.profileName, options.url]
        if let path = options.path, !path.isEmpty { args += ["--path", path] }
        return args
    }

    nonisolated static func buildIncludeUpdateArgs(_ options: ProfileIncludeUpdateOptions) -> [String] {
        var args = ["profile", "include", "update", options.harness, options.profileName, options.url]
        if let fromPath = options.fromPath, !fromPath.isEmpty { args += ["--from-path", fromPath] }
        if let newPath = options.newPath, !newPath.isEmpty { args += ["--path", newPath] }
        if let ref = options.ref, !ref.isEmpty { args += ["--ref", ref] }
        return args
    }

    // MARK: - Private

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
