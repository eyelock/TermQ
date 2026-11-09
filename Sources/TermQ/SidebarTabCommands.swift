import SwiftUI

/// View menu items that pick a sidebar tab: ⌃⌘ plus the tab's first letter
/// (R, H, M, W). Each shows the sidebar if it was collapsed. Digits are kept
/// free for the Wheelhouse stage.
@MainActor
struct SidebarTabCommands: Commands {
    @AppStorage("feature.harnessTab") private var harnessTabEnabled = false
    @AppStorage("feature.wheelhouseTab") private var wheelhouseTabEnabled = false
    @ObservedObject private var detector: YNHDetector = .shared

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(SidebarTab.allCases, id: \.self) { tab in
                Button {
                    Self.activate(tab)
                } label: {
                    Label(tab.menuTitle, systemImage: tab.icon)
                }
                .keyboardShortcut(KeyEquivalent(tab.shortcutKey), modifiers: [.command, .control])
                .disabled(
                    !tab.isAvailable(
                        harnessTabEnabled: harnessTabEnabled, ynhMissing: detector.status == .missing,
                        wheelhouseTabEnabled: wheelhouseTabEnabled))
            }
        }
    }
}

extension SidebarTabCommands {
    /// Shows `tab` in the sidebar. Asking for another tab leaves Wheelhouse
    /// focus mode, which shows only the Wheelhouse.
    static func activate(
        _ tab: SidebarTab, sidebar: SidebarState = .shared, stage: WheelhouseStage = .shared
    ) {
        if tab != .wheelhouses { stage.focusMode = false }
        sidebar.reveal(tab)
    }
}

extension SidebarTab {
    /// The tab's localized name for menus.
    var menuTitle: String {
        switch self {
        case .repositories: return Strings.Menu.workspaceRepositories
        case .harnesses: return Strings.Menu.workspaceHarnesses
        case .marketplaces: return Strings.Menu.workspaceMarketplaces
        case .wheelhouses: return Strings.Wheelhouse.title
        }
    }
}
