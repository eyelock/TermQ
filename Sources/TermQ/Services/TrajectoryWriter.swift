import Foundation
import TermQCore

/// Persists agent trajectory events as NDJSON to a per-session file.
///
/// One file per session at:
///
///   `<appSupport>/TermQ[-Debug]/agent-sessions/<sessionId>/trajectory.jsonl`
///
/// New events are appended; the file is never rewritten. Replay surfaces
/// (Transcript viewer, future CI artifact ingest) read it back line by line.
///
/// Failures are silent: if a write fails (disk full, permission denied,
/// etc.) the in-memory event stream continues unaffected. A future slice
/// can surface write errors via a published last-error property; for now
/// the on-disk record is best-effort.
public final class TrajectoryWriter {
    public let fileURL: URL
    private var handle: FileHandle?

    /// Construct a writer for `sessionId`. Creates the session directory
    /// and opens a FileHandle in append mode. Throws if the directory
    /// cannot be created or the file cannot be opened.
    ///
    /// `baseDirectory` overrides the default app-support location (used by
    /// tests). When `nil`, the default is the same TermQ data directory
    /// used by `BoardPersistence`.
    public init(sessionId: UUID, baseDirectory: URL? = nil) throws {
        let base = baseDirectory ?? Self.defaultAgentSessionsDirectory()
        let sessionDir = base.appendingPathComponent(sessionId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionDir, withIntermediateDirectories: true)

        let url = sessionDir.appendingPathComponent("trajectory.jsonl")
        self.fileURL = url

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        self.handle = handle
    }

    /// Append one event to the trajectory file as a JSONL line.
    ///
    /// `payloadJSON` is preserved as-is (the original NDJSON line from the
    /// loop driver). A trailing newline is added if missing. No-op once
    /// the writer has been closed.
    public func append(_ event: TrajectoryEvent) {
        guard let handle else { return }
        var line = event.payloadJSON
        if !line.hasSuffix("\n") { line += "\n" }
        guard let data = line.data(using: .utf8) else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            // Best-effort persistence; in-memory stream is the source of truth.
        }
    }

    /// Close the underlying file handle. Safe to call multiple times.
    public func close() {
        try? handle?.close()
        handle = nil
    }

    deinit {
        try? handle?.close()
    }

    /// Default directory: `<appSupport>/TermQ[-Debug]/agent-sessions/`.
    /// Mirrors the `#if DEBUG` switch used by BoardPersistence.
    private static func defaultAgentSessionsDirectory() -> URL {
        let appSupport =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        #if DEBUG
            let termqDir = appSupport.appendingPathComponent("TermQ-Debug", isDirectory: true)
        #else
            let termqDir = appSupport.appendingPathComponent("TermQ", isDirectory: true)
        #endif
        return termqDir.appendingPathComponent("agent-sessions", isDirectory: true)
    }
}
