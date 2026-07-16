import Foundation

/// A terminal selection that resolved to a real, existing filesystem path.
struct ResolvedSelectionPath: Equatable {
    /// The exact path the selection resolved to — a file or a directory.
    let exactPath: String
    /// `exactPath` itself when it's a directory; otherwise its containing directory.
    /// Actions that need "somewhere to run" (Launch, Quick Terminal, Open in Terminal)
    /// use this; actions that need the precise target (Copy as Pathname, Open in editor)
    /// use `exactPath`.
    let directory: String
}

/// Pure resolution of a terminal text selection into an existing filesystem path.
///
/// Distinct from `TerminalLinkResolver`: that resolver drives click-to-open behavior
/// and falls back to revealing the nearest existing parent for a missing path. This
/// resolver backs the selection context menu, where a non-existent path should simply
/// not offer any path actions — no fallback.
enum TerminalSelectionPathResolver {

    /// Resolve `selection` against `cwd`, returning `nil` unless it names a path that
    /// actually exists on disk.
    static func resolve(
        selection: String,
        cwd: String?,
        fileExists: (String) -> Bool,
        isDirectory: (String) -> Bool
    ) -> ResolvedSelectionPath? {
        let trimmed = TerminalLinkResolver.sanitize(selection)
        guard !trimmed.isEmpty else { return nil }
        guard !(trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) else { return nil }

        let resolvedPath: String
        if trimmed.hasPrefix("/") {
            resolvedPath = trimmed
        } else if let cwd {
            resolvedPath = (cwd as NSString).appendingPathComponent(trimmed)
        } else {
            return nil
        }

        let url = URL(fileURLWithPath: resolvedPath).standardized
        guard fileExists(url.path) else { return nil }

        let directory = isDirectory(url.path) ? url.path : url.deletingLastPathComponent().path
        return ResolvedSelectionPath(exactPath: url.path, directory: directory)
    }

    /// Default-wired resolve using the real filesystem, mirroring `TermQTerminalLink.default`.
    static func resolveOnDisk(selection: String, cwd: String?) -> ResolvedSelectionPath? {
        resolve(
            selection: selection,
            cwd: cwd,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            isDirectory: { path in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            }
        )
    }
}
