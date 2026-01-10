import Foundation

/// Represents the entire board state
public class Board: ObservableObject, Codable {
    @Published public var columns: [Column]
    @Published public var cards: [TerminalCard]
    /// Persisted order of favourite tabs
    @Published public var favouriteOrder: [UUID]

    enum CodingKeys: String, CodingKey {
        case columns, cards, favouriteOrder
    }

    public init(columns: [Column] = Column.defaults, cards: [TerminalCard] = [], favouriteOrder: [UUID] = []) {
        self.columns = columns
        self.cards = cards
        self.favouriteOrder = favouriteOrder
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columns = try container.decode([Column].self, forKey: .columns)
        cards = try container.decode([TerminalCard].self, forKey: .cards)
        favouriteOrder = try container.decodeIfPresent([UUID].self, forKey: .favouriteOrder) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(columns, forKey: .columns)
        try container.encode(cards, forKey: .cards)
        try container.encode(favouriteOrder, forKey: .favouriteOrder)
    }

    public func cards(for column: Column) -> [TerminalCard] {
        cards.filter { $0.columnId == column.id }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    @discardableResult
    public func addCard(to column: Column, title: String = "New Terminal") -> TerminalCard {
        let maxIndex = cards(for: column).map(\.orderIndex).max() ?? -1
        let card = TerminalCard(
            title: title,
            columnId: column.id,
            orderIndex: maxIndex + 1
        )
        cards.append(card)
        return card
    }

    public func moveCard(_ card: TerminalCard, to column: Column, at index: Int) {
        card.columnId = column.id

        // Reorder cards in the target column
        var columnCards = cards(for: column).filter { $0.id != card.id }
        columnCards.insert(card, at: min(index, columnCards.count))

        for (i, c) in columnCards.enumerated() {
            c.orderIndex = i
        }
    }

    public func removeCard(_ card: TerminalCard) {
        cards.removeAll { $0.id == card.id }
    }

    @discardableResult
    public func addColumn(name: String) -> Column {
        let maxIndex = columns.map(\.orderIndex).max() ?? -1
        let column = Column(name: name, orderIndex: maxIndex + 1)
        columns.append(column)
        return column
    }

    public func removeColumn(_ column: Column) {
        // Move cards to first column or delete them
        if let firstColumn = columns.first(where: { $0.id != column.id }) {
            for card in cards(for: column) {
                card.columnId = firstColumn.id
            }
        } else {
            cards.removeAll { $0.columnId == column.id }
        }
        columns.removeAll { $0.id == column.id }
    }

    /// Move a column to a new position
    public func moveColumn(_ column: Column, to targetIndex: Int) {
        guard let currentIndex = columns.firstIndex(where: { $0.id == column.id }) else { return }
        guard currentIndex != targetIndex else { return }

        columns.remove(at: currentIndex)
        let insertIndex = min(targetIndex, columns.count)
        columns.insert(column, at: insertIndex)

        // Update order indices
        for (i, col) in columns.enumerated() {
            col.orderIndex = i
        }
    }
}
