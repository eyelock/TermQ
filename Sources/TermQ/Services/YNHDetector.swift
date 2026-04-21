import Foundation
import TermQShared

/// Detection status for the YNH toolchain.
///
/// Drives sidebar visibility and placeholder content:
/// - `.missing` → hide the Harnesses tab entirely
/// - `.binaryOnly` → show tab with "Run `ynh init`" CTA
/// - `.ready` → show tab with harness list (Phase 2+)
enum YNHStatus: Equatable, Sendable {
    /// Neither `ynh` nor `ynd` found on `$PATH`.
    case missing
    /// `ynh` binary found but `ynh paths` failed (not initialised or broken config).
    case binaryOnly(ynhPath: String)
    /// `ynh paths` succeeded — toolchain is fully operational.
    case ready(ynhPath: String, yndPath: String?, paths: YNHPaths)
}

/// Detects and caches the YNH toolchain status.
///
/// Modelled as a `@MainActor` singleton (same pattern as `GitService`).
/// Detection runs as an async subprocess; the cached result drives the sidebar
/// tab visibility via `HarnessesSidebarViewModel`.
@MainActor
final class YNHDetector: ObservableObject {
    static let shared = YNHDetector()

    @Published private(set) var status: YNHStatus = .missing
    @Published private(set) var version: String?

    /// UserDefaults key for the `$YNH_HOME` override set in TermQ settings.
    private static let ynhHomeOverrideKey = "ynh.homeOverride"

    /// The `$YNH_HOME` override configured in settings, or `nil` for default.
    var ynhHomeOverride: String? {
        get {
            let value = UserDefaults.standard.string(forKey: Self.ynhHomeOverrideKey)
            return (value?.isEmpty ?? true) ? nil : value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.ynhHomeOverrideKey)
        }
    }

    private init() {}

    // MARK: - Detection

    /// Run detection and update `status`.
    ///
    /// Call on app launch and when the user changes the `$YNH_HOME` override.
    func detect() async {
        guard let ynhPath = findBinary("ynh") else {
            status = .missing
            version = nil
            return
        }

        let yndPath = findBinary("ynd")

        // Fetch version (best-effort — don't fail detection if this errors).
        if let raw = try? await Self.runCommand(ynhPath, args: ["version"]) {
            version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            version = nil
        }

        // Build environment for the subprocess, injecting YNH_HOME if overridden.
        var env = ProcessInfo.processInfo.environment
        if let override = ynhHomeOverride {
            env["YNH_HOME"] = override
        }

        do {
            let json = try await Self.runCommand(
                ynhPath,
                args: ["paths", "--format", "json"],
                environment: env
            )
            let paths = try JSONDecoder().decode(YNHPaths.self, from: Data(json.utf8))
            status = .ready(ynhPath: ynhPath, yndPath: yndPath, paths: paths)
        } catch {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.ui.info("YNHDetector: ynh paths failed error=\(error)")
            } else {
                TermQLogger.ui.info("YNHDetector: ynh paths failed")
            }
            status = .binaryOnly(ynhPath: ynhPath)
        }
    }

    // MARK: - Binary Discovery

    /// Search common install locations for a named binary.
    ///
    /// macOS GUI apps don't inherit the user's shell `$PATH`, so we check
    /// well-known locations explicitly. The list includes ynh's own managed
    /// bin directory (`~/.ynh/bin/`) which is the default install location.
    private func findBinary(_ name: String) -> String? {
        let home = NSHomeDirectory()

        var candidates = [String]()

        // If the user set a YNH_HOME override, its bin/ takes priority.
        if let override = ynhHomeOverride, !override.isEmpty {
            candidates.append("\(override)/bin/\(name)")
        }

        // ynh's default self-managed bin directory
        candidates.append("\(home)/.ynh/bin/\(name)")

        // Standard system locations
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/opt/local/bin/\(name)",
        ])

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Subprocess

    /// Run a command and return its stdout. Throws on non-zero exit.
    static func runCommand(
        _ executable: String,
        args: [String],
        environment: [String: String]? = nil
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.standardOutput = stdout
                process.standardError = stderr
                if let environment {
                    process.environment = environment
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
                        continuation.resume(
                            throwing: YNHDetectionError.commandFailed(
                                exitCode: process.terminationStatus,
                                stderr: stderrStr
                            )
                        )
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Protocol Conformance

extension YNHDetector: YNHDetectorProtocol {}

// MARK: - Errors

enum YNHDetectionError: Error, LocalizedError, Sendable {
    case commandFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let exitCode, let stderr):
            return "ynh command failed (exit \(exitCode)): \(stderr)"
        }
    }
}
