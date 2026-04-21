import Foundation
import SwiftUI

// MARK: - Settings.Ynh

extension Strings.Settings {
    enum Ynh {
        static var sectionTitle: String { localized("settings.ynh.section") }
        static var title: String { localized("settings.ynh.title") }
        static var description: String { localized("settings.ynh.description") }
        static var enableHarnessTab: String { localized("settings.ynh.enable.harness.tab") }
        static var enableHarnessTabHelp: String { localized("settings.ynh.enable.harness.tab.help") }
        static var homeOverride: String { localized("settings.ynh.home.override") }
        static var homeOverridePlaceholder: String { localized("settings.ynh.home.override.placeholder") }
        static var homeOverrideHelp: String { localized("settings.ynh.home.override.help") }
        static var resolvedPaths: String { localized("settings.ynh.resolved.paths") }
        static var redetect: String { localized("settings.ynh.redetect") }
        static var initRequired: String { localized("settings.ynh.init.required") }
        static var ready: String { localized("settings.ynh.ready") }
        static var pathLabel: String { localized("settings.ynh.path.label") }
        static var yndPathLabel: String { localized("settings.ynh.ynd.path.label") }
        static var statusLabel: String { localized("settings.ynh.status.label") }
        static var readyInfo: String { localized("settings.ynh.ready.info") }
        static var advanced: String { localized("settings.ynh.advanced") }
        static var versionLabel: String { localized("settings.ynh.version.label") }
        static var docsLinkLabel: String { localized("settings.ynh.docs.link.label") }
    }
}
