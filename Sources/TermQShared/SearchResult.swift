import Foundation

/// A harness search result decoded from `ynh search <term> --format json`.
public struct SearchResult: Codable, Sendable, Identifiable {
    public var id: String { "\(from.type.rawValue):\(from.name):\(name)" }
    public let name: String
    public let description: String?
    public let keywords: [String]?
    public let repo: String?
    public let path: String?
    public let vendors: [String]?
    public let version: String?
    public let from: SearchOrigin
}

/// Origin annotation — identifies which registry or local source a search result came from.
public struct SearchOrigin: Codable, Sendable {
    public let type: OriginType
    public let name: String
}

public enum OriginType: String, Codable, Sendable {
    case registry
    case source
}
