import Foundation

// Mutable buffer shared between readabilityHandler and terminationHandler.
// The OS guarantees serial delivery (termination fires after readability is nil'd),
// so @unchecked Sendable is safe here.
private final class LineBuffer: @unchecked Sendable {
    var data = Data()
}

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

struct IncludeApplicationOptions {
    let harness: String
    let sourceURL: String
    let path: String?
    let pick: [String]
}

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
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                process.standardOutput = pipe
                process.standardError = pipe
                process.environment = environment

                let handle = pipe.fileHandleForReading
                let lineBuffer = LineBuffer()

                handle.readabilityHandler = { fh in
                    let chunk = fh.availableData
                    guard !chunk.isEmpty else { return }
                    lineBuffer.data.append(chunk)
                    if let text = String(data: lineBuffer.data, encoding: .utf8) {
                        let lines = text.components(separatedBy: "\n")
                        let complete = lines.dropLast()
                        let partial = lines.last ?? ""
                        if !complete.isEmpty {
                            let toEmit = complete.filter { !$0.isEmpty }
                            lineBuffer.data = Data(partial.utf8)
                            DispatchQueue.main.async { [weak self] in
                                self?.outputLines.append(contentsOf: toEmit)
                            }
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    handle.readabilityHandler = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.outputLines.append("Error: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: 1)
                    return
                }

                process.terminationHandler = { terminatedProc in
                    handle.readabilityHandler = nil
                    let remaining = handle.readDataToEndOfFile()
                    if let tail = String(data: remaining, encoding: .utf8), !tail.isEmpty {
                        let lines = tail.components(separatedBy: "\n").filter { !$0.isEmpty }
                        DispatchQueue.main.async { [weak self] in
                            self?.outputLines.append(contentsOf: lines)
                        }
                    }
                    continuation.resume(returning: terminatedProc.terminationStatus)
                }
            }
        }
    }
}

// MARK: - Marketplace runner (used by AddYNHMarketplaceSheet)

/// Runs `ynh registry add <url>` and streams output back.
@MainActor
final class MarketplaceAddRunner: ObservableObject {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false
    @Published private(set) var errorMessage: String?

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
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.standardOutput = pipe
                process.standardError = pipe
                process.environment = environment

                let handle = pipe.fileHandleForReading
                let lineBuffer = LineBuffer()

                handle.readabilityHandler = { fh in
                    let chunk = fh.availableData
                    guard !chunk.isEmpty else { return }
                    lineBuffer.data.append(chunk)
                    if let text = String(data: lineBuffer.data, encoding: .utf8) {
                        let lines = text.components(separatedBy: "\n")
                        let complete = lines.dropLast()
                        let partial = lines.last ?? ""
                        if !complete.isEmpty {
                            let toEmit = complete.filter { !$0.isEmpty }
                            lineBuffer.data = Data(partial.utf8)
                            DispatchQueue.main.async { [weak self] in
                                self?.outputLines.append(contentsOf: toEmit)
                            }
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    handle.readabilityHandler = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.outputLines.append("Error: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: 1)
                    return
                }

                process.terminationHandler = { terminatedProc in
                    handle.readabilityHandler = nil
                    let remaining = handle.readDataToEndOfFile()
                    if let tail = String(data: remaining, encoding: .utf8), !tail.isEmpty {
                        let lines = tail.components(separatedBy: "\n").filter { !$0.isEmpty }
                        DispatchQueue.main.async { [weak self] in
                            self?.outputLines.append(contentsOf: lines)
                        }
                    }
                    continuation.resume(returning: terminatedProc.terminationStatus)
                }
            }
        }
    }
}

// MARK: - Include mutator (used by harness detail editor)

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
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.standardOutput = pipe
                process.standardError = pipe
                process.environment = environment

                let handle = pipe.fileHandleForReading
                let lineBuffer = LineBuffer()

                handle.readabilityHandler = { fh in
                    let chunk = fh.availableData
                    guard !chunk.isEmpty else { return }
                    lineBuffer.data.append(chunk)
                    if let text = String(data: lineBuffer.data, encoding: .utf8) {
                        let lines = text.components(separatedBy: "\n")
                        let complete = lines.dropLast()
                        let partial = lines.last ?? ""
                        if !complete.isEmpty {
                            let toEmit = complete.filter { !$0.isEmpty }
                            lineBuffer.data = Data(partial.utf8)
                            DispatchQueue.main.async { [weak self] in
                                self?.outputLines.append(contentsOf: toEmit)
                            }
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    handle.readabilityHandler = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.outputLines.append("Error: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: 1)
                    return
                }

                process.terminationHandler = { terminatedProc in
                    handle.readabilityHandler = nil
                    let remaining = handle.readDataToEndOfFile()
                    if let tail = String(data: remaining, encoding: .utf8), !tail.isEmpty {
                        let lines = tail.components(separatedBy: "\n").filter { !$0.isEmpty }
                        DispatchQueue.main.async { [weak self] in
                            self?.outputLines.append(contentsOf: lines)
                        }
                    }
                    continuation.resume(returning: terminatedProc.terminationStatus)
                }
            }
        }
    }
}

// MARK: - Delegate mutator (used by harness detail editor)

/// Runs `ynh delegate add/remove/update` and streams output back. Sibling to
/// `IncludeMutator`; delegates differ only in that they cannot narrow with
/// `--pick` (the whole referenced harness is merged in).
@MainActor
final class DelegateMutator: ObservableObject {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false
    @Published private(set) var errorMessage: String?

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
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.standardOutput = pipe
                process.standardError = pipe
                process.environment = environment

                let handle = pipe.fileHandleForReading
                let lineBuffer = LineBuffer()

                handle.readabilityHandler = { fh in
                    let chunk = fh.availableData
                    guard !chunk.isEmpty else { return }
                    lineBuffer.data.append(chunk)
                    if let text = String(data: lineBuffer.data, encoding: .utf8) {
                        let lines = text.components(separatedBy: "\n")
                        let complete = lines.dropLast()
                        let partial = lines.last ?? ""
                        if !complete.isEmpty {
                            let toEmit = complete.filter { !$0.isEmpty }
                            lineBuffer.data = Data(partial.utf8)
                            DispatchQueue.main.async { [weak self] in
                                self?.outputLines.append(contentsOf: toEmit)
                            }
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    handle.readabilityHandler = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.outputLines.append("Error: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: 1)
                    return
                }

                process.terminationHandler = { terminatedProc in
                    handle.readabilityHandler = nil
                    let remaining = handle.readDataToEndOfFile()
                    if let tail = String(data: remaining, encoding: .utf8), !tail.isEmpty {
                        let lines = tail.components(separatedBy: "\n").filter { !$0.isEmpty }
                        DispatchQueue.main.async { [weak self] in
                            self?.outputLines.append(contentsOf: lines)
                        }
                    }
                    continuation.resume(returning: terminatedProc.terminationStatus)
                }
            }
        }
    }
}

// MARK: - Marketplace listing service (used by SettingsMarketplacesView)

struct YNHMarketplace: Identifiable, Decodable {
    var id: String { url }
    let url: String
    let name: String
    let description: String?
    let ref: String?
}

@MainActor
final class YNHMarketplaceService: ObservableObject {
    @Published private(set) var marketplaces: [YNHMarketplace] = []
    @Published private(set) var isLoading = false

    func refresh(ynhPath: String, environment: [String: String]) async {
        isLoading = true
        defer { isLoading = false }
        if let data = await fetch(
            executable: ynhPath, args: ["registry", "list", "--format", "json"], environment: environment),
            let decoded = try? JSONDecoder().decode([YNHMarketplace].self, from: data)
        {
            marketplaces = decoded
        }
    }

    func remove(url: String, ynhPath: String, environment: [String: String]) async {
        await runSilent(executable: ynhPath, args: ["registry", "remove", url], environment: environment)
        await refresh(ynhPath: ynhPath, environment: environment)
    }

    private func fetch(executable: String, args: [String], environment: [String: String]) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.standardOutput = pipe
                process.standardError = Pipe()
                process.environment = environment
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: process.terminationStatus == 0 ? data : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func runSilent(executable: String, args: [String], environment: [String: String]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.environment = environment
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try? process.run()
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }
}

// MARK: - Include runner (used by HarnessIncludePicker)

/// Runs `ynh include add` and streams output back.
@MainActor
final class IncludeApplier: ObservableObject {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false
    @Published private(set) var errorMessage: String?

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
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.standardOutput = pipe
                process.standardError = pipe
                process.environment = environment

                let handle = pipe.fileHandleForReading
                let lineBuffer = LineBuffer()

                handle.readabilityHandler = { fh in
                    let chunk = fh.availableData
                    guard !chunk.isEmpty else { return }
                    lineBuffer.data.append(chunk)
                    if let text = String(data: lineBuffer.data, encoding: .utf8) {
                        let lines = text.components(separatedBy: "\n")
                        let complete = lines.dropLast()
                        let partial = lines.last ?? ""
                        if !complete.isEmpty {
                            let toEmit = complete.filter { !$0.isEmpty }
                            lineBuffer.data = Data(partial.utf8)
                            DispatchQueue.main.async { [weak self] in
                                self?.outputLines.append(contentsOf: toEmit)
                            }
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    handle.readabilityHandler = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.outputLines.append("Error: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: 1)
                    return
                }

                process.terminationHandler = { terminatedProc in
                    handle.readabilityHandler = nil
                    let remaining = handle.readDataToEndOfFile()
                    if let tail = String(data: remaining, encoding: .utf8), !tail.isEmpty {
                        let lines = tail.components(separatedBy: "\n").filter { !$0.isEmpty }
                        DispatchQueue.main.async { [weak self] in
                            self?.outputLines.append(contentsOf: lines)
                        }
                    }
                    continuation.resume(returning: terminatedProc.terminationStatus)
                }
            }
        }
    }
}
