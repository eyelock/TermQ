import Foundation
import SwiftUI

// MARK: - Settings.Agent

extension Strings.Settings {
    enum Agent {
        static var sectionTitle: String { localized("settings.agent.section") }
        static var description: String { localized("settings.agent.description") }
        static var enableAgentTab: String { localized("settings.agent.enable.tab") }
        static var enableAgentTabHelp: String { localized("settings.agent.enable.tab.help") }
    }
}
