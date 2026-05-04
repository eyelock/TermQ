import SwiftUI
import TermQShared

/// Configuration for installing a harness, passed from the sheet to ContentView.
///
/// ContentView calls `config.command(ynhPath:)` to build the init command for a
/// transient terminal card, so the user sees `ynh install` output in a dedicated tab.
struct HarnessInstallConfig {
    let displayName: String
    /// Arguments passed after `ynh install` (e.g. `["my-harness"]` or `["github.com/u/r", "--path", "sub"]`).
    let installArgs: [String]

    func command(ynhPath: String) -> String {
        ([ynhPath, "install"] + installArgs).joined(separator: " ")
    }
}

/// Thin host for the unified `SourcePicker` configured to install a harness.
/// Public surface (init params, `onInstall` callback) is preserved so call
/// sites need no changes.
struct HarnessInstallSheet: View {
    /// Names of already-installed harnesses — used to show "Installed" badge in search results.
    let installedNames: Set<String>
    /// Full installed harness list — shown as default content before any search term is entered.
    let harnesses: [Harness]
    let onInstall: (HarnessInstallConfig) -> Void

    @StateObject private var context: HarnessInstallContext

    init(
        installedNames: Set<String>,
        harnesses: [Harness],
        onInstall: @escaping (HarnessInstallConfig) -> Void
    ) {
        self.installedNames = installedNames
        self.harnesses = harnesses
        self.onInstall = onInstall
        _context = StateObject(
            wrappedValue: HarnessInstallContext(
                installedNames: installedNames,
                installedHarnesses: harnesses,
                onInstall: onInstall
            )
        )
    }

    var body: some View {
        SourcePicker(context: context)
    }
}
