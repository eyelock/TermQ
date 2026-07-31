import Foundation
import SwiftUI

// MARK: - Settings.Stacking

/// Strings for the Settings > Tools stacked-PR section.
///
/// Split deliberately: `Stacking` holds everything that describes the FEATURE and is
/// therefore shared by every backend, while `GitSpice`/`GitHub` hold only the text that
/// names a specific tool. Reusing a `settings.gitspice.*` key to label the GitHub card
/// would read fine today and mislead the next person to touch it.
extension Strings.Settings {
    enum Stacking {
        static var section: String { localized("settings.stacking.section") }
        static var version: String { localized("settings.stacking.version") }
        static var path: String { localized("settings.stacking.path") }
        static var checkAgain: String { localized("settings.stacking.check.again") }
        static func statusUnusable(_ reason: String) -> String {
            localized("settings.stacking.status.unusable %@", reason)
        }
        static var newStackMode: String { localized("settings.stacking.new.stack.mode") }
        static var newStackModeHelp: String { localized("settings.stacking.new.stack.mode.help") }
        static var hideStackedWorktrees: String { localized("settings.stacking.hide.stacked.worktrees") }
        static var hideStackedWorktreesHelp: String {
            localized("settings.stacking.hide.stacked.worktrees.help")
        }
        static var preferred: String { localized("settings.stacking.preferred") }
        static var preferredHelp: String { localized("settings.stacking.preferred.help") }
        static var preferredAutomatic: String { localized("settings.stacking.preferred.automatic") }

        /// Product names, deliberately not localized — they are how each tool is spelled
        /// everywhere else, including in the commands the user types.
        static let gitSpiceName = "git-spice"
        static let gitHubName = "GitHub"
    }

    enum GitSpice {
        static var title: String { localized("settings.gitspice.title") }
        static var description: String { localized("settings.gitspice.description") }
        static var info: String { localized("settings.gitspice.info") }
        static var notInstalledDescription: String { localized("settings.gitspice.not.installed.description") }
        static var installHint: String { localized("settings.gitspice.install.hint") }
        /// The literal command shown for copy-paste — never translated.
        static let installCommand = "brew install git-spice"
    }

    enum GitHubStack {
        static var title: String { localized("settings.ghstack.title") }
        static var description: String { localized("settings.ghstack.description") }
        static var info: String { localized("settings.ghstack.info") }
        static var notInstalledDescription: String { localized("settings.ghstack.not.installed.description") }
        static var installHint: String { localized("settings.ghstack.install.hint") }
        /// gh must be present before the extension can be installed; this hint is shown
        /// instead of the install command when it is not.
        static var needsGhCli: String { localized("settings.ghstack.needs.gh.cli") }
        static let installCommand = "gh extension install github/gh-stack"
    }
}
