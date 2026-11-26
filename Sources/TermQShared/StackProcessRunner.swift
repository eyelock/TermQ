import Foundation

/// Minimal Sendable process result for stacked-PR provider subprocesses.
///
/// Deliberately not `CommandRunner` (TermQ target) — providers must stay usable from
/// MCPServerLib and the CLI, neither of which depends on the app target.
public struct StackProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Why `StackProcessRunner.run` stopped a process before it finished.
public enum StackProcessError: Error, Equatable, Sendable {
    /// It ran longer than its timeout and was ended.
    case timedOut
}

/// Spawns provider subprocesses with non-interactivity enforced at the spawn site.
///
/// Shared by every `StackProvider` on purpose. git-spice guarantees it will not prompt
/// because TermQ passes `--no-prompt` on every call; gh-stack offers no such flag and
/// instead decides interactivity by sniffing for a TTY. Relying on each provider to
/// remember the right flags makes a hung subprocess one forgotten argument away, so the
/// guarantee lives here instead: stdin is always closed, so anything that asks whether it
/// is interactive is told no.
public enum StackProcessRunner {
    /// How long a stopped process gets to exit on SIGTERM before it is killed.
    static let killGrace: TimeInterval = 2

    /// Run `executable` and collect its output.
    ///
    /// The process is ended (SIGTERM, then SIGKILL after `killGrace`) when it
    /// runs past `timeout`, which throws `StackProcessError.timedOut`, and,
    /// with `terminateOnCancel`, when the calling task is cancelled, which
    /// throws `CancellationError`.
    ///
    /// - Parameter env: merged over the inherited environment. Used to neutralize pagers,
    ///   colour, and prompt behaviour that would otherwise block or corrupt parsing.
    /// - Parameter timeout: seconds the process may run; nil for no limit.
    /// - Parameter terminateOnCancel: end the process when the caller is
    ///   cancelled. Off by default: a write cut off halfway is worse than one
    ///   that finishes after nobody is waiting. Turn it on for reads only.
    public static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: String?,
        env: [String: String] = [:],
        timeout: TimeInterval? = nil,
        terminateOnCancel: Bool = false
    ) async throws -> StackProcessResult {
        let handle = RunningProcess()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe
                    // Never inherit the app's stdin — see the type comment. This is what makes
                    // non-interactivity a property of how TermQ spawns processes rather than a
                    // promise each provider has to keep.
                    process.standardInput = FileHandle.nullDevice
                    if !env.isEmpty {
                        var merged = ProcessInfo.processInfo.environment
                        for (key, value) in env { merged[key] = value }
                        process.environment = merged
                    }
                    if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    handle.started(process)
                    if let timeout {
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                            handle.stop(.timedOut)
                        }
                    }

                    // Read before waiting: a child that fills a pipe buffer blocks on write
                    // while we block on exit. gh-stack's JSON output is small today, but
                    // deadlocking on a verbose future release is not a risk worth carrying.
                    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    switch handle.finished() {
                    case .timedOut?:
                        continuation.resume(throwing: StackProcessError.timedOut)
                    case .cancelled?:
                        continuation.resume(throwing: CancellationError())
                    case nil:
                        continuation.resume(
                            returning: StackProcessResult(
                                exitCode: process.terminationStatus,
                                stdout: String(data: outData, encoding: .utf8) ?? "",
                                stderr: String(data: errData, encoding: .utf8) ?? ""
                            ))
                    }
                }
            }
        } onCancel: {
            if terminateOnCancel { handle.stop(.cancelled) }
        }
    }
}

/// The process one `run` call started, so a cancel or a timeout from another
/// thread can end it. Every field is guarded by `lock`.
private final class RunningProcess: @unchecked Sendable {
    enum StopReason {
        case cancelled
        case timedOut
    }

    private let lock = NSLock()
    private var process: Process?
    private var stopReason: StopReason?
    private var isFinished = false

    /// Records the launched process; ends it at once if a stop came first.
    func started(_ process: Process) {
        lock.lock()
        self.process = process
        let stopNow = stopReason != nil
        lock.unlock()
        if stopNow { terminate(process) }
    }

    /// Asks the process to end. The first reason wins; once it has exited
    /// this does nothing.
    func stop(_ reason: StopReason) {
        lock.lock()
        guard !isFinished, stopReason == nil else {
            lock.unlock()
            return
        }
        stopReason = reason
        let process = self.process
        lock.unlock()
        if let process { terminate(process) }
    }

    /// Marks the process exited and says why it was stopped, if it was.
    func finished() -> StopReason? {
        lock.lock()
        defer { lock.unlock() }
        isFinished = true
        return stopReason
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + StackProcessRunner.killGrace) { [self] in
            lock.lock()
            let exited = isFinished
            lock.unlock()
            if !exited, process.isRunning { kill(pid, SIGKILL) }
        }
    }
}
