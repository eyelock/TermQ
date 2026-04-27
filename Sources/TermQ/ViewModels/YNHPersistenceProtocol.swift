import Foundation

/// Abstracts `YNHPersistence` so callers can be tested without reading or
/// writing the live `ynh.json` file on disk.
///
/// All methods mirror the public interface of `YNHPersistence` and carry the
/// same `@MainActor` isolation. Types that previously held a concrete
/// `YNHPersistence` reference should switch to `any YNHPersistenceProtocol`.
///
/// ## ObservableObject compatibility
///
/// SwiftUI's `@ObservedObject` requires a concrete `ObservableObject` type.
/// Views that observe `ynhPersistence` for published changes keep their
/// `@ObservedObject private var ynhPersistence: YNHPersistence = .shared`
/// declarations — the protocol exists to break the direct coupling in
/// **non-view** callers (ViewModels, services) where DI via init is practical.
@MainActor
protocol YNHPersistenceProtocol: AnyObject {

    // MARK: - Queries

    /// Returns the explicit harness override for a specific worktree path, if any.
    func harness(for worktreePath: String) -> String?

    /// Returns the repository-level default harness, independent from worktree overrides.
    func repoDefaultHarness(for repoPath: String) -> String?

    /// Returns the sorted list of worktree paths linked to a harness.
    func worktrees(for harnessName: String) -> [String]

    // MARK: - Mutations

    /// Sets or clears the repository-level default harness.
    func setRepoDefaultHarness(_ harnessName: String?, for repoPath: String)

    /// Sets or clears the harness override for a specific worktree path.
    func setHarness(_ harnessName: String?, for worktreePath: String)

    /// Removes all worktree and repo-level associations for a harness (called after uninstall).
    func removeAllAssociations(for harnessName: String)
}
