import Foundation

/// Owns user-level git preferences (currently: the global protected-branches
/// list). Per-repo overrides live on the repo model itself; this store only
/// holds the project-wide default that previously leaked between
/// `SettingsView`'s `@AppStorage("protectedBranches")` and
/// `WorktreeSidebarViewModel`'s raw `UserDefaults` read.
@MainActor
final class GitConfigStore: ObservableObject {
    static let shared = GitConfigStore()

    private let defaults: UserDefaults
    private static let protectedBranchesKey = "protectedBranches"

    /// Comma-separated list of branch names treated as protected when no
    /// per-repo override is set. Stored as a single string to match the legacy
    /// `@AppStorage` shape so existing on-disk values continue to load.
    @Published var globalProtectedBranches: String {
        didSet { defaults.set(globalProtectedBranches, forKey: Self.protectedBranchesKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.globalProtectedBranches = defaults.string(forKey: Self.protectedBranchesKey) ?? ""
    }
}
