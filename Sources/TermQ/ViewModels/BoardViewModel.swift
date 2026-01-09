import Foundation
import SwiftUI
import TermQCore

@MainActor
class BoardViewModel: ObservableObject {
    @Published var board: Board
    @Published var selectedCard: TerminalCard?
    @Published var isEditingCard: TerminalCard?
    @Published var isEditingColumn: Column?

    private let saveURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let termqDir = appSupport.appendingPathComponent("TermQ", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: termqDir, withIntermediateDirectories: true)

        self.saveURL = termqDir.appendingPathComponent("board.json")

        // Try to load saved board
        if let data = try? Data(contentsOf: saveURL),
            let loaded = try? JSONDecoder().decode(Board.self, from: data)
        {
            self.board = loaded
        } else {
            self.board = Board()
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(board)
            try data.write(to: saveURL)
        } catch {
            print("Failed to save board: \(error)")
        }
    }

    func addTerminal(to column: Column) {
        let card = board.addCard(to: column)
        objectWillChange.send()
        save()

        // Open it for editing
        isEditingCard = card
    }

    func deleteCard(_ card: TerminalCard) {
        if selectedCard?.id == card.id {
            selectedCard = nil
        }
        // Clean up terminal session
        TerminalSessionManager.shared.removeSession(for: card.id)
        board.removeCard(card)
        objectWillChange.send()
        save()
    }

    func moveCard(_ card: TerminalCard, to column: Column) {
        let targetCards = board.cards(for: column)
        board.moveCard(card, to: column, at: targetCards.count)
        objectWillChange.send()
        save()
    }

    func selectCard(_ card: TerminalCard) {
        selectedCard = card
    }

    func deselectCard() {
        selectedCard = nil
    }

    func addColumn() {
        let column = board.addColumn(name: "New Column")
        objectWillChange.send()
        save()
        isEditingColumn = column
    }

    /// Check if a column can be deleted (must be empty)
    func canDeleteColumn(_ column: Column) -> Bool {
        return board.cards(for: column).isEmpty
    }

    func deleteColumn(_ column: Column) {
        // Only delete if column is empty
        guard canDeleteColumn(column) else { return }
        board.removeColumn(column)
        objectWillChange.send()
        save()
    }

    func updateCard(_ card: TerminalCard) {
        objectWillChange.send()
        save()
    }

    func updateColumn(_ column: Column) {
        objectWillChange.send()
        save()
    }

    // MARK: - Pinned Cards

    var pinnedCards: [TerminalCard] {
        board.cards.filter { $0.isPinned }
    }

    func togglePin(_ card: TerminalCard) {
        card.isPinned.toggle()
        objectWillChange.send()
        save()
    }
}
