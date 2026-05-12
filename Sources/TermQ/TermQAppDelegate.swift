import AppKit
import Combine
import Sparkle
import SwiftUI
import TermQCore
import TermQShared

/// App delegate to handle quit confirmation, auto-updates, and enforce single window
@MainActor
class TermQAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Sparkle updater delegate for dynamic feed URL
    private let sparkleDelegate = SparkleUpdaterDelegate()

    /// Sparkle updater controller for automatic updates
    let updaterController: SPUStandardUpdaterController

    /// Updater view model for SwiftUI
    let updaterViewModel: UpdaterViewModel

    /// Reference to the main window (first window created)
    private var mainWindow: NSWindow?

    /// KVO token tracking main window visibility; non-nil while observing
    private var windowVisibilityObservation: NSKeyValueObservation?

    override init() {
        // Initialize Sparkle updater with delegate for dynamic feed URL
        // SUPublicEDKey is read from Info.plist
        // Debug builds must not start the updater — it hits the production appcast,
        // finds a "newer" version, and can wake the release app via Launch Services.
        #if TERMQ_DEBUG_BUILD
            let startUpdater = false
        #else
            let startUpdater = true
        #endif
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startUpdater,
            updaterDelegate: sparkleDelegate,
            userDriverDelegate: nil
        )
        updaterViewModel = UpdaterViewModel(
            updater: updaterController.updater,
            controller: updaterController
        )
        super.init()
        #if TERMQ_DEBUG_BUILD
            TermQLogger.window.notice("TermQAppDelegate.init: Sparkle updater disabled (debug build)")
        #else
            TermQLogger.window.notice("TermQAppDelegate.init: Sparkle updater initialized")
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        EditorRegistry.shared.start()
        // Prevent macOS from auto-tabbing windows (e.g. when "Prefer tabs" is set in System Settings)
        NSWindow.allowsAutomaticWindowTabbing = false
        // Log window state at launch to detect unexpected pre-existing windows
        let windows = NSApplication.shared.windows
        TermQLogger.window.notice("applicationDidFinishLaunching: \(windows.count) window(s)")
        for (i, win) in windows.enumerated() {
            let desc = "\(type(of: win)) visible=\(win.isVisible) frame=\(win.frame)"
            TermQLogger.window.notice("  window[\(i)]: \(desc)")
        }
        // Override SwiftUI's kAEGetURL handler, which SwiftUI registers during scene setup
        // (after our App.init runs). Registering here ensures our handler wins and prevents
        // SwiftUI's AppWindowsController from hiding the main window on every URL open.
        NSAppleEventManager.shared().setEventHandler(
            URLEventHandler.shared,
            andSelector: #selector(URLEventHandler.handleURL(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        registerLifecycleObservers()
        // Store reference to the main window and set delegate
        // In SwiftUI apps, the window might not be created yet, so we poll for it
        setupMainWindowDelegate()
    }

    // MARK: - Lifecycle diagnostics

    /// Subscribe to every NSApp/NSWindow transition so we can diagnose stealing-focus,
    /// spontaneous-hide, and spontaneous-miniaturize reports without adding new logging
    /// each time. Each event is recorded with a state snapshot + stack via `logLifecycle`.
    private func registerLifecycleObservers() {
        let nc = NotificationCenter.default
        let appEvents: [(Notification.Name, String)] = [
            (NSApplication.willBecomeActiveNotification, "app.willBecomeActive"),
            (NSApplication.didBecomeActiveNotification, "app.didBecomeActive"),
            (NSApplication.willResignActiveNotification, "app.willResignActive"),
            (NSApplication.didResignActiveNotification, "app.didResignActive"),
            (NSApplication.didHideNotification, "app.didHide"),
            (NSApplication.didUnhideNotification, "app.didUnhide"),
        ]
        for (name, label) in appEvents {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.logLifecycle(label)
                }
            }
        }
        let windowEvents: [(Notification.Name, String)] = [
            (NSWindow.didBecomeKeyNotification, "win.didBecomeKey"),
            (NSWindow.didResignKeyNotification, "win.didResignKey"),
            (NSWindow.didBecomeMainNotification, "win.didBecomeMain"),
            (NSWindow.didResignMainNotification, "win.didResignMain"),
            (NSWindow.didMiniaturizeNotification, "win.didMiniaturize"),
            (NSWindow.didDeminiaturizeNotification, "win.didDeminiaturize"),
        ]
        for (name, label) in windowEvents {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let objectID = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self,
                        let mainID = self.mainWindow.map({ ObjectIdentifier($0 as AnyObject) }),
                        objectID == mainID
                    else { return }
                    self.logLifecycle(label)
                }
            }
        }
    }

    /// Single point of truth for lifecycle log formatting.
    /// Layout: `<event> | <state snapshot> \n  <stack frames>`.
    private func logLifecycle(_ event: String, withStack: Bool = true) {
        let stack =
            withStack
            ? "\n  " + Thread.callStackSymbols.dropFirst().prefix(24).joined(separator: "\n  ")
            : ""
        TermQLogger.window.notice("\(event) | \(lifecycleSnapshot())\(stack)")
    }

    private func lifecycleSnapshot() -> String {
        let app = NSApp
        let win = mainWindow
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        return
            "active=\(app?.isActive ?? false) hidden=\(app?.isHidden ?? false) "
            + "win.visible=\(win?.isVisible ?? false) win.key=\(win?.isKeyWindow ?? false) "
            + "win.main=\(win?.isMainWindow ?? false) win.min=\(win?.isMiniaturized ?? false) "
            + "frontmost=\(frontmost)"
    }

    private func setupMainWindowDelegate() {
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
            windowVisibilityObservation = nil
            mainWindow = window
            window.delegate = self
            window.tabbingMode = .disallowed
            windowVisibilityObservation = window.observe(\.isVisible, options: [.new, .old]) { [weak self] _, change in
                guard change.oldValue == true, change.newValue == false else { return }
                MainActor.assumeIsolated {
                    self?.logLifecycle("win.isVisible.true→false")
                }
            }
            let desc = "\(type(of: window)) frame=\(window.frame)"
            TermQLogger.window.notice("setupMainWindowDelegate: delegate set on \(desc)")
        } else {
            let total = NSApplication.shared.windows.count
            TermQLogger.window.notice("setupMainWindowDelegate: no visible window yet (total=\(total)), retrying")
            // Window not ready yet, try again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupMainWindowDelegate()
            }
        }

        // Handle cards created headless that need tmux sessions
        Task {
            await BoardViewModel.shared.handleHeadlessCards()
        }
    }

    /// Prevent creating new windows when user tries to open the app again
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        logLifecycle("app.shouldHandleReopen(hasVisibleWindows=\(flag))")
        if let window = mainWindow {
            // Reopen events fire not just on Dock clicks but on every AppleEvent URL
            // delivery (e.g. MCP-driven `termq://` opens with activates:false). Activating
            // the window unconditionally here causes TermQ to steal focus on every
            // background MCP operation. Only bring the window forward when there's
            // actually something to surface.
            if NSApp.isHidden {
                NSApp.unhide(nil)
                window.makeKeyAndOrderFront(nil)
            } else if window.isMiniaturized {
                window.deminiaturize(nil)
            } else if !flag {
                window.makeKeyAndOrderFront(nil)
            }
            return false
        }
        // No main window tracked yet — allow the system to open one
        return true
    }

    /// Intercept URL opens so SwiftUI's AppWindowsController never sees them.
    /// Without this, SwiftUI calls activateWindowForExternalEvent which closes the main window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            URLHandler.shared.handleURL(url)
        }
    }

    func applicationWillHide(_ notification: Notification) {
        logLifecycle("app.willHide")
    }

    func windowWillMiniaturize(_ notification: Notification) {
        logLifecycle("win.willMiniaturize")
    }

    /// Keep app running even if last window closes (user can reopen from Dock)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Handle window close button - show confirmation if terminals are running
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let desc = "\(type(of: sender)) frame=\(sender.frame)"
        TermQLogger.window.notice("windowShouldClose: \(desc)")
        // Check for running direct (non-tmux) sessions
        let sessionManager = TerminalSessionManager.shared
        let activeCards = sessionManager.activeSessionCardIds()

        // Count direct and tmux sessions separately
        let directSessionCount = activeCards.filter { cardId in
            sessionManager.getBackend(for: cardId) == .direct
        }.count

        let tmuxSessionCount = activeCards.filter { cardId in
            sessionManager.getBackend(for: cardId)?.usesTmux ?? false
        }.count

        if directSessionCount > 0 {
            let message =
                tmuxSessionCount > 0
                ? Strings.Alert.quitWithDirectSessionsMessageWithTmux(directSessionCount)
                : Strings.Alert.quitWithDirectSessionsMessage(directSessionCount)
            let confirmed = AlertBuilder.confirm(
                title: Strings.Alert.quitWithDirectSessions,
                message: message,
                confirmButton: Strings.Common.closeWindow,
                cancelButton: Strings.Common.cancel)
            if !confirmed { return false }
        }

        // Hide the app instead of closing — NSApp.hide(nil) preserves all state
        // cleanly. Clicking the Dock icon unhides everything.
        NSApp.hide(nil)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check for running direct (non-tmux) sessions
        let sessionManager = TerminalSessionManager.shared
        let activeCards = sessionManager.activeSessionCardIds()

        // Count direct and tmux sessions separately
        let directSessionCount = activeCards.filter { cardId in
            sessionManager.getBackend(for: cardId) == .direct
        }.count

        let tmuxSessionCount = activeCards.filter { cardId in
            sessionManager.getBackend(for: cardId)?.usesTmux ?? false
        }.count

        if directSessionCount > 0 {
            let message =
                tmuxSessionCount > 0
                ? Strings.Alert.quitWithDirectSessionsMessageWithTmux(directSessionCount)
                : Strings.Alert.quitWithDirectSessionsMessage(directSessionCount)
            let confirmed = AlertBuilder.confirm(
                title: Strings.Alert.quitWithDirectSessions,
                message: message,
                confirmButton: Strings.Common.quit,
                cancelButton: Strings.Common.cancel)
            if !confirmed { return .terminateCancel }
        }

        // Clean up all sessions before quitting
        sessionManager.removeAllSessions()
        return .terminateNow
    }
}
