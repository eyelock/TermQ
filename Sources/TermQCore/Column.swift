import Foundation

/// Represents a Kanban column
public class Column: Identifiable, ObservableObject, Codable {
    public let id: UUID
    @Published public var name: String
    @Published public var orderIndex: Int
    @Published public var color: String  // Hex color string

    enum CodingKeys: String, CodingKey {
        case id, name, orderIndex, color
    }

    public init(
        id: UUID = UUID(),
        name: String,
        orderIndex: Int,
        color: String = "#6B7280"
    ) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.color = color
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        color = try container.decode(String.self, forKey: .color)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(orderIndex, forKey: .orderIndex)
        try container.encode(color, forKey: .color)
    }

    public static var defaults: [Column] {
        [
            Column(name: "To Do", orderIndex: 0, color: "#6B7280"),
            Column(name: "In Progress", orderIndex: 1, color: "#3B82F6"),
            Column(name: "Blocked", orderIndex: 2, color: "#EF4444"),
            Column(name: "Done", orderIndex: 3, color: "#10B981"),
        ]
    }
}

// MARK: - Equatable

extension Column: Equatable {
    public static func == (lhs: Column, rhs: Column) -> Bool {
        lhs.id == rhs.id
    }
}
