import Foundation
import SwiftUI

// MARK: - Sidebar

extension Strings {
    enum Sidebar {
        static var title: String { localized("sidebar.title") }
        static var addButtonHelp: String { localized("sidebar.add.button.help") }
        static var emptyMessage: String { localized("sidebar.empty.message") }
        static var worktreesPlaceholder: String { localized("sidebar.worktrees.placeholder") }
        static var removeRepository: String { localized("sidebar.remove.repository") }
        static var toggleHelp: String { localized("sidebar.toggle.help") }
        static var addRepositoryTitle: String { localized("sidebar.add.title") }
        static var editRepositoryTitle: String { localized("sidebar.edit.title") }
        static var editRepository: String { localized("sidebar.edit.repository") }
        static var pathLabel: String { localized("sidebar.add.path.label") }
        static var nameLabel: String { localized("sidebar.add.name.label") }
        static var namePlaceholder: String { localized("sidebar.add.name.placeholder") }
        static var worktreeBasePathLabel: String { localized("sidebar.worktree.base.path.label") }
        static var worktreeBasePathHelp: String { localized("sidebar.worktree.base.path.help") }
        static var worktreeBasePathPlaceholder: String { localized("sidebar.worktree.base.path.placeholder") }
        static var protectedBranchesOverrideLabel: String { localized("sidebar.protected.branches.override.label") }
        static var protectedBranchesOverrideHelp: String { localized("sidebar.protected.branches.override.help") }
        static var protectedBranchesOverridePlaceholder: String {
            localized("sidebar.protected.branches.override.placeholder")
        }
        static var basePathEqualsRepo: String { localized("sidebar.base.path.equals.repo") }
        static var basePathIsParentOfRepo: String { localized("sidebar.base.path.is.parent") }
        static func addToGitignore(_ entry: String) -> String {
            String(format: localized("sidebar.add.gitignore %@"), entry)
        }
        static var cancelButton: String { localized("sidebar.add.cancel") }
        static var addButton: String { localized("sidebar.add.add") }
        static var addAdvanced: String { localized("sidebar.add.advanced") }
        static var menuToggle: String { localized("menu.toggle.sidebar") }
        static func errorNotGitRepo(_ path: String) -> String {
            localized("sidebar.error.not.git.repo %@", path)
        }

        // Worktree list
        static var worktreesEmpty: String { localized("sidebar.worktrees.empty") }
        static var detachedHead: String { localized("sidebar.worktree.detached.head") }
        static var mainBadge: String { localized("sidebar.worktree.main.badge") }
        static var refreshWorktrees: String { localized("sidebar.worktrees.refresh") }
        static var newWorktree: String { localized("sidebar.worktree.new") }
        static var newTerminal: String { localized("sidebar.worktree.new.terminal") }
        static var createTerminal: String { localized("sidebar.worktree.create.terminal") }
        static var terminalBadgeHelp: String { localized("sidebar.worktree.terminals.badge.help") }
        static var openInTerminal: String { localized("sidebar.worktree.open.in.terminal") }
        static var revealInFinder: String { localized("sidebar.worktree.reveal.in.finder") }
        static var openIn: String { localized("sidebar.worktree.open.in") }
        static var copyPathname: String { localized("sidebar.worktree.copy.pathname") }
        static var openRemoteBranch: String { localized("sidebar.worktree.open.remote.branch") }
        static var openRemoteCommit: String { localized("sidebar.worktree.open.remote.commit") }
        static var lockWorktree: String { localized("sidebar.worktree.lock") }
        static var unlockWorktree: String { localized("sidebar.worktree.unlock") }

        // Harness linkage
        static var setHarness: String { localized("sidebar.worktree.set.harness") }
        static var clearHarness: String { localized("sidebar.worktree.clear.harness") }
        static func linkedHarness(_ name: String) -> String {
            String(format: localized("sidebar.worktree.linked.harness %@"), name)
        }
        static func launchHarness(_ name: String) -> String {
            String(format: localized("sidebar.worktree.launch.harness %@"), name)
        }

        // Remove / delete worktree
        static var removeWorktree: String { localized("sidebar.remove.worktree") }
        static var removeWorktreeTitle: String { localized("sidebar.remove.worktree.title") }
        static var removeWorktreeConfirm: String { localized("sidebar.remove.worktree.confirm") }
        static var removeMainWorktreeError: String { localized("sidebar.remove.main.worktree.error") }
        static func removeWorktreeMessage(_ path: String) -> String {
            localized("sidebar.remove.worktree.message %@", path)
        }

        static var deleteWorktree: String { localized("sidebar.worktree.delete") }
        static var deleteWorktreeTitle: String { localized("sidebar.worktree.delete.title") }
        static var deleteWorktreeConfirm: String { localized("sidebar.worktree.delete.confirm") }
        static func deleteWorktreeMessage(_ path: String) -> String {
            localized("sidebar.worktree.delete.message %@", path)
        }

        // Prune worktrees
        static var pruneWorktrees: String { localized("sidebar.prune.worktrees") }
        static var pruneWorktreesTitle: String { localized("sidebar.prune.worktrees.title") }
        static var pruneWorktreesConfirm: String { localized("sidebar.prune.worktrees.confirm") }
        static var pruneWorktreesNothingTitle: String { localized("sidebar.prune.worktrees.nothing.title") }
        static var pruneWorktreesNothingMessage: String { localized("sidebar.prune.worktrees.nothing.message") }
        static var pruneWorktreesExplanation: String { localized("sidebar.prune.worktrees.explanation") }
        static var pruneBranches: String { localized("sidebar.prune.branches") }
        static var pruneBranchesTitle: String { localized("sidebar.prune.branches.title") }
        static var pruneBranchesConfirm: String { localized("sidebar.prune.branches.confirm") }
        static var pruneBranchesNothingTitle: String { localized("sidebar.prune.branches.nothing.title") }
        static var pruneBranchesNothingMessage: String { localized("sidebar.prune.branches.nothing.message") }
        static var pruneBranchesExplanation: String { localized("sidebar.prune.branches.explanation") }

        // New worktree sheet
        static var newWorktreeTitle: String { localized("sidebar.new.worktree.title") }
        static var branchNameLabel: String { localized("sidebar.new.worktree.branch.label") }
        static var branchNamePlaceholder: String { localized("sidebar.new.worktree.branch.placeholder") }
        static var newWorktreeBranchRequired: String { localized("sidebar.new.worktree.branch.required") }
        static var baseBranchLabel: String { localized("sidebar.new.worktree.base.label") }
        static var baseBranchPlaceholder: String { localized("sidebar.new.worktree.base.placeholder") }
        static var worktreePathLabel: String { localized("sidebar.new.worktree.path.label") }
        static var newWorktreePathRequired: String { localized("sidebar.new.worktree.path.required") }
        static var createButton: String { localized("sidebar.new.worktree.create") }
        static var loadingBranches: String { localized("sidebar.new.worktree.loading.branches") }

        // Local branches section
        static var localBranches: String { localized("sidebar.local.branches") }
        static var newWorktreeFromBranch: String { localized("sidebar.branch.new.worktree.from.branch") }

        // Checkout branch as worktree sheet
        static var checkoutBranchTitle: String { localized("sidebar.checkout.branch.title") }
        static var checkoutBranchLabel: String { localized("sidebar.checkout.branch.label") }
        static var checkoutBranchPlaceholder: String { localized("sidebar.checkout.branch.placeholder") }
        static var checkoutBranchRequired: String { localized("sidebar.checkout.branch.required") }
        static var checkoutBranchCreate: String { localized("sidebar.checkout.branch.create") }
    }

    // MARK: - Harnesses

    enum Harnesses {
        static var title: String { localized("harnesses.title") }
        static var refreshHelp: String { localized("harnesses.refresh.help") }
        static var wizardToolbarHelp: String { localized("harnesses.wizard.toolbar.help") }
        static var notInstalled: String { localized("harnesses.not.installed") }
        static var initRequired: String { localized("harnesses.init.required") }
        static var initHint: String { localized("harnesses.init.hint") }
        static var emptyMessage: String { localized("harnesses.empty.message") }
        static var emptyNoRegistriesMessage: String { localized("harnesses.empty.no.registries.message") }
        static var searchButton: String { localized("harnesses.search.button") }

        // Row badges
        static var sourceLocal: String { localized("harnesses.source.local") }
        static var sourceRegistry: String { localized("harnesses.source.registry") }

        // Sidebar groups
        static var groupDefault: String { localized("harnesses.group.default") }
        static var groupLocal: String { localized("harnesses.group.local") }
        static func groupGitHub(_ org: String) -> String { localized("harnesses.group.github %@", org) }
        static func groupRegistry(_ name: String) -> String { localized("harnesses.group.registry %@", name) }

        // Detail view
        static var detailInfo: String { localized("harnesses.detail.info") }
        static var detailPath: String { localized("harnesses.detail.path") }
        static var detailSource: String { localized("harnesses.detail.source") }
        static var detailSubpath: String { localized("harnesses.detail.subpath") }
        static var detailInstalledAt: String { localized("harnesses.detail.installed.at") }
        static var detailArtifacts: String { localized("harnesses.detail.artifacts") }
        static var detailNoArtifacts: String { localized("harnesses.detail.no.artifacts") }
        static var detailSkills: String { localized("harnesses.detail.skills") }
        static var detailAgents: String { localized("harnesses.detail.agents") }
        static var detailRules: String { localized("harnesses.detail.rules") }
        static var detailCommands: String { localized("harnesses.detail.commands") }
        static var detailDependencies: String { localized("harnesses.detail.dependencies") }
        static func detailIncludes(_ count: Int) -> String {
            localized("harnesses.detail.includes %d", count)
        }
        static func detailDelegates(_ count: Int) -> String {
            localized("harnesses.detail.delegates %d", count)
        }
        static func detailPicks(_ count: Int) -> String {
            localized("harnesses.detail.picks %d", count)
        }
        static var revealInFinder: String { localized("harnesses.reveal.in.finder") }
        static var openInBrowser: String { localized("harnesses.open.in.browser") }
        static var closeDetail: String { localized("harnesses.close.detail") }
        static var configureFromMarketplaces: String { localized("harnesses.configure.from.marketplaces") }
        static var detailArtifactsFromIncludes: String { localized("harnesses.detail.artifacts.from.includes") }
        static var detailFrom: String { localized("harnesses.detail.from") }
        static var detailHooks: String { localized("harnesses.detail.hooks") }
        static var detailMCPServers: String { localized("harnesses.detail.mcp.servers") }
        static var detailProfiles: String { localized("harnesses.detail.profiles") }
        static var detailFocuses: String { localized("harnesses.detail.focuses") }
        static func detailFocusProfile(_ name: String) -> String {
            localized("harnesses.detail.focus.profile %@", name)
        }
        static var detailManifest: String { localized("harnesses.detail.manifest") }
        static var detailNoManifest: String { localized("harnesses.detail.no.manifest") }
        static var detailResolved: String { localized("harnesses.detail.resolved") }
        static var detailUnresolved: String { localized("harnesses.detail.unresolved") }
        static var detailNoHooks: String { localized("harnesses.detail.no.hooks") }
        static var detailNoMCPServers: String { localized("harnesses.detail.no.mcp.servers") }
        static var detailNoProfiles: String { localized("harnesses.detail.no.profiles") }
        static var detailNoFocuses: String { localized("harnesses.detail.no.focuses") }

        // Launch
        static var launchTitle: String { localized("harnesses.launch.title") }
        static var launchVendor: String { localized("harnesses.launch.vendor") }
        static var launchVendorUnavailable: String { localized("harnesses.launch.vendor.unavailable") }
        static func launchVendorDefault(_ vendor: String) -> String {
            String(format: localized("harnesses.launch.vendor.default"), vendor)
        }
        static var launchFocus: String { localized("harnesses.launch.focus") }
        static var launchFocusNone: String { localized("harnesses.launch.focus.none") }
        static var launchWorkingDirectory: String { localized("harnesses.launch.working.directory") }
        static var launchBrowse: String { localized("harnesses.launch.browse") }
        static var launchPrompt: String { localized("harnesses.launch.prompt") }
        static var launchPromptPlaceholder: String { localized("harnesses.launch.prompt.placeholder") }
        static var launchButton: String { localized("harnesses.launch.button") }
        static var launchHelp: String { localized("harnesses.launch.help") }
        static var launchCancel: String { localized("harnesses.launch.cancel") }
        static var launchBackend: String { localized("harnesses.launch.backend") }

        // Linked worktrees section in detail view
        static var linkedWorktrees: String { localized("harnesses.linked.worktrees") }
        static var linkedWorktreesNone: String { localized("harnesses.linked.worktrees.none") }

        // Install sheet
        static var installTitle: String { localized("harnesses.install.title") }
        static var installToolbarHelp: String { localized("harnesses.install.toolbar.help") }
        static var installTabSearch: String { localized("harnesses.install.tab.search") }
        static var installTabGit: String { localized("harnesses.install.tab.git") }
        static var installTabSources: String { localized("harnesses.install.tab.sources") }
        static var installSearchPlaceholder: String { localized("harnesses.install.search.placeholder") }
        static var installSearchPrompt: String { localized("harnesses.install.search.prompt") }
        static var installSearchEmpty: String { localized("harnesses.install.search.empty") }
        static var installSectionInstalled: String { localized("harnesses.install.section.installed") }
        static var installSectionAvailable: String { localized("harnesses.install.section.available") }
        static var installSectionLocal: String { localized("harnesses.install.section.local") }
        static var installBrowsing: String { localized("harnesses.install.browsing") }
        static var installRetry: String { localized("harnesses.install.retry") }
        static var installGitURL: String { localized("harnesses.install.git.url") }
        static var installGitURLPlaceholder: String { localized("harnesses.install.git.url.placeholder") }
        static var installGitSubpath: String { localized("harnesses.install.git.subpath") }
        static var installGitSubpathPlaceholder: String { localized("harnesses.install.git.subpath.placeholder") }
        static var installGitRef: String { localized("harnesses.install.git.ref") }
        static var installGitRefPlaceholder: String { localized("harnesses.install.git.ref.placeholder") }
        static var installCommandPreview: String { localized("harnesses.install.command.preview") }
        static var installConfirm: String { localized("harnesses.install.confirm") }
        static var installCancel: String { localized("harnesses.install.cancel") }
        static var installAlreadyInstalled: String { localized("harnesses.install.already.installed") }
        static func installFrom(_ name: String) -> String {
            String(format: localized("harnesses.install.from %@"), name)
        }
        static var installSourcesEmpty: String { localized("harnesses.install.sources.empty") }
        static var installSourcesAdd: String { localized("harnesses.install.sources.add") }
        static var installSourcesAddHelp: String { localized("harnesses.install.sources.add.help") }
        static var installSourcesRemove: String { localized("harnesses.install.sources.remove") }
        static func installSourcesCount(_ count: Int) -> String {
            String(format: localized("harnesses.install.sources.count %ld"), count)
        }

        // MARK: Update / Uninstall
        static var updateButton: String { localized("harnesses.update.button") }
        static var updateHelp: String { localized("harnesses.update.help") }
        static var uninstallButton: String { localized("harnesses.uninstall.button") }
        static var uninstallHelp: String { localized("harnesses.uninstall.help") }
        static func uninstallAlertTitle(_ name: String) -> String {
            String(format: localized("harnesses.uninstall.alert.title %@"), name)
        }
        static var uninstallAlertMessage: String { localized("harnesses.uninstall.alert.message") }
        static func uninstallAlertWorktrees(_ count: Int) -> String {
            String(format: localized("harnesses.uninstall.alert.worktrees %ld"), count)
        }
        static func uninstallAlertTerminals(_ count: Int) -> String {
            String(format: localized("harnesses.uninstall.alert.terminals %ld"), count)
        }
        static var uninstallAlertConfirm: String { localized("harnesses.uninstall.alert.confirm") }
        static var moreActionsHelp: String { localized("harnesses.more.actions.help") }
        static var copyRunCommand: String { localized("harnesses.copy.run.command") }
        static var exportButton: String { localized("harnesses.export.button") }
        static var ynhDocumentation: String { localized("harnesses.ynh.documentation") }
        static var addRegistryTitle: String { localized("harnesses.add.registry.title") }
        static var addRegistryURLLabel: String { localized("harnesses.add.registry.url.label") }
        static var addRegistryHint: String { localized("harnesses.add.registry.hint") }
        static var addRegistryButton: String { localized("harnesses.add.registry.button") }
        static var addRegistrySuccess: String { localized("harnesses.add.registry.success") }
        static var addRegistryToolbarHelp: String { localized("harnesses.add.registry.toolbar.help") }
        static var addSampleButton: String { localized("harnesses.add.sample.button") }
        static var groupMenuSettings: String { localized("harnesses.group.menu.settings") }
        static var createHarnessButton: String { localized("harnesses.create.harness.button") }
    }
}
