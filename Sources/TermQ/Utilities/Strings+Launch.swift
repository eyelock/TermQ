import Foundation

extension Strings {
    /// The launch group every menu starts with. "Quick" never opens a dialog;
    /// "…" always does.
    enum Launch {
        /// Launch with the harness's defaults, no dialog.
        static func quick(_ name: String) -> String { localized("launch.quick %@", name) }
        /// Open the launch sheet with `name` chosen.
        static func sheet(_ name: String) -> String { localized("launch.sheet %@", name) }
        /// Open the launch sheet, with no harness chosen yet.
        static var sheetAny: String { localized("launch.sheet.any") }
        /// A button that opens the launch sheet for a harness already named nearby.
        static var sheetShort: String { localized("launch.sheet.short") }
        /// The submenu of focuses, each launched with no dialog.
        static var withFocus: String { localized("launch.with.focus") }
    }
}
