import AppKit
import Foundation

/// Detects if TermQ.app GUI is running
enum GUIDetector {
    /// Check if TermQ.app is currently running
    /// Uses NSWorkspace to query running applications by bundle identifier
    static func isGUIRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.eyelock.TermQ"
        }
    }

    /// Wait for GUI to become available with timeout
    /// Useful for handling startup race conditions where GUI is launching
    /// - Parameter timeout: Maximum time to wait in seconds (default: 0.5)
    /// - Returns: true if GUI became available within timeout, false otherwise
    static func waitForGUI(timeout: TimeInterval = 0.5) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if isGUIRunning() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }
        return false
    }
}
