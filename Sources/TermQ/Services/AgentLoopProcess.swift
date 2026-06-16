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
/// Two transport modes for trajectory events:
///
/// - **File mode** (production) — caller provides a `trajectoryFile` URL.
///   The subprocess is expected to write NDJSON events to that path (the
///   real driver is `ynh agent run --emit-jsonl <path>`). This actor tails
///   the file with a `DispatchSource` vnode watcher and yields events as
///   they appear. The subprocess's stdout is still drained (for the stderr
///   buffer's purposes and to avoid pipe-full deadlocks) but ignored for
///   event purposes.
///
/// - **Stdout mode** (tests) — caller leaves `trajectoryFile` nil. The
///   subprocess's stdout is parsed line-by-line as NDJSON, the way a shell
///   fixture like `echo '{"type":"converged"}'` works.
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
    private var trajectoryTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<TrajectoryEvent>.Continuation?
    private var terminationCode: Int32?
    private var terminationContinuation: CheckedContinuation<Int32, Never>?
    public private(set) var status: AgentLoopProcessStatus = .notStarted

    /// Tail of the subprocess's stderr, capped at `stderrBufferCap` bytes.
    /// Surfaced via `stderrTail` so the UI can show a meaningful error
    /// banner when the driver exits non-zero without emitting any
    /// trajectory events.
    private var stderrBuffer: String = ""
    private static let stderrBufferCap = 16_384

    public var stderrTail: String { stderrBuffer }

    public init() {}

    /// Spawn the subprocess and begin streaming trajectory events.
    ///
    /// - Parameters:
    ///   - executable: Absolute path to the binary to spawn.
    ///   - arguments: Argv (without the executable itself).
    ///   - environment: Process environment, or nil to inherit.
    ///   - currentDirectory: Working directory for the subprocess.
    ///   - trajectoryFile: If non-nil, events are read from this file
    ///     instead of stdout (production mode — see type doc). The file is
    ///     truncated to empty before spawning so the watcher starts on a
    ///     clean canvas.
    public func start(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        trajectoryFile: URL? = nil
    ) throws -> AsyncStream<TrajectoryEvent> {
        guard process == nil else { throw AgentLoopProcessError.alreadyStarted }

        let (stream, continuation) = AsyncStream<TrajectoryEvent>.makeStream()
        eventContinuation = continuation

        // Prepare the trajectory file before spawning so our read fd is
        // open before ynh writes anything.
        if let trajectoryFile {
            try? FileManager.default.createDirectory(
                at: trajectoryFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: trajectoryFile)
            FileManager.default.createFile(atPath: trajectoryFile.path, contents: nil)
            TermQLogger.agent.notice(
                "trajectory file prepared at path=\(trajectoryFile.path)"
            )
        }

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

        TermQLogger.agent.notice(
            "spawning executable=\(executable.lastPathComponent) argc=\(arguments.count) tail=\(trajectoryFile != nil)"
        )

        do {
            try proc.run()
        } catch {
            status = .failed(reason: error.localizedDescription)
            continuation.finish()
            eventContinuation = nil
            TermQLogger.agent.notice(
                "spawn failed: \(error.localizedDescription)"
            )
            throw error
        }

        process = proc
        stdinHandle = stdinPipe.fileHandleForWriting
        status = .running(pid: proc.processIdentifier)
        TermQLogger.agent.notice("spawned pid=\(proc.processIdentifier)")

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let parseStdout = trajectoryFile == nil
        stdoutTask = Task { [weak self] in
            await self?.drainStdout(handle: stdoutHandle, parseAsEvents: parseStdout)
        }

        let stderrHandle = stderrPipe.fileHandleForReading
        stderrTask = Task { [weak self] in
            await self?.consumeStderr(handle: stderrHandle)
        }

        if let trajectoryFile {
            // File-mode: trajectory tail owns the stream's lifetime.
            // We need a Sendable handle on the continuation to yield from
            // outside the actor's isolation.
            let pinnedContinuation = continuation
            trajectoryTask = Task.detached { [weak self] in
                await self?.tailTrajectoryFile(at: trajectoryFile, continuation: pinnedContinuation)
            }
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
    /// code and unblocks any in-flight `awaitTermination()` waiter.
    private func handleTermination(code: Int32) {
        status = .exited(code: code)
        terminationCode = code
        terminationContinuation?.resume(returning: code)
        terminationContinuation = nil
        process = nil
        stdinHandle = nil
        TermQLogger.agent.notice("process exited code=\(code)")
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

    /// Drain stdout. In stdout-mode (`parseAsEvents == true`), parses each
    /// line as a `TrajectoryEvent` and yields it; owns the stream's
    /// lifetime. In file-mode (`parseAsEvents == false`), discards bytes
    /// — the trajectory file tail owns the stream — but the drain is
    /// still necessary so the subprocess doesn't block on a full pipe.
    private func drainStdout(handle: FileHandle, parseAsEvents: Bool) async {
        do {
            for try await line in handle.bytes.lines {
                guard parseAsEvents else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                if let event = Self.parseLine(trimmed) {
                    eventContinuation?.yield(event)
                }
            }
        } catch {
            // EOF or pipe closed — expected when the subprocess exits.
        }
        if parseAsEvents {
            _ = await awaitTermination()
            eventContinuation?.finish()
            eventContinuation = nil
        }
    }

    /// Tail the trajectory file with a `DispatchSource` vnode watcher.
    /// Owns the stream's lifetime in file-mode: finishes the continuation
    /// only after `handleTermination` records an exit code AND a final
    /// drain pass has read any bytes written between the last event and
    /// process exit.
    private func tailTrajectoryFile(
        at url: URL,
        continuation: AsyncStream<TrajectoryEvent>.Continuation
    ) async {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else {
            TermQLogger.agent.notice(
                "trajectory tail: open failed errno=\(errno) path=\(url.path)"
            )
            _ = await awaitTermination()
            continuation.finish()
            return
        }
        TermQLogger.agent.notice("trajectory tail: opened fd=\(fd)")

        // Serial queue → handler invocations don't overlap, so the byte
        // buffer can be a plain class without locking.
        let queue = DispatchQueue(label: "termq.agent.trajectory.tail")
        let buffer = LineBuffer()
        let readHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)

        // Drain whatever's currently available, parsing complete lines and
        // yielding events. Called by the DispatchSource on each .write event
        // and once more at end-of-life.
        func drainAndYield() {
            let data = readHandle.availableData
            guard !data.isEmpty else { return }
            buffer.data.append(data)
            TermQLogger.agent.notice(
                "trajectory tail: read bytes=\(data.count) bufferSize=\(buffer.data.count)"
            )
            while let nl = buffer.data.firstIndex(of: 0x0A) {
                let lineRange = buffer.data.startIndex..<nl
                let lineData = buffer.data[lineRange]
                buffer.data.removeSubrange(buffer.data.startIndex...nl)
                guard let lineStr = String(data: Data(lineData), encoding: .utf8) else { continue }
                let trimmed = lineStr.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                if let event = AgentLoopProcess.parseLine(trimmed) {
                    continuation.yield(event)
                    TermQLogger.agent.notice(
                        "trajectory tail: yielded type=\(event.type)"
                    )
                } else {
                    TermQLogger.agent.notice("trajectory tail: discarded unparsable line")
                }
            }
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )
        source.setEventHandler { drainAndYield() }
        source.activate()

        // Some bytes may have landed between createFile and source activation
        // (rare with the prepare/spawn ordering in `start`, but cheap to be
        // defensive). Drain once explicitly.
        queue.sync { drainAndYield() }

        _ = await awaitTermination()
        TermQLogger.agent.notice("trajectory tail: subprocess terminated, final drain")
        queue.sync { drainAndYield() }

        source.cancel()
        close(fd)
        continuation.finish()
        TermQLogger.agent.notice("trajectory tail: stream finished")
    }

    private func consumeStderr(handle: FileHandle) async {
        // Drain the pipe so the subprocess doesn't block, and keep the
        // tail (last `stderrBufferCap` bytes) so the UI can show what
        // went wrong if the driver exits without emitting any events.
        do {
            for try await line in handle.bytes.lines {
                appendStderr(line + "\n")
            }
        } catch {
            // EOF — expected.
        }
    }

    private func appendStderr(_ chunk: String) {
        stderrBuffer.append(chunk)
        if stderrBuffer.count > Self.stderrBufferCap {
            let overflow = stderrBuffer.count - Self.stderrBufferCap
            stderrBuffer.removeFirst(overflow)
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

    private static func parseISODate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

/// Mutable byte buffer used by the trajectory tail — wrapped in a class so
/// the `DispatchSource` handler closure can mutate it across invocations
/// (the queue is serial, so no locking is needed).
private final class LineBuffer {
    var data = Data()
}
