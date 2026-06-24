import Foundation

// MARK: - Menu Commands — Top Menu additions
//
// New menu bar items added with the top-menu feature: Workspace submenu
// (Repositories / Harnesses / Marketplaces), Window jump-list helpers,
// View (zoom / tabs / palette), Edit (Find), and File (open / export /
// close / delete / bin). Pre-existing Menu entries remain in Strings.swift.

extension Strings.Menu {

    // MARK: Workspace menu

    static var workspace: String { localized("menu.workspace") }
    static var workspaceRepositories: String { localized("menu.workspace.repositories") }
    static var workspaceHarnesses: String { localized("menu.workspace.harnesses") }
    static var workspaceMarketplaces: String { localized("menu.workspace.marketplaces") }
    static var addRepository: String { localized("menu.workspace.add.repository") }
    /// Shared "Refresh All" label — used in Repositories, Harnesses and Marketplaces submenus.
    static var refreshAll: String { localized("menu.refresh.all") }
    static var pruneAllWorktrees: String { localized("menu.workspace.prune.all.worktrees") }
    static var repositorySettings: String { localized("menu.workspace.repository.settings") }
    static var installHarness: String { localized("menu.workspace.install.harness") }
    static var createHarness: String { localized("menu.workspace.create.harness") }
    static var harnessRegistries: String { localized("menu.workspace.harness.registries") }
    static var harnessTools: String { localized("menu.workspace.harness.tools") }
    static var addMarketplace: String { localized("menu.workspace.add.marketplace") }
    static var restoreDefaults: String { localized("menu.workspace.restore.defaults") }
    static var marketplaceSettings: String { localized("menu.workspace.marketplace.settings") }

    // MARK: Window menu

    static var favouriteCurrentTerminal: String { localized("menu.favourite.current.terminal") }
    static var allTerminals: String { localized("menu.all.terminals") }
    /// Fallback title shown in the Window jump list when a terminal card has no title set.
    static var terminalFallbackTitle: String { localized("menu.terminal.fallback.title") }

    // MARK: View menu

    static var toggleZoom: String { localized("menu.toggle.zoom") }
    static var nextTab: String { localized("menu.next.tab") }
    static var previousTab: String { localized("menu.previous.tab") }
    static var commandPalette: String { localized("menu.command.palette") }

    // MARK: Edit menu

    static var find: String { localized("menu.find") }

    // MARK: File menu

    static var openInTerminalApp: String { localized("menu.open.in.terminal.app") }
    static var exportSession: String { localized("menu.export.session") }
    static var closeTab: String { localized("menu.close.tab") }
    static var deleteTerminal: String { localized("menu.delete.terminal") }
    static var showBin: String { localized("menu.show.bin") }
}
