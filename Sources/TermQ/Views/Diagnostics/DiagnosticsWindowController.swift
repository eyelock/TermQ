import AppKit
import SwiftUI

@MainActor
final class DiagnosticsWindowController: NSWindowController {
    static let shared = DiagnosticsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Strings.Diagnostics.windowTitle
        window.center()
        window.contentView = NSHostingView(rootView: DiagnosticsView())
        window.setFrameAutosaveName("DiagnosticsWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
