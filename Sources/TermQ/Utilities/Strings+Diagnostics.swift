import Foundation

extension Strings.Menu {
    static var utilities: String { localized("menu.utilities") }
    static var utilitiesLogging: String { localized("menu.utilities.logging") }
}

extension Strings {
    // MARK: - Diagnostics
    enum Diagnostics {
        static var windowTitle: String { localized("diagnostics.window.title") }
        static var filterCategory: String { localized("diagnostics.filter.category") }
        static var filterCategoryAll: String { localized("diagnostics.filter.category.all") }
        static var filterLevel: String { localized("diagnostics.filter.level") }
        static var searchPlaceholder: String { localized("diagnostics.search.placeholder") }
        static var clear: String { localized("diagnostics.clear") }
        static var export: String { localized("diagnostics.export") }
        static var jumpToLatest: String { localized("diagnostics.jump.to.latest") }
        static var statusLive: String { localized("diagnostics.status.live") }
        static var statusPaused: String { localized("diagnostics.status.paused") }
        static var verboseMode: String { localized("diagnostics.verbose.mode") }
        static var verboseModeHelp: String { localized("diagnostics.verbose.mode.help") }
        static var verboseWarning: String { localized("diagnostics.verbose.warning") }
        static var exportTitle: String { localized("diagnostics.export.title") }
        static var exportFooter: String { localized("diagnostics.export.footer") }

        static func statusEntries(_ total: Int, _ matching: Int) -> String {
            localized("diagnostics.status.entries %lld %lld", total, matching)
        }
    }
}
