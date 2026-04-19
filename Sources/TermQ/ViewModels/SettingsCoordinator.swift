import Foundation
import SwiftUI

/// Coordinates Settings window navigation and tab selection
@MainActor
final class SettingsCoordinator: ObservableObject {
    static let shared = SettingsCoordinator()

    @Published var requestedTab: SettingsView.SettingsTab?

    private init() {}

    /// Request navigation to a specific Settings tab.
    ///
    /// Callers are responsible for also opening the Settings window (e.g. via
    /// `@Environment(\.openSettings)` or a `SettingsLink`).
    func openSettings(tab: SettingsView.SettingsTab) {
        requestedTab = tab
    }

    /// Clear the requested tab after it's been handled
    func clearRequest() {
        requestedTab = nil
    }
}
