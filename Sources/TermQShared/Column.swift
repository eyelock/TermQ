import Foundation

/// Represents a Kanban column (shared across CLI and MCP)
public struct Column: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public let orderIndex: Int
    public let color: String

    /// Memberwise initializer
    public init(id: UUID = UUID(), name: String, description: String = "", orderIndex: Int, color: String = "#6B7280") {
        self.id = id
        self.name = name
        self.description = description
        self.orderIndex = orderIndex
        self.color = color
    }

    // Custom decoding for backwards compatibility with older board.json files
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex) ?? 0
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#6B7280"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, orderIndex, color
    }
}
