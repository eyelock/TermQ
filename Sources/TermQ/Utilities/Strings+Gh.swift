import Foundation
import SwiftUI

// MARK: - Settings.Gh

extension Strings.Settings {
    enum Gh {
        static var section: String { localized("settings.section.gh") }
        static var title: String { localized("settings.gh.title") }
        static var description: String { localized("settings.gh.description") }
        static var version: String { localized("settings.gh.version") }
        static var path: String { localized("settings.gh.path") }
        static var info: String { localized("settings.gh.info") }
        static var notInstalledDescription: String { localized("settings.gh.not.installed.description") }
        static var installHint: String { localized("settings.gh.install.hint") }
        static var checkAgain: String { localized("settings.gh.check.again") }
        static var statusUnauthenticated: String { localized("settings.gh.status.unauthenticated") }
        static var statusAuthCheckFailed: String { localized("settings.gh.status.auth.check.failed") }
        static var authHint: String { localized("settings.gh.auth.hint") }
        static func statusSignedInAs(_ login: String) -> String {
            localized("settings.gh.status.signed.in.as %@", login)
        }
    }
}
