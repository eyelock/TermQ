import Foundation

/// Pure filtering logic for the Repositories sidebar.
///
/// Extracted from any view or store so the "what shows where" rules can be
/// unit-tested in isolation, with no SwiftUI or persistence involved.
enum WorkspaceFilter {
    /// The repo ids to display under a given active selection, preserving the
    /// order of `allRepoIds`.
    ///
    /// - `active == nil` → "All": every repo, unfiltered.
    /// - `active` names a workspace → only that workspace's members, in
    ///   `allRepoIds` order. Member ids absent from `allRepoIds` (a repo since
    ///   deleted) are ignored — membership intersects the live repo set.
    /// - `active` set but not found among `workspaces` → treated as "All"
    ///   (defensive fallback; a deleted active workspace shows everything).
    static func visibleRepoIds(
        active: UUID?,
        in workspaces: [Workspace],
        allRepoIds: [UUID]
    ) -> [UUID] {
        guard let active,
            let workspace = workspaces.first(where: { $0.id == active })
        else {
            return allRepoIds
        }
        let members = Set(workspace.repoIds)
        return allRepoIds.filter { members.contains($0) }
    }
}
