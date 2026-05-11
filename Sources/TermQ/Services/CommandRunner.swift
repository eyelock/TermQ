import Foundation

/// Streamed shell-out abstraction for invoking external CLIs (ynh, ynd, git).
///
/// Emits stdout and stderr lines as they arrive so callers can surface live
/// progress. The full captured output is also returned on completion for
/// callers that want both.
///
/// ## Logging policy
///
/// Default-level logs carry only the command name (basename of the executable),
/// exit code, and duration. Argument lists, the working directory, and the raw
/// stdout/stderr streams are treated as user data and only emitted to file
/// logging (`TERMQ_DEBUG=1`). See `logging-rules` skill.
enum CommandRunner {
    struct Result: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let duration: TimeInterval

        var didSucceed: Bool { exitCode == 0 }
    }

    enum RunError: Error, LocalizedError, Sendable {
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let detail):
                return "failed to launch process: \(detail)"
            }
        }
    }

    /// Run a command, streaming stdout/stderr lines as they arrive.
    ///
    /// - Returns: a `Result` containing exit code, full captured stdout/stderr,
    ///   and elapsed wall-clock duration. Non-zero exit codes are returned in
    ///   the result, never thrown — callers decide how to react.
    /// - Throws: `RunError.launchFailed` only when the process cannot be started.
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil,
        onStdoutLine: (@Sendable (String) -> Void)? = nil,
        onStderrLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> Result {
        let commandName = (executable as NSString).lastPathComponent
        let start = Date()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                if let environment {
                    process.environment = environment
                }
                if let currentDirectory {
                    process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
                }

                let stdoutAccum = ByteAccumulator()
                let stderrAccum = ByteAccumulator()
                let stdoutLines = LineBuffer(onLine: onStdoutLine)
                let stderrLines = LineBuffer(onLine: onStderrLine)

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty { return }
                    stdoutAccum.append(chunk)
                    stdoutLines.append(chunk)
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty { return }
                    stderrAccum.append(chunk)
                    stderrLines.append(chunk)
                }

                do {
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    TermQLogger.process.error(
                        "command name=\(commandName) launch_failed=\(error.localizedDescription)"
                    )
                    continuation.resume(
                        throwing: RunError.launchFailed(error.localizedDescription)
                    )
                    return
                }

                process.waitUntilExit()

                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                // Drain anything that arrived between the last readability
                // callback and process exit.
                let tailOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if !tailOut.isEmpty {
                    stdoutAccum.append(tailOut)
                    stdoutLines.append(tailOut)
                }
                let tailErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !tailErr.isEmpty {
                    stderrAccum.append(tailErr)
                    stderrLines.append(tailErr)
                }
                stdoutLines.flush()
                stderrLines.flush()

                let exitCode = process.terminationStatus
                let duration = Date().timeIntervalSince(start)

                TermQLogger.process.info(
                    "command name=\(commandName) exit=\(exitCode) duration=\(String(format: "%.3fs", duration))"
                )
                if TermQLogger.fileLoggingEnabled {
                    let argString = arguments.joined(separator: " ")
                    TermQLogger.process.debug(
                        "command name=\(commandName) args=[\(argString)] cwd=\(currentDirectory ?? "<inherit>")"
                    )
                    TermQLogger.process.debug(
                        "command name=\(commandName) stdout=\(stdoutAccum.string())"
                    )
                    TermQLogger.process.debug(
                        "command name=\(commandName) stderr=\(stderrAccum.string())"
                    )
                }

                let result = Result(
                    exitCode: exitCode,
                    stdout: stdoutAccum.string(),
                    stderr: stderrAccum.string(),
                    duration: duration
                )
                continuation.resume(returning: result)
            }
        }
    }
}

// MARK: - Internal helpers

/// Thread-safe Data accumulator for capturing the full stream in parallel with
/// the streaming line callbacks.
private final class ByteAccumulator: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Splits an incoming byte stream on `\n` and forwards complete lines to a
/// callback. A trailing partial line is held until the next chunk or `flush()`.
private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    func append(_ chunk: Data) {
        guard let onLine else { return }
        lock.lock()
        pending.append(chunk)
        var emitted: [String] = []
        while let newlineIndex = pending.firstIndex(of: 0x0A) {
            let lineData = pending.subdata(in: pending.startIndex..<newlineIndex)
            pending.removeSubrange(pending.startIndex...newlineIndex)
            if let line = String(data: lineData, encoding: .utf8) {
                emitted.append(line)
            }
        }
        lock.unlock()
        for line in emitted { onLine(line) }
    }

    func flush() {
        guard let onLine else { return }
        lock.lock()
        let remaining = pending
        pending = Data()
        lock.unlock()
        guard !remaining.isEmpty,
            let line = String(data: remaining, encoding: .utf8)
        else { return }
        onLine(line)
    }
}
