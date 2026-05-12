import Foundation

/// A GitHub pull request fetched via `gh pr list --format json`.
public struct GitHubPR: Sendable, Codable, Identifiable {
    public let number: Int
    public let title: String
    /// The branch name on the source repository.
    public let headRefName: String
    /// The commit SHA at the PR head. Used as the primary match key against local worktrees.
    public let headRefOid: String
    public let author: GitHubUser
    /// True for cross-repository (fork) PRs. `gh pr checkout` uses `<login>-<branch>`
    /// naming for these to avoid collisions with same-named branches upstream.
    public let isCrossRepository: Bool
    public let isDraft: Bool
    /// Users from whom a review has been requested.
    public let reviewRequests: [GitHubReviewRequest]
    public let assignees: [GitHubUser]
    /// When the PR was last updated. Used for recency ordering within priority tiers.
    public let updatedAt: Date

    public var id: Int { number }

    /// The local branch name `gh pr checkout` will create.
    /// For same-repo PRs this is `headRefName`. For fork PRs it's `<author.login>-<headRefName>`.
    public func localBranchName() -> String {
        isCrossRepository ? "\(author.login)-\(headRefName)" : headRefName
    }

    enum CodingKeys: String, CodingKey {
        case number, title, author, assignees
        case headRefName, headRefOid, isCrossRepository, isDraft, reviewRequests, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        headRefName = try c.decode(String.self, forKey: .headRefName)
        headRefOid = try c.decode(String.self, forKey: .headRefOid)
        author = try c.decode(GitHubUser.self, forKey: .author)
        isCrossRepository = try c.decode(Bool.self, forKey: .isCrossRepository)
        isDraft = try c.decode(Bool.self, forKey: .isDraft)
        reviewRequests = (try? c.decode([GitHubReviewRequest].self, forKey: .reviewRequests)) ?? []
        assignees = (try? c.decode([GitHubUser].self, forKey: .assignees)) ?? []
        // gh emits ISO 8601 with Z suffix; fall back to epoch so sorting degrades gracefully.
        if let raw = try? c.decode(String.self, forKey: .updatedAt),
            let date = ISO8601DateFormatter().date(from: raw)
        {
            updatedAt = date
        } else {
            updatedAt = Date(timeIntervalSince1970: 0)
        }
    }
}

/// A GitHub user (author, assignee, etc.).
public struct GitHubUser: Sendable, Codable, Equatable {
    public let login: String

    public init(login: String) {
        self.login = login
    }
}

/// A review request entry (the requested reviewer).
public struct GitHubReviewRequest: Sendable, Codable {
    public let login: String

    enum CodingKeys: String, CodingKey {
        case login
    }

    public init(from decoder: Decoder) throws {
        // gh pr list emits reviewRequests as an array of objects with a nested
        // actor object: [{"requestedReviewer": {"login": "..."}}] or similar.
        // The CLI actually emits [{"login": "..."}] at the top level when --json
        // reviewRequests is requested. Accept both shapes gracefully.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        login = try c.decode(String.self, forKey: .login)
    }
}

/// Role badges a PR can carry relative to the current authenticated user.
public struct PRRoleBadges: Sendable, Equatable {
    public var isAuthor: Bool
    public var isReviewRequested: Bool
    public var isAssigned: Bool
    public var isDraft: Bool
    public var isCheckedOut: Bool

    public init(
        isAuthor: Bool = false,
        isReviewRequested: Bool = false,
        isAssigned: Bool = false,
        isDraft: Bool = false,
        isCheckedOut: Bool = false
    ) {
        self.isAuthor = isAuthor
        self.isReviewRequested = isReviewRequested
        self.isAssigned = isAssigned
        self.isDraft = isDraft
        self.isCheckedOut = isCheckedOut
    }
}

/// A candidate PR row/worktree for the "Prune Closed PRs" confirmation sheet.
public struct PRPruneCandidate: Sendable, Identifiable {
    public let prNumber: Int
    /// Path of the locally checked-out worktree, if any.
    public let worktreePath: String?
    public let isDirty: Bool
    public let aheadCount: Int

    public var id: Int { prNumber }
    public var canPrune: Bool { !isDirty && aheadCount == 0 }

    public init(prNumber: Int, worktreePath: String?, isDirty: Bool, aheadCount: Int) {
        self.prNumber = prNumber
        self.worktreePath = worktreePath
        self.isDirty = isDirty
        self.aheadCount = aheadCount
    }
}

/// A focus worktree created by TermQ for reviewing a remote PR without a permanent checkout.
///
/// Focus worktrees live under `~/.termq/focus-worktrees/` and are always prunable — they carry
/// no uncommitted work by design.
public struct FocusWorktreeCandidate: Sendable, Identifiable {
    public let path: String
    public var id: String { path }
    public var displayName: String { URL(fileURLWithPath: path).lastPathComponent }

    public init(path: String) { self.path = path }
}

/// The result of matching PRs against local worktrees for a repo.
public struct PRWorktreeMatch: Sendable {
    /// The PR number.
    public let prNumber: Int
    /// The local worktree path that matches this PR's head, if checked out.
    public let worktreePath: String?

    public var isCheckedOut: Bool { worktreePath != nil }

    public init(prNumber: Int, worktreePath: String?) {
        self.prNumber = prNumber
        self.worktreePath = worktreePath
    }
}
