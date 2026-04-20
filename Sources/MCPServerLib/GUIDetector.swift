import AppKit
import Foundation
import TermQShared

/// Detects if TermQ.app GUI is running
public enum GUIDetector {
    /// Override for tests — set to force headless (false) or GUI (true) mode without a running app.
    /// Never set in production code.
    /// Set in tests to force headless (false) or GUI (true) mode without a running app.
    /// Never set in production code.
    nonisolated(unsafe) public static var testModeOverride: Bool?

    /// Check if TermQ.app is currently running
    /// Uses NSWorkspace to query running applications by bundle identifier
    public static func isGUIRunning() -> Bool {
        if let override = testModeOverride { return override }
        return NSWorkspace.shared.runningApplications.contains {
            guard let bundleId = $0.bundleIdentifier else { return false }
            return AppProfile.allBundleIdentifiers.contains(bundleId)
        }
    }

    /// Wait for GUI to become available with timeout
    /// Useful for handling startup race conditions where GUI is launching
    /// - Parameter timeout: Maximum time to wait in seconds (default: 0.5)
    /// - Returns: true if GUI became available within timeout, false otherwise
    public static func waitForGUI(timeout: TimeInterval = 0.5) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if isGUIRunning() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }
        return false
    }
}
