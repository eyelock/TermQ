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
        // Store reference to the main window and set delegate
        // In SwiftUI apps, the window might not be created yet, so we poll for it
        setupMainWindowDelegate()
    }

    private func setupMainWindowDelegate() {
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
            windowVisibilityObservation = nil
            mainWindow = window
            window.delegate = self
            window.tabbingMode = .disallowed
            windowVisibilityObservation = window.observe(\.isVisible, options: [.new, .old]) { _, change in
                guard change.oldValue == true, change.newValue == false else { return }
                let stack = Thread.callStackSymbols.prefix(32).joined(separator: "\n  ")
                TermQLogger.window.notice("mainWindow isVisible true→false — stack:\n  \(stack)")
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
        let windows = NSApplication.shared.windows
        let appHidden = NSApp.isHidden
        TermQLogger.window.notice(
            "applicationShouldHandleReopen: hasVisibleWindows=\(flag) isAppHidden=\(appHidden) total=\(windows.count)"
        )
        for (i, win) in windows.enumerated() {
            let desc = "\(type(of: win)) visible=\(win.isVisible) frame=\(win.frame)"
            TermQLogger.window.notice("  window[\(i)]: \(desc)")
        }
        if let window = mainWindow {
            // Only call unhide if the app is actually hidden (e.g. from windowShouldClose → NSApp.hide).
            // Calling unhide on a non-hidden app schedules a deferred _doOrderWindow orderOut block that
            // fires when the run loop returns to NSDefaultRunLoopMode — which a busy terminal defers for
            // seconds or minutes, producing the "spontaneous" window hide.
            if NSApp.isHidden {
                NSApp.unhide(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return false
        }
        // No main window tracked yet — allow the system to open one
        return true
    }

    /// Log when the app is about to hide (Cmd+H, "Hide TermQ" menu, or external caller).
    /// The call stack reveals whether this is user-initiated or driven by an external tool.
    func applicationWillHide(_ notification: Notification) {
        let stack = Thread.callStackSymbols.prefix(32).joined(separator: "\n  ")
        TermQLogger.window.notice("applicationWillHide triggered — stack:\n  \(stack)")
    }

    /// Log when the window is about to miniaturize so we can diagnose spontaneous occurrences.
    /// The call stack captured here will reveal whether it's Cmd+M, an external tool, or macOS.
    func windowWillMiniaturize(_ notification: Notification) {
        let stack = Thread.callStackSymbols.prefix(32).joined(separator: "\n  ")
        TermQLogger.window.notice("windowWillMiniaturize triggered — stack:\n  \(stack)")
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
