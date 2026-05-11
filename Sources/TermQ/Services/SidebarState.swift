import Foundation

/// The three top-level tabs in the sidebar. Promoted out of `SidebarView` so
/// that other views (HarnessWizardSheet, HarnessDetailView, etc.) can drive
/// the selection through `SidebarState` without needing the View itself.
enum SidebarTab: String, CaseIterable, Sendable {
    case repositories
    case harnesses
    case marketplaces

    var icon: String {
        switch self {
        case .repositories: return "shippingbox"
        case .harnesses: return "puzzlepiece.extension"
        case .marketplaces: return "storefront"
        }
    }

    var label: String {
        switch self {
        case .repositories: return "Repositories"
        case .harnesses: return "Harnesses"
        case .marketplaces: return "Marketplaces"
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
}
