import Foundation
import SwiftUI
import TermQCore

@MainActor
class BoardViewModel: ObservableObject {
    @Published var board: Board
    @Published var selectedCard: TerminalCard?
    @Published var isEditingCard: TerminalCard?
    @Published var isEditingNewCard: Bool = false
    @Published var isEditingColumn: Column?
    @Published var showDeleteConfirmation: Bool = false

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
        isEditingNewCard = true
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

    /// Delete a pinned card and stay in focused view if possible
    /// Selects the tab to the left, or next available pinned tab, or goes to board if none left
    func deletePinnedCard(_ card: TerminalCard) {
        let pinned = pinnedCards
        let cardIndex = pinned.firstIndex(where: { $0.id == card.id })

        // Determine which card to select after deletion
        var nextCard: TerminalCard?
        if let index = cardIndex {
            // Try to select the tab to the left
            if index > 0 {
                nextCard = pinned[index - 1]
            } else if pinned.count > 1 {
                // If deleting first tab, select the next one
                nextCard = pinned[1]
            }
        }

        // Clean up terminal session
        TerminalSessionManager.shared.removeSession(for: card.id)
        board.removeCard(card)
        objectWillChange.send()
        save()

        // Select the next card, or go to board if none left
        if let next = nextCard, next.id != card.id {
            selectedCard = next
        } else {
            // Check if there are any remaining pinned cards
            let remainingPinned = pinnedCards
            if let first = remainingPinned.first {
                selectedCard = first
            } else {
                selectedCard = nil  // Go to board view
            }
        }
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

    /// Cards to show as tabs - pinned cards plus current card if not pinned
    var tabCards: [TerminalCard] {
        var tabs = pinnedCards
        // Add current card if it's not already pinned
        if let current = selectedCard, !current.isPinned {
            tabs.append(current)
        }
        return tabs
    }

    func togglePin(_ card: TerminalCard) {
        card.isPinned.toggle()
        objectWillChange.send()
        save()
    }

    // MARK: - Quick Actions

    /// Create a new terminal immediately without showing the editor dialog
    /// Uses current terminal's column and working directory if available
    func quickNewTerminal() {
        // Determine column and working directory
        let column: Column
        let workingDirectory: String

        if let current = selectedCard,
            let currentColumn = board.columns.first(where: { $0.id == current.columnId })
        {
            column = currentColumn
            workingDirectory = current.workingDirectory
        } else if let firstColumn = board.columns.first {
            column = firstColumn
            workingDirectory = NSHomeDirectory()
        } else {
            return  // No columns available
        }

        // Generate a unique title
        let existingTitles = Set(board.cards.map { $0.title })
        var counter = 1
        var title = "Terminal \(counter)"
        while existingTitles.contains(title) {
            counter += 1
            title = "Terminal \(counter)"
        }

        // Create the card
        let card = board.addCard(to: column, title: title)
        card.workingDirectory = workingDirectory

        // If created from focused view, auto-pin so it appears as a tab
        if selectedCard != nil {
            card.isPinned = true
        }

        objectWillChange.send()
        save()

        // Switch to the new terminal immediately
        selectCard(card)
    }

    /// Switch to the next pinned terminal (cycles through)
    func nextPinnedTerminal() {
        let pinned = pinnedCards
        guard !pinned.isEmpty else { return }

        if let current = selectedCard,
            let currentIndex = pinned.firstIndex(where: { $0.id == current.id })
        {
            let nextIndex = (currentIndex + 1) % pinned.count
            selectCard(pinned[nextIndex])
        } else if let first = pinned.first {
            selectCard(first)
        }
    }

    /// Switch to the previous pinned terminal (cycles through)
    func previousPinnedTerminal() {
        let pinned = pinnedCards
        guard !pinned.isEmpty else { return }

        if let current = selectedCard,
            let currentIndex = pinned.firstIndex(where: { $0.id == current.id })
        {
            let prevIndex = currentIndex == 0 ? pinned.count - 1 : currentIndex - 1
            selectCard(pinned[prevIndex])
        } else if let last = pinned.last {
            selectCard(last)
        }
    }
}
