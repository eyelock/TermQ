import Foundation

/// Where a harness source tree keeps its manifest directory.
///
/// Mirrors YNH's `plugin.ManifestDir`: the canonical `.agents/harness/` is
/// checked first, the deprecated `.ynh-plugin/` second. YNH 0.14+ refuses a
/// tree that only has the legacy directory (the fix is `ynd migrate`) and a
/// tree that has both; TermQ keeps reading the legacy layout so it can flag it
/// instead of pretending the harness does not exist.
public enum HarnessManifestLayout {
    /// Canonical manifest directory, relative to the harness root.
    public static let canonicalDir = ".agents/harness"
    /// Deprecated manifest directory, relative to the harness root. Nothing
    /// in TermQ ever creates files here.
    public static let legacyDir = ".ynh-plugin"
    /// `.agents/` also holds unrelated content (Codex skills and plugins),
    /// so it must never be treated as a harness-owned directory.
    public static let agentsDir = ".agents"
    public static let manifestFile = "plugin.json"
    public static let installedFile = "installed.json"

    public enum State: Equatable, Sendable {
        /// Only `.agents/harness/plugin.json`.
        case canonical
        /// Only `.ynh-plugin/plugin.json` — YNH 0.14+ refuses it.
        case legacy
        /// Both exist — YNH 0.14+ refuses it, and `ynd migrate` leaves it alone.
        case both
    }

    public struct Resolution: Equatable, Sendable {
        public let state: State
        /// Manifest directory actually used for reading (canonical wins),
        /// relative to the harness root.
        public var dir: String {
            state == .legacy ? HarnessManifestLayout.legacyDir : HarnessManifestLayout.canonicalDir
        }
        /// True when YNH 0.14+ would refuse the tree as it stands.
        public var needsAttention: Bool { state != .canonical }
    }

    /// Resolve the layout of the harness rooted at `path`, or nil when
    /// neither directory holds a `plugin.json`.
    public static func resolve(at path: String) -> Resolution? {
        let root = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        let hasCanonical = fileManager.fileExists(
            atPath: root.appendingPathComponent(canonicalDir).appendingPathComponent(manifestFile).path)
        let hasLegacy = fileManager.fileExists(
            atPath: root.appendingPathComponent(legacyDir).appendingPathComponent(manifestFile).path)
        switch (hasCanonical, hasLegacy) {
        case (true, true): return Resolution(state: .both)
        case (true, false): return Resolution(state: .canonical)
        case (false, true): return Resolution(state: .legacy)
        case (false, false): return nil
        }
    }

    /// URL of the manifest that reads should use (canonical first), or nil
    /// when the tree has none.
    public static func manifestURL(at path: String) -> URL? {
        resolve(at: path).map {
            URL(fileURLWithPath: path).appendingPathComponent($0.dir).appendingPathComponent(manifestFile)
        }
    }

    /// Manifest directory for writes: whichever layout already holds the
    /// manifest (never silently moved), canonical when there is none.
    public static func writeDir(at path: String) -> String {
        resolve(at: path)?.dir ?? canonicalDir
    }

    /// True when either manifest *directory* exists at `path`, with or
    /// without a `plugin.json` inside — the looser "this is a harness dir"
    /// marker used to guard wholesale replacement.
    public static func hasManifestDir(at path: String) -> Bool {
        let root = URL(fileURLWithPath: path)
        return [canonicalDir, legacyDir].contains { dir in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: root.appendingPathComponent(dir).path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }
}
