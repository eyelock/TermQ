import AppKit
import Foundation

/// Injectable seam around `NSWorkspace.shared` for code that opens URLs,
/// reveals files in Finder, or queries LaunchServices for default
/// applications.
///
/// Production code uses `LiveWorkspaceProvider`. Tests inject a stub that
/// records calls without performing real workspace side effects — letting
/// `EditorRegistry` and `TermQTerminalLink` be exercised without launching
/// apps or talking to LaunchServices.
@MainActor
protocol WorkspaceProvider {
    @discardableResult
    func open(_ url: URL) -> Bool

    func urlForApplication(toOpen url: URL) -> URL?

    func urlForApplication(withBundleIdentifier identifier: String) -> URL?

    func activateFileViewerSelecting(_ urls: [URL])

    /// Opens `url` with the application at `appURL`. Completion is invoked
    /// on the main actor with the underlying `NSWorkspace` error (if any).
    func openFile(
        _ url: URL,
        withApplicationAt appURL: URL,
        completion: @escaping @MainActor @Sendable (Error?) -> Void
    )
}

/// Production provider: thin pass-through to `NSWorkspace.shared`.
@MainActor
struct LiveWorkspaceProvider: WorkspaceProvider {
    @discardableResult
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    func urlForApplication(toOpen url: URL) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    func urlForApplication(withBundleIdentifier identifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }

    func activateFileViewerSelecting(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openFile(
        _ url: URL,
        withApplicationAt appURL: URL,
        completion: @escaping @MainActor @Sendable (Error?) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) {
            @Sendable _, error in
            Task { @MainActor in completion(error) }
        }
    }
}
