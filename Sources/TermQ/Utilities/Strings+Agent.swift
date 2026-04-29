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

// MARK: - Editor.Agent

extension Strings.Editor {
    enum Agent {
        static var tab: String { localized("editor.tab.agent") }
        static var sectionConfig: String { localized("editor.agent.section.config") }
        static var sectionBudget: String { localized("editor.agent.section.budget") }
        static var fieldBackend: String { localized("editor.agent.field.backend") }
        static var fieldMode: String { localized("editor.agent.field.mode") }
        static var fieldInteraction: String { localized("editor.agent.field.interaction") }
        static var fieldMaxTurns: String { localized("editor.agent.field.max.turns") }
        static var fieldMaxTokens: String { localized("editor.agent.field.max.tokens") }
        static var fieldMaxWallMinutes: String { localized("editor.agent.field.max.wall.minutes") }
    }
}
