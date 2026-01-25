import AppKit
import Foundation

/// Detects if TermQ.app GUI is running
public enum GUIDetector {
    /// Check if TermQ.app is currently running
    /// Uses NSWorkspace to query running applications by bundle identifier
    public static func isGUIRunning() -> Bool {
        let bundleIds = [
            "com.termq.app",                // Current bundle ID
            "com.termq.app.debug",          // Debug variant
            "net.eyelock.termq.app",        // Legacy production
            "net.eyelock.termq.app.debug",  // Legacy debug
            "com.eyelock.TermQ"             // Old bundle ID
        ]
        return NSWorkspace.shared.runningApplications.contains {
            guard let bundleId = $0.bundleIdentifier else { return false }
            return bundleIds.contains(bundleId)
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
