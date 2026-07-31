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

/// Spawns provider subprocesses with non-interactivity enforced at the spawn site.
///
/// Shared by every `StackProvider` on purpose. git-spice guarantees it will not prompt
/// because TermQ passes `--no-prompt` on every call; gh-stack offers no such flag and
/// instead decides interactivity by sniffing for a TTY. Relying on each provider to
/// remember the right flags makes a hung subprocess one forgotten argument away, so the
/// guarantee lives here instead: stdin is always closed, so anything that asks whether it
/// is interactive is told no.
public enum StackProcessRunner {
    /// Run `executable` and collect its output.
    ///
    /// - Parameter env: merged over the inherited environment. Used to neutralize pagers,
    ///   colour, and prompt behaviour that would otherwise block or corrupt parsing.
    public static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: String?,
        env: [String: String] = [:]
    ) async throws -> StackProcessResult {
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

                // Read before waiting: a child that fills a pipe buffer blocks on write
                // while we block on exit. gh-stack's JSON output is small today, but
                // deadlocking on a verbose future release is not a risk worth carrying.
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                continuation.resume(
                    returning: StackProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: outData, encoding: .utf8) ?? "",
                        stderr: String(data: errData, encoding: .utf8) ?? ""
                    ))
            }
        }
    }
}
