import Foundation

/// A git worktree discovered from `git worktree list --porcelain` (shared across CLI and MCP)
///
/// `id` is path-derived so Codable synthesis must exclude it — see CodingKeys.
public struct GitWorktree: Sendable, Identifiable {
    /// Path-derived identity — unique per repository
    public var id: String { path }

    /// Absolute path to the worktree directory
    public let path: String

    /// Checked-out branch name (nil for detached HEAD or bare repositories)
    public let branch: String?

    /// Abbreviated HEAD commit hash (first 8 characters)
    public let commitHash: String

    /// Whether this is the main (primary) worktree
    public let isMainWorktree: Bool

    /// Whether the worktree is locked (`git worktree lock`)
    public let isLocked: Bool

    /// Whether the worktree has uncommitted changes (staged or unstaged)
    public let isDirty: Bool

    public init(
        path: String,
        branch: String?,
        commitHash: String,
        isMainWorktree: Bool,
        isLocked: Bool,
        isDirty: Bool = false
    ) {
        self.path = path
        self.branch = branch
        self.commitHash = commitHash
        self.isMainWorktree = isMainWorktree
        self.isLocked = isLocked
        self.isDirty = isDirty
    }
}

// MARK: - Codable

extension GitWorktree: Codable {
    enum CodingKeys: String, CodingKey {
        case path, branch, commitHash, isMainWorktree, isLocked, isDirty
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        commitHash = try c.decode(String.self, forKey: .commitHash)
        isMainWorktree = try c.decode(Bool.self, forKey: .isMainWorktree)
        isLocked = try c.decode(Bool.self, forKey: .isLocked)
        isDirty = try c.decodeIfPresent(Bool.self, forKey: .isDirty) ?? false
    }
}
