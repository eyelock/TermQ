import Foundation

/// A configured local harness source decoded from `ynh sources list --format json`.
public struct YNHSource: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let path: String
    public let description: String?
    public let harnesses: Int
}
