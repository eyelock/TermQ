import Foundation

/// Coordinates the top-level Repositories / Harnesses / Marketplaces menu
/// commands that need to drive sheet-backed flows owned by the sidebar tab
/// views.
///
/// Each tab view presents its Add / Create / Install sheets from local `@State`,
/// and only the selected tab's view is mounted at a time, so a menu command
/// cannot toggle that state directly. Instead the command records a `pending`
/// request and switches `SidebarState` to the owning tab; the tab view consumes
/// the request from its `onChange(of:initial:)` — which fires both when the tab
/// is freshly mounted by the switch and when it is already frontmost — then
/// clears it. Mirrors `SettingsCoordinator`'s request / clear pattern.
@MainActor
final class SidebarMenuCoordinator: ObservableObject {
    static let shared = SidebarMenuCoordinator()

    /// A menu-triggered request awaiting consumption by the owning tab view.
    enum Request: Equatable {
        case addRepository
        case createHarness
        case installHarness
        case addMarketplace
        case refreshMarketplaces
        case restoreDefaultMarketplaces
    }

    @Published var pending: Request?

    private init() {}

    /// Switch to `tab` (revealing the sidebar if collapsed) and record `request`
    /// for that tab's view to consume.
    func request(_ request: Request, on tab: SidebarTab) {
        // Ensure the sidebar is visible so the owning tab view is mounted to
        // consume the request (mirrors ContentView's @AppStorage key).
        UserDefaults.standard.set(false, forKey: SidebarState.sidebarCollapsedKey)
        SidebarState.shared.selectedTab = tab
        pending = request
    }

    /// If `request` is the one pending, clear it and return `true` so the caller
    /// acts on it exactly once.
    func consume(_ request: Request) -> Bool {
        guard pending == request else { return false }
        pending = nil
        return true
    }
}
