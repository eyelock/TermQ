import Foundation

/// Persisted repository configuration stored in `repos.json` (shared across CLI and MCP)
public struct RepoConfig: Codable, Sendable {
    public var repositories: [GitRepository]

    public init(repositories: [GitRepository] = []) {
        self.repositories = repositories
    }
}
