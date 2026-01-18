import Foundation
import SwiftUI

/// Coordinates Settings window navigation and tab selection
@MainActor
final class SettingsCoordinator: ObservableObject {
    static let shared = SettingsCoordinator()

    @Published var requestedTab: SettingsView.SettingsTab?

    private init() {}

    /// Request to open Settings with a specific tab
    func openSettings(tab: SettingsView.SettingsTab) {
        requestedTab = tab
    }

    /// Clear the requested tab after it's been handled
    func clearRequest() {
        requestedTab = nil
    }
}
