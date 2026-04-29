import Foundation
import TermQCore

/// Status of an `AgentLoopProcess` subprocess.
public enum AgentLoopProcessStatus: Sendable, Equatable {
    case notStarted
    case running(pid: Int32)
    case exited(code: Int32)
    case failed(reason: String)
}

/// Errors thrown by `AgentLoopProcess`.
public enum AgentLoopProcessError: Error, Sendable {
    case notRunning
    case alreadyStarted
}

/// Spawns and manages a long-running agent loop driver subprocess and
/// streams its NDJSON trajectory events.
///
/// The launcher is binary-agnostic — it can spawn any process that emits
/// line-delimited JSON to stdout. Tests use a shell script fixture; the
/// real binary is `ynh-agent` (a portable Go binary planned in the agent
/// loop plan, not yet shipped at the time of this slice).
///
/// Lifecycle:
///   1. Construct.
///   2. `start(...)` — returns an `AsyncStream<TrajectoryEvent>`.
///   3. Iterate the stream; the stream finishes when the subprocess exits.
///   4. Call `send(line:)` to write feedback to the subprocess's stdin.
///   5. Call `stop()` to terminate (sends SIGTERM).
public actor AgentLoopProcess {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<TrajectoryEvent>.Continuation?
    private var terminationCode: Int32?
    private var terminationContinuation: CheckedContinuation<Int32, Never>?
    public private(set) var status: AgentLoopProcessStatus = .notStarted

    public init() {}

    /// Spawn the subprocess and begin streaming its stdout as
    /// `TrajectoryEvent` values. Returns immediately. The stream finishes
    /// when the subprocess exits.
    public func start(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) throws -> AsyncStream<TrajectoryEvent> {
        guard process == nil else { throw AgentLoopProcessError.alreadyStarted }

        let (stream, continuation) = AsyncStream<TrajectoryEvent>.makeStream()
        eventContinuation = continuation

        let proc = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        proc.executableURL = executable
        proc.arguments = arguments
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        proc.standardInput = stdinPipe
        if let environment { proc.environment = environment }
        if let currentDirectory { proc.currentDirectoryURL = currentDirectory }

        proc.terminationHandler = { terminated in
            let code = terminated.terminationStatus
            Task { [weak self] in
                await self?.handleTermination(code: code)
            }
        }

        do {
            try proc.run()
        } catch {
            status = .failed(reason: error.localizedDescription)
            continuation.finish()
            eventContinuation = nil
            throw error
        }

        process = proc
        stdinHandle = stdinPipe.fileHandleForWriting
        status = .running(pid: proc.processIdentifier)

        let stdoutHandle = stdoutPipe.fileHandleForReading
        stdoutTask = Task { [weak self] in
            await self?.readStdoutLines(handle: stdoutHandle)
        }

        let stderrHandle = stderrPipe.fileHandleForReading
        stderrTask = Task { [weak self] in
            await self?.consumeStderr(handle: stderrHandle)
        }

        return stream
    }

    /// Write a line to the subprocess's stdin. A trailing newline is
    /// appended automatically if not present.
    public func send(line: String) throws {
        guard let stdinHandle else { throw AgentLoopProcessError.notRunning }
        let suffixed = line.hasSuffix("\n") ? line : line + "\n"
        guard let data = suffixed.data(using: .utf8) else { return }
        try stdinHandle.write(contentsOf: data)
    }

    /// Send SIGTERM to the subprocess. No-op if not running.
    public func stop() {
        process?.terminate()
    }

    // MARK: - Private

    /// Called from the subprocess's terminationHandler. Records the exit
    /// code and unblocks any in-flight `awaitTermination()` waiter. The
    /// stream is still finished by `readStdoutLines` after EOF, but only
    /// after this has run — guaranteeing `status == .exited` before
    /// consumers see the stream end.
    private func handleTermination(code: Int32) {
        status = .exited(code: code)
        terminationCode = code
        terminationContinuation?.resume(returning: code)
        terminationContinuation = nil
        process = nil
        stdinHandle = nil
    }

    /// Suspend until `handleTermination` records an exit code (or return
    /// immediately if it already has).
    private func awaitTermination() async -> Int32 {
        if let code = terminationCode { return code }
        return await withCheckedContinuation { continuation in
            if let code = terminationCode {
                continuation.resume(returning: code)
            } else {
                terminationContinuation = continuation
            }
        }
    }

    /// Drain stdout. Owns the stream's lifetime: finishes the continuation
    /// only after the pipe reaches EOF AND the terminationHandler has
    /// recorded the exit code. This ordering ensures consumers see every
    /// event the subprocess emitted, with `status == .exited` set by the
    /// time the stream ends.
    private func readStdoutLines(handle: FileHandle) async {
        do {
            for try await line in handle.bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                if let event = Self.parseLine(trimmed) {
                    eventContinuation?.yield(event)
                }
            }
        } catch {
            // EOF or pipe closed — expected when the subprocess exits.
        }
        _ = await awaitTermination()
        eventContinuation?.finish()
        eventContinuation = nil
    }

    private func consumeStderr(handle: FileHandle) async {
        // Stderr is reserved for diagnostics; consume to drain the pipe so
        // the subprocess doesn't block. Logging integration lands in a
        // later slice.
        do {
            for try await _ in handle.bytes.lines {
                continue
            }
        } catch {
            // EOF — expected.
        }
    }

    /// Parse one NDJSON line into a `TrajectoryEvent`. Returns `nil` if the
    /// line is not valid JSON or has no top-level `type` field.
    static func parseLine(_ line: String) -> TrajectoryEvent? {
        guard let data = line.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = dict["type"] as? String
        else { return nil }
        let timestamp = (dict["timestamp"] as? String).flatMap(parseISODate) ?? Date()
        return TrajectoryEvent(type: type, timestamp: timestamp, payloadJSON: line)
    }

    private static func parseISODate(_ s: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: s) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }
}
