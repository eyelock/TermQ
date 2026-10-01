import Foundation

extension Strings.Menu {
    static var utilities: String { localized("menu.utilities") }
    static var utilitiesLogging: String { localized("menu.utilities.logging") }
    static var memoryReport: String { localized("menu.memory.report") }
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

extension Strings {
    // MARK: - Memory Report
    enum MemoryReport {
        static var windowTitle: String { localized("memory.report.window.title") }
        static var collecting: String { localized("memory.report.collecting") }
        static var analysing: String { localized("memory.report.analysing") }
        static var pauseNotice: String { localized("memory.report.pause.notice") }
        static var ready: String { localized("memory.report.ready") }
        static var privacyNote: String { localized("memory.report.privacy") }
        static var copy: String { localized("memory.report.copy") }
        static var copied: String { localized("memory.report.copied") }
        static var save: String { localized("memory.report.save") }

        static func summary(_ footprint: String, _ peak: String, _ sessions: Int) -> String {
            localized("memory.report.summary %@ %@ %lld", footprint, peak, sessions)
        }
    }
}
