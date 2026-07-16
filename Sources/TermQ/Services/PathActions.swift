import AppKit
import TermQShared

/// Shared `NSWorkspace`-backed actions for an arbitrary filesystem path. Used by both
/// the worktree sidebar context menu and the terminal selection context menu so the
/// two surfaces behave identically for the operations they have in common.
@MainActor
enum PathActions {
    static func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func openInTerminal(path: String) {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            TermQLogger.ui.error("openInTerminal: Terminal.app not found")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.addsToRecentItems = false
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: path)],
            withApplicationAt: terminalURL,
            configuration: config
        )
    }

    static func openIn(editor: ExternalEditor, path: String) {
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.addsToRecentItems = false
        NSWorkspace.shared.open([url], withApplicationAt: editor.appURL, configuration: config)
    }

    static func copyPathname(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}
