import Foundation

/// A named grouping of git repositories.
///
/// Workspaces filter only the Repositories sidebar — harnesses and marketplaces
/// remain global. Membership is stored here (`repoIds`) rather than on
/// `GitRepository`, so `repos.json` stays untouched and the CLI/MCP keep seeing
/// every repo. Membership is many-to-many: a repo may appear in several
/// workspaces. Stale ids (a repo later deleted) are harmless — filtering
/// intersects with the live repo set.
struct Workspace: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var repoIds: [UUID]
    let addedAt: Date

    init(id: UUID = UUID(), name: String, repoIds: [UUID] = [], addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.repoIds = repoIds
        self.addedAt = addedAt
    }
}

/// Persisted root for the Workspaces feature: the workspace definitions plus the
/// single active selection.
///
/// Both live in one file (`workspaces.json`) so the active selection can never
/// drift from the definitions across a restart or update. A `nil`
/// `activeWorkspaceId` means the implicit "All" view — no filtering. "All" is
/// never stored as a `Workspace`.
struct WorkspaceConfig: Codable, Sendable {
    var activeWorkspaceId: UUID?
    var workspaces: [Workspace]

    init(activeWorkspaceId: UUID? = nil, workspaces: [Workspace] = []) {
        self.activeWorkspaceId = activeWorkspaceId
        self.workspaces = workspaces
    }
}
