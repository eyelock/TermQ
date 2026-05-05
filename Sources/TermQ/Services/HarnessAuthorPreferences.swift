import Foundation

/// Owns user preferences relevant to harness authoring (fork, duplicate, wizard
/// flows). Currently scoped to the default destination directory the sheets
/// pre-fill. Keeps these out of the global `SettingsStore` since they only
/// matter to authoring UIs.
@MainActor
final class HarnessAuthorPreferences: ObservableObject {
    static let shared = HarnessAuthorPreferences()

    private let defaults: UserDefaults
    private static let defaultDirectoryKey = "defaultHarnessAuthorDirectory"

    /// Default destination directory used by Fork / Duplicate / Wizard sheets.
    /// Empty string means "no default — fall back to the harness's own location."
    @Published var defaultDirectory: String {
        didSet { defaults.set(defaultDirectory, forKey: Self.defaultDirectoryKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaultDirectory = defaults.string(forKey: Self.defaultDirectoryKey) ?? ""
    }
}
