import Foundation

/// The three top-level tabs in the sidebar. Promoted out of `SidebarView` so
/// that other views (HarnessWizardSheet, HarnessDetailView, etc.) can drive
/// the selection through `SidebarState` without needing the View itself.
enum SidebarTab: String, CaseIterable, Sendable {
    case repositories
    case harnesses
    case marketplaces
    case wheelhouses

    var icon: String {
        switch self {
        case .repositories: return "shippingbox"
        case .harnesses: return "puzzlepiece.extension"
        case .marketplaces: return "storefront"
        case .wheelhouses: return "steeringwheel"
        }
    }

    /// The letter that, with ⌃⌘, selects this tab: its name's first letter.
    var shortcutKey: Character {
        switch self {
        case .repositories: return "r"
        case .harnesses: return "h"
        case .marketplaces: return "m"
        case .wheelhouses: return "w"
        }
    }

    /// Whether the tab is shown for the enabled features: Harnesses and
    /// Marketplaces need the Harnesses tab on and ynh present, Wheelhouses its
    /// own tab on.
    func isAvailable(harnessTabEnabled: Bool, ynhMissing: Bool, wheelhouseTabEnabled: Bool) -> Bool {
        switch self {
        case .repositories: return true
        case .harnesses, .marketplaces: return harnessTabEnabled && !ynhMissing
        case .wheelhouses: return wheelhouseTabEnabled
        }
    }

    var label: String {
        switch self {
        case .repositories: return "Repositories"
        case .harnesses: return "Harnesses"
        case .marketplaces: return "Marketplaces"
        case .wheelhouses: return "Wheelhouses"
        }
    }
}

/// Owns the currently-selected sidebar tab. Three views previously coordinated
/// via the same `@AppStorage("sidebar.selectedTab")` key, which made
/// cross-view navigation fragile (e.g. a writer using a raw string that
/// happened to match a `SidebarTab` rawValue). Centralising publishes the
/// state and removes the string typing.
@MainActor
final class SidebarState: ObservableObject {
    static let shared = SidebarState()

    /// UserDefaults key backing ContentView's sidebar-collapsed `@AppStorage`,
    /// written by `reveal(_:)` to show the sidebar.
    static let sidebarCollapsedKey = "sidebarCollapsed"

    private let defaults: UserDefaults
    private static let selectedTabKey = "sidebar.selectedTab"

    @Published var selectedTab: SidebarTab {
        didSet { defaults.set(selectedTab.rawValue, forKey: Self.selectedTabKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.selectedTabKey) ?? SidebarTab.repositories.rawValue
        self.selectedTab = SidebarTab(rawValue: raw) ?? .repositories
    }

    /// Selects `tab` and shows the sidebar if it was collapsed: what the
    /// ⌃⌘R/H/M/W shortcuts do.
    func reveal(_ tab: SidebarTab) {
        defaults.set(false, forKey: Self.sidebarCollapsedKey)
        selectedTab = tab
    }
}
