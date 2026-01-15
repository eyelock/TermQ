import Foundation
import XCTest

@testable import TermQCore

final class BoardTests: XCTestCase {
    func testInitializationWithDefaults() {
        let board = Board()

        XCTAssertEqual(board.columns.count, 4)  // Default columns
        XCTAssertTrue(board.cards.isEmpty)
    }

    func testInitializationWithCustomColumns() {
        let columns = [
            Column(name: "A", orderIndex: 0),
            Column(name: "B", orderIndex: 1),
        ]
        let board = Board(columns: columns, cards: [])

        XCTAssertEqual(board.columns.count, 2)
        XCTAssertEqual(board.columns[0].name, "A")
        XCTAssertEqual(board.columns[1].name, "B")
    }

    func testCardsForColumn() {
        let column1 = Column(name: "Col1", orderIndex: 0)
        let column2 = Column(name: "Col2", orderIndex: 1)

        let card1 = TerminalCard(title: "Card1", columnId: column1.id, orderIndex: 0)
        let card2 = TerminalCard(title: "Card2", columnId: column1.id, orderIndex: 1)
        let card3 = TerminalCard(title: "Card3", columnId: column2.id, orderIndex: 0)

        let board = Board(columns: [column1, column2], cards: [card1, card2, card3])

        let col1Cards = board.cards(for: column1)
        XCTAssertEqual(col1Cards.count, 2)
        XCTAssertEqual(col1Cards[0].title, "Card1")
        XCTAssertEqual(col1Cards[1].title, "Card2")

        let col2Cards = board.cards(for: column2)
        XCTAssertEqual(col2Cards.count, 1)
        XCTAssertEqual(col2Cards[0].title, "Card3")
    }

    func testCardsForColumnSorted() {
        let column = Column(name: "Test", orderIndex: 0)

        let card1 = TerminalCard(title: "Third", columnId: column.id, orderIndex: 2)
        let card2 = TerminalCard(title: "First", columnId: column.id, orderIndex: 0)
        let card3 = TerminalCard(title: "Second", columnId: column.id, orderIndex: 1)

        let board = Board(columns: [column], cards: [card1, card2, card3])

        let cards = board.cards(for: column)
        XCTAssertEqual(cards[0].title, "First")
        XCTAssertEqual(cards[1].title, "Second")
        XCTAssertEqual(cards[2].title, "Third")
    }

    func testAddCardToColumn() {
        let column = Column(name: "Test", orderIndex: 0)
        let board = Board(columns: [column], cards: [])

        let card = board.addCard(to: column, title: "New Card")

        XCTAssertEqual(board.cards.count, 1)
        XCTAssertEqual(card.title, "New Card")
        XCTAssertEqual(card.columnId, column.id)
        XCTAssertEqual(card.orderIndex, 0)
    }

    func testAddCardIncrementsOrderIndex() {
        let column = Column(name: "Test", orderIndex: 0)
        let board = Board(columns: [column], cards: [])

        let card1 = board.addCard(to: column, title: "First")
        let card2 = board.addCard(to: column, title: "Second")
        let card3 = board.addCard(to: column, title: "Third")

        XCTAssertEqual(card1.orderIndex, 0)
        XCTAssertEqual(card2.orderIndex, 1)
        XCTAssertEqual(card3.orderIndex, 2)
    }

    func testMoveCardToDifferentColumn() {
        let column1 = Column(name: "Source", orderIndex: 0)
        let column2 = Column(name: "Target", orderIndex: 1)

        let card = TerminalCard(title: "Moving Card", columnId: column1.id, orderIndex: 0)
        let board = Board(columns: [column1, column2], cards: [card])

        board.moveCard(card, to: column2, at: 0)

        XCTAssertEqual(card.columnId, column2.id)
        XCTAssertTrue(board.cards(for: column1).isEmpty)
        XCTAssertEqual(board.cards(for: column2).count, 1)
    }

    func testMoveCardReordersTargetColumn() {
        let column1 = Column(name: "Source", orderIndex: 0)
        let column2 = Column(name: "Target", orderIndex: 1)

        let existingCard = TerminalCard(title: "Existing", columnId: column2.id, orderIndex: 0)
        let movingCard = TerminalCard(title: "Moving", columnId: column1.id, orderIndex: 0)

        let board = Board(columns: [column1, column2], cards: [existingCard, movingCard])

        board.moveCard(movingCard, to: column2, at: 0)

        let targetCards = board.cards(for: column2)
        XCTAssertEqual(targetCards.count, 2)
        XCTAssertEqual(targetCards[0].title, "Moving")  // Inserted at position 0
        XCTAssertEqual(targetCards[1].title, "Existing")
    }

    func testMoveCardWithinSameColumnForward() {
        let column = Column(name: "Test", orderIndex: 0)

        let cardA = TerminalCard(title: "A", columnId: column.id, orderIndex: 0)
        let cardB = TerminalCard(title: "B", columnId: column.id, orderIndex: 1)
        let cardC = TerminalCard(title: "C", columnId: column.id, orderIndex: 2)

        let board = Board(columns: [column], cards: [cardA, cardB, cardC])

        // Move A to position 2 (before C, so A should end up between B and C)
        board.moveCard(cardA, to: column, at: 2)

        let cards = board.cards(for: column)
        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(cards[0].title, "B")
        XCTAssertEqual(cards[1].title, "A")  // A moved forward to before C
        XCTAssertEqual(cards[2].title, "C")
    }

    func testMoveCardWithinSameColumnBackward() {
        let column = Column(name: "Test", orderIndex: 0)

        let cardA = TerminalCard(title: "A", columnId: column.id, orderIndex: 0)
        let cardB = TerminalCard(title: "B", columnId: column.id, orderIndex: 1)
        let cardC = TerminalCard(title: "C", columnId: column.id, orderIndex: 2)

        let board = Board(columns: [column], cards: [cardA, cardB, cardC])

        // Move C to position 0 (before A)
        board.moveCard(cardC, to: column, at: 0)

        let cards = board.cards(for: column)
        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(cards[0].title, "C")  // C moved to front
        XCTAssertEqual(cards[1].title, "A")
        XCTAssertEqual(cards[2].title, "B")
    }

    func testMoveCardToSamePositionNoChange() {
        let column = Column(name: "Test", orderIndex: 0)

        let cardA = TerminalCard(title: "A", columnId: column.id, orderIndex: 0)
        let cardB = TerminalCard(title: "B", columnId: column.id, orderIndex: 1)

        let board = Board(columns: [column], cards: [cardA, cardB])

        // Move A to position 0 (same position)
        board.moveCard(cardA, to: column, at: 0)

        let cards = board.cards(for: column)
        XCTAssertEqual(cards[0].title, "A")
        XCTAssertEqual(cards[1].title, "B")
    }

    func testRemoveCard() {
        let column = Column(name: "Test", orderIndex: 0)
        let card = TerminalCard(title: "To Remove", columnId: column.id)
        let board = Board(columns: [column], cards: [card])

        board.removeCard(card)

        XCTAssertTrue(board.cards.isEmpty)
    }

    func testAddColumn() {
        let board = Board(columns: [], cards: [])

        let column = board.addColumn(name: "New Column")

        XCTAssertEqual(board.columns.count, 1)
        XCTAssertEqual(column.name, "New Column")
        XCTAssertEqual(column.orderIndex, 0)
    }

    func testAddColumnIncrementsOrderIndex() {
        let board = Board(columns: [], cards: [])

        let col1 = board.addColumn(name: "First")
        let col2 = board.addColumn(name: "Second")

        XCTAssertEqual(col1.orderIndex, 0)
        XCTAssertEqual(col2.orderIndex, 1)
    }

    func testRemoveColumnMovesCards() {
        let column1 = Column(name: "First", orderIndex: 0)
        let column2 = Column(name: "Second", orderIndex: 1)

        let card = TerminalCard(title: "Card", columnId: column2.id)
        let board = Board(columns: [column1, column2], cards: [card])

        board.removeColumn(column2)

        XCTAssertEqual(board.columns.count, 1)
        XCTAssertEqual(board.columns[0].name, "First")
        XCTAssertEqual(card.columnId, column1.id)  // Moved to first column
    }

    func testRemoveLastColumnDeletesCards() {
        let column = Column(name: "Only", orderIndex: 0)
        let card = TerminalCard(title: "Card", columnId: column.id)
        let board = Board(columns: [column], cards: [card])

        board.removeColumn(column)

        XCTAssertTrue(board.columns.isEmpty)
        XCTAssertTrue(board.cards.isEmpty)  // Card deleted with column
    }

    func testCodableRoundTrip() throws {
        let column = Column(name: "Test Column", orderIndex: 0)
        let card = TerminalCard(title: "Test Card", columnId: column.id)
        let original = Board(columns: [column], cards: [card])

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Board.self, from: data)

        XCTAssertEqual(decoded.columns.count, 1)
        XCTAssertEqual(decoded.columns[0].name, "Test Column")
        XCTAssertEqual(decoded.cards.count, 1)
        XCTAssertEqual(decoded.cards[0].title, "Test Card")
    }
}
