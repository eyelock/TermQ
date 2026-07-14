import Foundation
import SwiftUI

// MARK: - Settings.GitSpice

extension Strings.Settings {
    enum GitSpice {
        static var section: String { localized("settings.gitspice.section") }
        static var title: String { localized("settings.gitspice.title") }
        static var description: String { localized("settings.gitspice.description") }
        static var version: String { localized("settings.gitspice.version") }
        static var path: String { localized("settings.gitspice.path") }
        static var info: String { localized("settings.gitspice.info") }
        static var notInstalledDescription: String { localized("settings.gitspice.not.installed.description") }
        static var installHint: String { localized("settings.gitspice.install.hint") }
        static var checkAgain: String { localized("settings.gitspice.check.again") }
        static func statusUnusable(_ reason: String) -> String {
            localized("settings.gitspice.status.unusable %@", reason)
        }
    }
}
