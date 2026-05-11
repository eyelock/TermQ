import Foundation

/// Status of an individual command step in the authoring sequence.
enum AuthorStepStatus: Sendable {
    case pending
    case running
    case done
    case failed(String)

    var isTerminal: Bool {
        switch self {
        case .done, .failed: return true
        default: return false
        }
    }
}

/// A single named step tracked by `HarnessAuthor`.
struct AuthorStep: Identifiable, Sendable {
    let id: UUID
    let label: String
    var status: AuthorStepStatus
    var command: String  // preview shown to user before execution

    init(label: String, command: String) {
        self.id = UUID()
        self.label = label
        self.command = command
        self.status = .pending
    }
}

struct HarnessCreationOptions {
    let name: String
    let description: String
    let vendorID: String
    let destination: String
    let install: Bool
}

struct YNHBinaries {
    let yndPath: String
    let ynhPath: String
}

/// Sequences `ynd create harness <name>` + optional `ynh install <path>`.
///
/// Streams combined stdout/stderr lines to `outputLines` and tracks per-step status.
/// `include add` calls live in `HarnessIncludePicker` — this class only handles creation.
@MainActor
final class HarnessAuthor: ObservableObject {
    @Published private(set) var steps: [AuthorStep] = []
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false

    private(set) var createdHarnessName: String?

    private let commandRunner: any YNHCommandRunner

    init(commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func run(_ options: HarnessCreationOptions, binaries: YNHBinaries, environment: [String: String]) async {
        var createCmd = "\(binaries.yndPath) create harness \(options.name)"
        if !options.description.isEmpty { createCmd += " --description \"\(options.description)\"" }
        if !options.vendorID.isEmpty { createCmd += " --vendor \(options.vendorID)" }
        let installPath = (options.destination as NSString).appendingPathComponent(options.name)
        let installCmd = "\(binaries.ynhPath) install \(installPath)"

        steps = [AuthorStep(label: "Create harness", command: createCmd)]
        if options.install {
            steps.append(AuthorStep(label: "Install harness", command: installCmd))
        }
        outputLines = []
        isRunning = true
        succeeded = false

        // Step 1: create
        var createArgs = ["create", "harness", options.name]
        if !options.description.isEmpty { createArgs += ["--description", options.description] }
        if !options.vendorID.isEmpty { createArgs += ["--vendor", options.vendorID] }
        let createOK = await runStep(
            index: 0,
            executable: binaries.yndPath,
            args: createArgs,
            cwd: options.destination,
            environment: environment
        )
        guard createOK else {
            isRunning = false
            return
        }
        createdHarnessName = options.name

        // Step 2: install (optional)
        if options.install {
            let installOK = await runStep(
                index: 1,
                executable: binaries.ynhPath,
                args: ["install", installPath],
                cwd: options.destination,
                environment: environment
            )
            guard installOK else {
                isRunning = false
                return
            }
        }

        isRunning = false
        succeeded = true
    }

    // MARK: - Private

    private func runStep(
        index: Int,
        executable: String,
        args: [String],
        cwd: String,
        environment: [String: String]
    ) async -> Bool {
        steps[index].status = .running

        let exitCode = await streamProcess(
            executable: executable,
            args: args,
            cwd: cwd,
            environment: environment
        )

        if exitCode == 0 {
            steps[index].status = .done
            return true
        } else {
            steps[index].status = .failed("Exit \(exitCode)")
            return false
        }
    }

    private func streamProcess(
        executable: String,
        args: [String],
        cwd: String,
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
                currentDirectory: cwd,
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
