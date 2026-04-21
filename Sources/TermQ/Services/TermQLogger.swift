import Foundation
import TermQCore
import os

/// Structured diagnostic logging for TermQ.
///
/// ## Always active — Unified Logging
/// Every message is routed through Apple Unified Logging. Stream in real-time:
///
///     log stream --predicate 'subsystem == "net.eyelock.termq"'
///     log stream --predicate 'subsystem == "net.eyelock.termq" AND category == "tmux"'
///
/// Or browse historically in Console.app (search by subsystem or category).
///
/// ## File logging — set TERMQ_DEBUG=1
/// When the `TERMQ_DEBUG` environment variable is set, messages are also written
/// to `/tmp/termq-debug.log`. The file is truncated at startup so each run
/// starts clean. Tail it for live output:
///
///     TERMQ_DEBUG=1 open TermQDebug.app
///     tail -f /tmp/termq-debug.log
///
///     # Filter to a specific category:
///     tail -f /tmp/termq-debug.log | grep '\[tmux\]'
///
/// ## Usage
///
///     TermQLogger.tmux.debug("sizeChanged pane=\(id) \(cols)x\(rows)")
///     TermQLogger.pane.info("Border updated pane=\(id) active=\(isActive)")
///     TermQLogger.focus.warning("makeFirstResponder called on nil window")
///     TermQLogger.session.error("connect() failed: \(error)")
///
enum TermQLogger {

    // MARK: - Category Loggers

    /// tmux control mode protocol: resize, layout changes, pane output, commands
    static let tmux = CategoryLogger(category: "tmux")

    /// Pane lifecycle: creation, layout, border updates, cleanup
    static let pane = CategoryLogger(category: "pane")

    /// Terminal session lifecycle: connect, disconnect, backend switching
    static let session = CategoryLogger(category: "session")

    /// Keyboard focus: first responder, tab switching, click-to-focus
    static let focus = CategoryLogger(category: "focus")

    /// Input/output routing: key events, pane output, send-keys
    static let io = CategoryLogger(category: "io")

    /// SwiftUI/AppKit view lifecycle: appear, disappear, layout passes
    static let ui = CategoryLogger(category: "ui")

    /// Window lifecycle: creation, close, delegate assignment, count changes
    static let window = CategoryLogger(category: "window")

    // MARK: - File Logging

    /// True when TERMQ_DEBUG is set in the environment. Evaluated once at
    /// launch so the check is free in the hot path.
    static let fileLoggingEnabled: Bool =
        ProcessInfo.processInfo.environment["TERMQ_DEBUG"] != nil

    private static let logPath = "/tmp/termq-debug.log"
    private static let fileQueue = DispatchQueue(
        label: "net.eyelock.termq.logger",
        qos: .utility
    )
    // Access is serialised through fileQueue — the nonisolated(unsafe) annotation
    // documents that external synchronisation (the serial queue) protects this.
    nonisolated(unsafe) private static var logFileReady = false

    fileprivate static func writeToFile(category: String, level: String, message: String) {
        guard fileLoggingEnabled else { return }
        fileQueue.async {
            if !logFileReady {
                // Truncate on first write — each launch gets a fresh log
                try? "".write(toFile: logPath, atomically: false, encoding: .utf8)
                logFileReady = true
            }
            let ts = String(format: "%.3f", Date().timeIntervalSince1970)
            let line = "\(ts) [\(category)\(level.isEmpty ? "" : ":\(level)")] \(message)\n"
            if let data = line.data(using: .utf8),
                let handle = FileHandle(forWritingAtPath: logPath)
            {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        }
    }

    // MARK: - CategoryLogger

    struct CategoryLogger {
        let category: String
        private let osLog: Logger

        init(category: String) {
            self.category = category
            self.osLog = Logger(subsystem: "net.eyelock.termq", category: category)
        }

        /// Fine-grained diagnostic detail. Use for high-frequency events like
        /// sizeChanged, output bytes, or layout calculations.
        func debug(_ message: String) {
            osLog.debug("\(message, privacy: .public)")
            TermQLogger.writeToFile(category: category, level: "", message: message)
            TermQLogBuffer.shared.append(level: .debug, category: category, message: message)
        }

        /// Noteworthy state changes that help trace the happy path: session
        /// connected, pane added, focus granted.
        func info(_ message: String) {
            osLog.info("\(message, privacy: .public)")
            TermQLogger.writeToFile(category: category, level: "info", message: message)
            TermQLogBuffer.shared.append(level: .info, category: category, message: message)
        }

        /// Important lifecycle events that should appear in `log stream` without
        /// extra flags. Maps to os_log `.notice` (the "default" level).
        /// Use for low-volume events you always want visible: window creation,
        /// app lifecycle transitions.
        func notice(_ message: String) {
            osLog.notice("\(message, privacy: .public)")
            TermQLogger.writeToFile(category: category, level: "notice", message: message)
            TermQLogBuffer.shared.append(level: .notice, category: category, message: message)
        }

        /// Unexpected but recoverable situations: missing pane in parser, skipped
        /// resize, delegate called on nil.
        func warning(_ message: String) {
            osLog.warning("\(message, privacy: .public)")
            TermQLogger.writeToFile(category: category, level: "warn", message: message)
            TermQLogBuffer.shared.append(level: .warning, category: category, message: message)
        }

        /// Failures that affect functionality: connect threw, process died,
        /// invariant violated.
        func error(_ message: String) {
            osLog.error("\(message, privacy: .public)")
            TermQLogger.writeToFile(category: category, level: "error", message: message)
            TermQLogBuffer.shared.append(level: .error, category: category, message: message)
        }
    }
}
