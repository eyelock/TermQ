import Foundation

/// A git repository registered in TermQ's sidebar (shared across CLI and MCP)
public struct GitRepository: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var path: String
    public var worktreeBasePath: String?
    public let addedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        worktreeBasePath: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.worktreeBasePath = worktreeBasePath
        self.addedAt = addedAt
    }
}
