import Foundation

/// Metadata tag for a terminal card (shared across CLI and MCP)
public struct Tag: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let key: String
    public let value: String

    public init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}
