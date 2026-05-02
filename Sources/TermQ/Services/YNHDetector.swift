import Foundation
import TermQShared

/// Detection status for the YNH toolchain.
///
/// Drives sidebar visibility and placeholder content:
/// - `.missing` → hide the Harnesses tab entirely
/// - `.binaryOnly` → show tab with "Run `ynh init`" CTA
/// - `.outdated` → show tab with "Upgrade YNH" CTA (capability version below minimum)
/// - `.ready` → show tab with harness list (Phase 2+)
enum YNHStatus: Equatable, Sendable {
    /// Neither `ynh` nor `ynd` found on `$PATH`.
    case missing
    /// `ynh` binary found but `ynh paths` failed (not initialised or broken config).
    case binaryOnly(ynhPath: String)
    /// `ynh` binary found and initialised, but its declared `capabilities` version
    /// is below `YNHDetector.minimumCapabilitiesVersion`. TermQ will refuse to issue
    /// marketplace/harness-editing commands against it because the wire contract
    /// (e.g. canonical pick form) is not yet supported.
    case outdated(ynhPath: String, version: String?, capabilities: String?)
    /// `ynh paths` succeeded and capabilities meet the minimum — toolchain is fully operational.
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
    @Published private(set) var capabilities: String?

    /// The wire-contract version of YNH that this build of TermQ is tested against.
    ///
    /// Bumped when TermQ starts relying on a YNH feature or contract change introduced
    /// in a new `CapabilitiesVersion`. Gating on this avoids writing harness configs
    /// that older YNH binaries cannot consume (e.g. canonical `type/name` picks).
    ///
    /// Can be *lowered* at runtime by setting the `TERMQ_YNH_CAPABILITIES_MIN_OVERRIDE`
    /// UserDefaults key — intended for developers testing against older YNH builds.
    /// Raising the gate via override is ignored (TermQ has not been tested above its
    /// built-in minimum).
    nonisolated static let minimumCapabilitiesVersion = "0.2.0"

    /// UserDefaults key for the dev override described on `minimumCapabilitiesVersion`.
    private static let capabilitiesMinOverrideKey = "TERMQ_YNH_CAPABILITIES_MIN_OVERRIDE"

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

        // Fetch version + capabilities via `ynh version --format json`. Older YNH
        // builds predate this flag — they print the plain version string instead,
        // which decodes as capabilities=nil and is treated as below-min below.
        (version, capabilities) = await Self.fetchVersionInfo(ynhPath: ynhPath)

        // Capability gate. Before any expensive path probe, confirm the binary
        // speaks a contract TermQ knows how to drive. If it doesn't, stop here
        // and surface an .outdated status so the UI can prompt for an upgrade.
        let minRequired = effectiveMinimumCapabilities()
        if !Self.capabilityMeets(capabilities, minimum: minRequired) {
            let reported = capabilities ?? "<none>"
            TermQLogger.ui.info(
                "YNHDetector: capabilities below minimum — disabled (reported \(reported), required \(minRequired))"
            )
            status = .outdated(ynhPath: ynhPath, version: version, capabilities: capabilities)
            return
        }

        // Build environment for the subprocess, injecting YNH_HOME if overridden.
        var env = ProcessInfo.processInfo.environment
        if let override = ynhHomeOverride {
            env["YNH_HOME"] = override
        }

        do {
            let result = try await CommandRunner.run(
                executable: ynhPath,
                arguments: ["paths", "--format", "json"],
                environment: env
            )
            guard result.didSucceed else {
                throw YNHDetectionError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
            }
            let paths = try JSONDecoder().decode(YNHPaths.self, from: Data(result.stdout.utf8))
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

    /// Return the active minimum capability version, honouring the dev UserDefaults
    /// override. Override can only *lower* the built-in minimum; raising it is
    /// ignored (TermQ has not been tested above `minimumCapabilitiesVersion`).
    private func effectiveMinimumCapabilities() -> String {
        let builtIn = Self.minimumCapabilitiesVersion
        guard
            let override = UserDefaults.standard.string(forKey: Self.capabilitiesMinOverrideKey),
            !override.isEmpty
        else {
            return builtIn
        }
        // Allow override only if it is <= built-in minimum.
        if Self.compareSemver(override, builtIn) <= 0 {
            TermQLogger.ui.info(
                "YNHDetector: capability minimum lowered to \(override) via override (built-in \(builtIn))"
            )
            return override
        }
        TermQLogger.ui.info(
            "YNHDetector: ignoring capability override \(override) — cannot raise above built-in minimum \(builtIn)"
        )
        return builtIn
    }

    /// Run `ynh version --format json` and parse the `{version, capabilities}` payload.
    /// Falls back to plain `ynh version` for older binaries that don't support the flag;
    /// in that case `capabilities` comes back `nil`.
    static func fetchVersionInfo(ynhPath: String) async -> (version: String?, capabilities: String?) {
        if let result = try? await CommandRunner.run(
            executable: ynhPath,
            arguments: ["version", "--format", "json"]
        ),
            result.didSucceed,
            let info = try? JSONDecoder().decode(VersionInfo.self, from: Data(result.stdout.utf8))
        {
            return (info.version, info.capabilities)
        }
        // Pre-capability binary: best-effort plain version, no capability claim.
        if let result = try? await CommandRunner.run(executable: ynhPath, arguments: ["version"]),
            result.didSucceed
        {
            return (result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        return (nil, nil)
    }

    /// Test whether `reported` satisfies `minimum` using 3-segment semver comparison.
    /// A `nil` or unparseable `reported` always fails (treat pre-capability YNH as below-min).
    nonisolated static func capabilityMeets(_ reported: String?, minimum: String) -> Bool {
        guard let reported else { return false }
        return compareSemver(reported, minimum) >= 0
    }

    /// Compare two semver-ish version strings segment-by-segment. Non-numeric segments
    /// compare as zero. Missing trailing segments compare as zero (so "0.2" == "0.2.0").
    /// Returns -1 if lhs < rhs, 0 if lhs == rhs, 1 if lhs > rhs.
    nonisolated static func compareSemver(_ lhs: String, _ rhs: String) -> Int {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhsParts.count, rhsParts.count)
        for i in 0..<count {
            let lv = i < lhsParts.count ? lhsParts[i] : 0
            let rv = i < rhsParts.count ? rhsParts[i] : 0
            if lv < rv { return -1 }
            if lv > rv { return 1 }
        }
        return 0
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
}

// MARK: - Protocol Conformance

extension YNHDetector: YNHDetectorProtocol {}

// MARK: - Supporting types

/// Decoded payload of `ynh version --format json`.
private struct VersionInfo: Decodable {
    let version: String?
    let capabilities: String?
}

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
