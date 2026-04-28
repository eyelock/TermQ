import AppKit
import Foundation
import SwiftTerm

/// Pure resolution of a terminal-detected link string into an actionable
/// outcome. Has no side effects and no UI — call sites in
/// `TerminalSessionManager` apply the result via `NSWorkspace`/`AlertBuilder`.
enum TerminalLinkAction: Equatable {
    /// Open a remote URL (http/https) with the default browser.
    case openURL(URL)
    /// Open a local file with the registered default application.
    case openFile(URL)
    /// File doesn't exist — reveal it in Finder rooted at the nearest
    /// existing parent directory.
    case revealInFinder(file: URL, root: URL)
    /// Couldn't resolve to a path; hand back to the caller as a plain string
    /// for default-handler behaviour.
    case fallbackString(String)
    /// Nothing to do (empty/whitespace-only payload).
    case noop
}

enum TerminalLinkResolver {

    /// Strip whitespace and trailing punctuation that SwiftTerm's implicit
    /// link regex can capture (`)`, `]`, `}`, `:`, `.`, line-wrap whitespace,
    /// etc.) so the resolved path matches what's actually on disk.
    static func sanitize(_ link: String) -> String {
        let trimSet = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".,;:!?)]}>\""))
        var result = link.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = result.unicodeScalars.last, trimSet.contains(last) {
            result.removeLast()
        }
        return result
    }

    /// Resolve a raw link payload against the optional current working
    /// directory and a file-existence predicate.
    static func resolve(
        link: String,
        cwd: String?,
        fileExists: (String) -> Bool
    ) -> TerminalLinkAction {
        let trimmed = sanitize(link)
        guard !trimmed.isEmpty else { return .noop }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let url = URL(string: trimmed) { return .openURL(url) }
            return .fallbackString(trimmed)
        }

        let resolvedPath: String
        if trimmed.hasPrefix("/") {
            resolvedPath = trimmed
        } else if let base = cwd {
            resolvedPath = (base as NSString).appendingPathComponent(trimmed)
        } else {
            return .fallbackString(trimmed)
        }

        let url = URL(fileURLWithPath: resolvedPath).standardized
        if fileExists(url.path) {
            return .openFile(url)
        }

        var parent = url.deletingLastPathComponent()
        while !fileExists(parent.path) && parent.path != "/" {
            parent = parent.deletingLastPathComponent()
        }
        return .revealInFinder(file: url, root: parent)
    }
}

/// Single entry point for terminal link clicks across all `TerminalViewDelegate`
/// implementations in the project (direct sessions, tmux control-mode panes,
/// and any future surfaces).
///
/// **Wiring rule:** every `TerminalViewDelegate` we author must implement
/// `requestOpenLink` and route it here. SwiftTerm's protocol-default opens
/// the raw payload via `URL(string:)` + `NSWorkspace.shared.open`, which
/// produces the macOS "-50" Finder dialog for absolute paths. Skipping this
/// step silently regresses to that default — see `TerminalLinkRoutingTests`.
@MainActor
enum TermQTerminalLink {

    /// Resolves a terminal-detected link via `TerminalLinkResolver` and
    /// applies the resulting action through `NSWorkspace`.
    static func open(link: String, cwd: String?) {
        TermQLogger.ui.debug("TermQTerminalLink.open raw=\(link) cwd=\(cwd ?? "<nil>")")
        let action = TerminalLinkResolver.resolve(
            link: link,
            cwd: cwd,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
        switch action {
        case .noop:
            return
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .fallbackString(let string):
            if let url = URL(string: string) { NSWorkspace.shared.open(url) }
        case .revealInFinder(_, let root):
            // file doesn't exist; selectFile silently fails for missing paths.
            // Open the nearest existing parent instead so Finder shows something useful.
            NSWorkspace.shared.open(root)
        case .openFile(let url):
            openFileWithDefaultApp(url)
        }
    }

    /// Opens `url` with its registered default application, surfacing a
    /// friendly alert instead of the macOS "-50" Finder dialog when
    /// LaunchServices has no handler or the launch attempt fails.
    private static func openFileWithDefaultApp(_ url: URL) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            NSWorkspace.shared.open(url)
            return
        }

        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            TermQLogger.ui.info("TermQTerminalLink no default handler path=\(url.path)")
            presentNoHandlerAlert(for: url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: handler, configuration: configuration) {
            _, error in
            guard let error else { return }
            Task { @MainActor in
                TermQLogger.ui.warning(
                    "TermQTerminalLink launch failed path=\(url.path) error=\(error.localizedDescription)"
                )
                presentOpenFailedAlert(for: url, error: error)
            }
        }
    }

    private static func presentNoHandlerAlert(for url: URL) {
        let revealed = AlertBuilder.confirm(
            title: Strings.Alert.FileOpen.noHandlerTitle,
            message: Strings.Alert.FileOpen.noHandlerMessage(url.lastPathComponent),
            confirmButton: Strings.Alert.FileOpen.revealInFinder,
            style: .informational
        )
        if revealed {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private static func presentOpenFailedAlert(for url: URL, error: Error) {
        let revealed = AlertBuilder.confirm(
            title: Strings.Alert.FileOpen.failedTitle,
            message: Strings.Alert.FileOpen.failedMessage(
                error: error.localizedDescription, filename: url.lastPathComponent
            ),
            confirmButton: Strings.Alert.FileOpen.revealInFinder,
            style: .warning
        )
        if revealed {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
