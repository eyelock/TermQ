import Foundation
import TermQShared

/// Persisted workspaces (named groupings of repositories) plus the active
/// selection.
///
/// Stored at `<data-dir>/workspaces.json`, where `<data-dir>` is the
/// profile-aware TermQ directory (`TermQ` or `TermQ-Debug`) — the same directory
/// `repos.json` lives in, so workspace membership (repo UUIDs) always matches the
/// repo list of the running build. Lives outside the `.app` bundle, so it
/// survives restarts and Sparkle updates exactly like `repos.json`.
@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    @Published private(set) var workspaces: [Workspace] = []
    /// The active workspace, or `nil` for the implicit "All" view.
    @Published private(set) var activeWorkspaceId: UUID?

    /// Most recent persistence error, if any. Surfaces silent disk failures
    /// (write permission, disk full, encoding) to the UI.
    @Published private(set) var lastPersistenceError: String?

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Designated initialiser. Defaults to the profile-aware production/debug
    /// location; tests inject a temp file.
    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = BoardLoader.getDataDirectoryPath()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("workspaces.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let config = try? decoder.decode(WorkspaceConfig.self, from: data)
        else { return }
        workspaces = config.workspaces
        activeWorkspaceId = normalizedActive(config.activeWorkspaceId, in: config.workspaces)
    }

    private func save() {
        let config = WorkspaceConfig(activeWorkspaceId: activeWorkspaceId, workspaces: workspaces)
        do {
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: .atomic)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = "Failed to persist workspaces: \(error.localizedDescription)"
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.ui.error("WorkspaceStore: failed to persist: \(error.localizedDescription)")
            } else {
                TermQLogger.ui.error("WorkspaceStore: failed to persist workspaces")
            }
        }
    }

    /// Drops an active id that no longer names a workspace (→ "All").
    private func normalizedActive(_ id: UUID?, in workspaces: [Workspace]) -> UUID? {
        guard let id, workspaces.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    // MARK: - Lookups

    func workspace(id: UUID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    func contains(repoId: UUID, in workspaceId: UUID) -> Bool {
        workspace(id: workspaceId)?.repoIds.contains(repoId) ?? false
    }

    /// Repo ids visible under the current active selection, in `allRepoIds` order.
    func visibleRepoIds(allRepoIds: [UUID]) -> [UUID] {
        WorkspaceFilter.visibleRepoIds(
            active: activeWorkspaceId, in: workspaces, allRepoIds: allRepoIds)
    }

    // MARK: - Active selection

    /// Set the active workspace (or `nil` for "All"). An id that no longer names
    /// a workspace falls back to "All".
    func setActive(_ id: UUID?) {
        let normalized = normalizedActive(id, in: workspaces)
        guard normalized != activeWorkspaceId else { return }
        activeWorkspaceId = normalized
        save()
    }

    // MARK: - Mutations

    @discardableResult
    func create(name: String) -> Workspace {
        let workspace = Workspace(name: name)
        workspaces.append(workspace)
        save()
        return workspace
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[idx].name = name
        save()
    }

    func delete(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        workspaces.removeAll { $0.id == id }
        if activeWorkspaceId == id { activeWorkspaceId = nil }  // fall back to "All"
        save()
    }

    func add(repoId: UUID, to workspaceId: UUID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        guard !workspaces[idx].repoIds.contains(repoId) else { return }
        workspaces[idx].repoIds.append(repoId)
        save()
    }

    func remove(repoId: UUID, from workspaceId: UUID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        guard workspaces[idx].repoIds.contains(repoId) else { return }
        workspaces[idx].repoIds.removeAll { $0 == repoId }
        save()
    }

    /// Remove a repo from every workspace. Called when a repository is deleted so
    /// no stale membership lingers. (Filtering already tolerates stale ids; this
    /// keeps the file tidy.)
    func removeRepoFromAll(repoId: UUID) {
        var changed = false
        for idx in workspaces.indices where workspaces[idx].repoIds.contains(repoId) {
            workspaces[idx].repoIds.removeAll { $0 == repoId }
            changed = true
        }
        if changed { save() }
    }
}
