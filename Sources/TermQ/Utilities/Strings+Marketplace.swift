import Foundation
import SwiftUI

// MARK: - Marketplace

extension Strings {
    enum Marketplace {
        static var title: String { localized("marketplace.title") }
        static var addHelp: String { localized("marketplace.add.help") }
        static var groupDefault: String { localized("marketplace.group.default") }
        static func groupGitHub(_ org: String) -> String { localized("marketplace.group.github %@", org) }
        static var groupLocal: String { localized("marketplace.group.local") }
        static var addTabLocal: String { localized("marketplace.add.tab.local") }
        static var addSectionLocalPath: String { localized("marketplace.add.section.local.path") }
        static var addLocalBrowse: String { localized("marketplace.add.local.browse") }
        static var addLocalPathPlaceholder: String { localized("marketplace.add.local.path.placeholder") }
        static var rowLocal: String { localized("marketplace.row.local") }
        static var rowReveal: String { localized("marketplace.row.reveal") }
        static var empty: String { localized("marketplace.empty") }
        static var addButton: String { localized("marketplace.add.button") }
        static var rowRefreshHelp: String { localized("marketplace.row.refresh.help") }
        static var rowRefresh: String { localized("marketplace.row.refresh") }
        static var rowRemove: String { localized("marketplace.row.remove") }
        static var rowStale: String { localized("marketplace.row.stale") }
        static var rowNeverFetched: String { localized("marketplace.row.never.fetched") }
        static var refreshAllHelp: String { localized("marketplace.refresh.all.help") }
        static var restoreDefaults: String { localized("marketplace.restore.defaults") }
        static var restoreDefaultsHelp: String { localized("marketplace.restore.defaults.help") }
        static var addSheetTitle: String { localized("marketplace.add.sheet.title") }
        static var addTabKnown: String { localized("marketplace.add.tab.known") }
        static var addTabCustom: String { localized("marketplace.add.tab.custom") }
        static var addSectionGitURL: String { localized("marketplace.add.section.git.url") }
        static var addSectionDisplayName: String { localized("marketplace.add.section.display.name") }
        static var addSectionVendor: String { localized("marketplace.add.section.vendor") }
        static var addSectionRef: String { localized("marketplace.add.section.ref") }
        static var addRefPlaceholder: String { localized("marketplace.add.ref.placeholder") }
        static func rowPinnedHelp(_ ref: String) -> String { localized("marketplace.row.pinned.help %@", ref) }
        static func detailLastFetched(_ rel: String) -> String {
            localized("marketplace.detail.last.fetched %@", rel)
        }
        static var detailSearchPlaceholder: String { localized("marketplace.detail.search.placeholder") }
        static func detailSearchEmpty(_ query: String) -> String {
            localized("marketplace.detail.search.empty %@", query)
        }
        static var detailEmpty: String { localized("marketplace.detail.empty") }
        static var detailEmptyHint: String { localized("marketplace.detail.empty.hint") }
        static var pluginAddToHarness: String { localized("marketplace.plugin.add.to.harness") }
        static var pluginCopyInstallCommand: String { localized("marketplace.plugin.copy.install.command") }
        static var pluginCopyInstallCommandHelp: String { localized("marketplace.plugin.copy.install.command.help") }
        static var pluginLoadArtifacts: String { localized("marketplace.plugin.load.artifacts") }
        static var pluginLoadingArtifacts: String { localized("marketplace.plugin.loading.artifacts") }
        static var pluginNoArtifacts: String { localized("marketplace.plugin.no.artifacts") }
        static var pluginNoArtifactsHint: String { localized("marketplace.plugin.no.artifacts.hint") }
        static func pluginArtifactsUnavailable(_ msg: String) -> String {
            localized("marketplace.plugin.artifacts.unavailable %@", msg)
        }

        // MARK: Include Picker
        enum Picker {
            static var stepArtifacts: String { localized("marketplace.picker.step.artifacts") }
            static var stepHarness: String { localized("marketplace.picker.step.harness") }
            static var stepApply: String { localized("marketplace.picker.step.apply") }
            static var selectPrompt: String { localized("marketplace.picker.select.prompt") }
            static var selectAll: String { localized("marketplace.picker.select.all") }
            static var selectNone: String { localized("marketplace.picker.select.none") }
            static var noHarnesses: String { localized("marketplace.picker.no.harnesses") }
            static var noHarnessesHint: String { localized("marketplace.picker.no.harnesses.hint") }
            static var reviewPlugin: String { localized("marketplace.picker.review.plugin") }
            static var reviewHarness: String { localized("marketplace.picker.review.harness") }
            static var reviewArtifacts: String { localized("marketplace.picker.review.artifacts") }
            static func reviewAllCount(_ count: Int) -> String {
                localized("marketplace.picker.review.all.count %lld", count)
            }
            static func reviewSelected(_ selected: Int, _ total: Int) -> String {
                localized("marketplace.picker.review.selected %lld %lld", selected, total)
            }
            static var commandPreview: String { localized("marketplace.picker.command.preview") }
            static func success(_ name: String) -> String {
                localized("marketplace.picker.success %@", name)
            }
            static var done: String { localized("marketplace.picker.done") }
            static var back: String { localized("marketplace.picker.back") }
            static var next: String { localized("marketplace.picker.next") }
        }
    }
}

// MARK: - Harness Wizard

extension Strings {
    enum HarnessDuplicate {
        static var title: String { localized("harness.duplicate.title") }
        static var duplicateButton: String { localized("harness.duplicate.button") }
        static var installing: String { localized("harness.duplicate.installing") }
        static func success(_ name: String) -> String { localized("harness.duplicate.success %@", name) }
    }

    enum HarnessWizard {
        static var title: String { localized("harness.wizard.title") }
        static var nameLabel: String { localized("harness.wizard.name.label") }
        static var descriptionLabel: String { localized("harness.wizard.description.label") }
        static var loadingVendors: String { localized("harness.wizard.loading.vendors") }
        static var vendorLabel: String { localized("harness.wizard.vendor.label") }
        static var destinationLabel: String { localized("harness.wizard.destination.label") }
        static var installToggle: String { localized("harness.wizard.install.toggle") }
        static var successAddPlugins: String { localized("harness.wizard.success.add.plugins") }
        static var successOpen: String { localized("harness.wizard.success.open") }
        static var create: String { localized("harness.wizard.create") }
        static var retry: String { localized("harness.wizard.retry") }
        static var errorNameRequired: String { localized("harness.wizard.error.name.required") }
        static var errorNameInvalid: String { localized("harness.wizard.error.name.invalid") }
        static func errorNameDuplicate(_ name: String) -> String {
            localized("harness.wizard.error.name.duplicate %@", name)
        }
    }
}

// MARK: - Settings.Marketplaces

extension Strings.Settings {
    enum Marketplaces {
        static var sectionMarketplaces: String { localized("settings.marketplaces.section.list") }
        static var noMarketplaces: String { localized("settings.marketplaces.empty") }
        static var addMarketplace: String { localized("settings.marketplaces.add") }
        static var neverFetched: String { localized("settings.marketplaces.never.fetched") }
        static var removeConfirmTitle: String { localized("settings.marketplaces.remove.confirm.title") }
        static func removeConfirmMessage(_ vendor: String) -> String {
            localized("settings.marketplaces.remove.confirm.message %@", vendor)
        }
        static var sectionBehaviour: String { localized("settings.marketplaces.section.behaviour") }
        static var autoRefresh: String { localized("settings.marketplaces.auto.refresh") }
        static var autoRefreshHelp: String { localized("settings.marketplaces.auto.refresh.help") }
        static var sectionAuthoring: String { localized("settings.marketplaces.section.authoring") }
        static var defaultAuthorDirectory: String { localized("settings.marketplaces.default.author.directory") }
        static var authorDirectoryDetectedHint: String {
            localized("settings.marketplaces.author.directory.detected.hint")
        }
        static var reset: String { localized("settings.marketplaces.reset") }
        static var sectionYNHRegistries: String { localized("settings.marketplaces.section.ynh.registries") }
        static var noRegistries: String { localized("settings.marketplaces.ynh.registries.empty") }
        static var addYNHRegistry: String { localized("settings.marketplaces.ynh.add.registry") }
        static var removeRegistryConfirmTitle: String {
            localized("settings.marketplaces.ynh.registry.remove.confirm.title")
        }
        static var removeRegistryConfirm: String { localized("settings.marketplaces.ynh.registry.remove.confirm") }
        static func removeRegistryConfirmMessage(_ name: String) -> String {
            localized("settings.marketplaces.ynh.registry.remove.confirm.message %@", name)
        }
    }
}

extension Strings.Marketplace {
    static var addCustomNamePlaceholder: String { localized("marketplace.add.custom.name.placeholder") }
}

extension Strings.HarnessWizard {
    static func successCreated(_ name: String) -> String {
        localized("harness.wizard.success.created %@", name)
    }
}
