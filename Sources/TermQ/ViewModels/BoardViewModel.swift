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

    /// Session tabs - ordered list of card IDs currently open as tabs (not persisted)
    /// Initialized from favourites on startup, then tracks what's open during the session
    @Published private(set) var sessionTabs: [UUID] = []

    /// Tabs that need attention (received a bell) - cleared when selected
    @Published private(set) var needsAttention: Set<UUID> = []

    /// Terminals currently processing (have recent output activity)
    @Published private(set) var processingCards: Set<UUID> = []

    /// Transient terminals - not persisted, exist only as tabs until promoted
    /// Promoted to board when: edited & saved, or marked as favourite
    private var transientCards: [UUID: TerminalCard] = [:]

    /// Timer for updating processing status
    private var processingTimer: Timer?

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

        // Initialize session tabs from persisted favourite order
        // Filter to only include existing favourite cards
        let favouriteIds = Set(board.cards.filter { $0.isFavourite }.map { $0.id })
        sessionTabs = board.favouriteOrder.filter { favouriteIds.contains($0) }

        // Add any favourites not in the order (e.g., newly favourited while order wasn't saved)
        for card in board.cards where card.isFavourite && !sessionTabs.contains(card.id) {
            sessionTabs.append(card.id)
        }

        // Start timer to periodically update processing status
        startProcessingTimer()
    }

    /// Start timer to update processing status
    private func startProcessingTimer() {
        processingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProcessingStatus()
            }
        }
    }

    /// Refresh which cards are currently processing
    private func refreshProcessingStatus() {
        let newProcessing = TerminalSessionManager.shared.processingCardIds()
        if newProcessing != processingCards {
            processingCards = newProcessing
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
        // Remove from session tabs
        sessionTabs.removeAll { $0 == card.id }

        if selectedCard?.id == card.id {
            selectedCard = nil
        }
        // Clean up terminal session
        TerminalSessionManager.shared.removeSession(for: card.id)
        board.removeCard(card)
        objectWillChange.send()
        save()
    }

    /// Delete a tab card and stay in focused view if possible
    /// Selects the tab to the left, or next available tab, or goes to board if none left
    func deleteTabCard(_ card: TerminalCard) {
        let tabs = tabCards
        let cardIndex = tabs.firstIndex(where: { $0.id == card.id })

        // Determine which card to select after deletion
        var nextCard: TerminalCard?
        if let index = cardIndex {
            // Try to select the tab to the left
            if index > 0 {
                nextCard = tabs[index - 1]
            } else if tabs.count > 1 {
                // If deleting first tab, select the next one
                nextCard = tabs[1]
            }
        }

        // Remove from session tabs
        sessionTabs.removeAll { $0 == card.id }

        // Clean up terminal session
        TerminalSessionManager.shared.removeSession(for: card.id)

        // Remove from appropriate storage
        if card.isTransient {
            transientCards.removeValue(forKey: card.id)
        } else {
            board.removeCard(card)
            save()
        }

        objectWillChange.send()

        // Select the next card, or go to board if none left
        if let next = nextCard, next.id != card.id {
            selectedCard = next
        } else {
            // Check if there are any remaining tabs
            if let first = tabCards.first {
                selectedCard = first
            } else {
                selectedCard = nil  // Go to board view
            }
        }
    }

    /// Close a tab without deleting the terminal card (unless transient)
    /// Transient cards are removed entirely when closed
    /// Removes from session tabs and selects adjacent tab
    func closeTab(_ card: TerminalCard) {
        let tabs = tabCards
        let cardIndex = tabs.firstIndex(where: { $0.id == card.id })

        // Determine which card to select after closing
        var nextCard: TerminalCard?
        if let index = cardIndex {
            if index > 0 {
                nextCard = tabs[index - 1]
            } else if tabs.count > 1 {
                nextCard = tabs[1]
            }
        }

        // Remove from session tabs
        sessionTabs.removeAll { $0 == card.id }

        // If transient, remove the card entirely (it was never persisted)
        if card.isTransient {
            transientCards.removeValue(forKey: card.id)
            TerminalSessionManager.shared.removeSession(for: card.id)
        }

        objectWillChange.send()

        // Select the next card, or go to board if none left
        if let next = nextCard, next.id != card.id {
            selectedCard = next
        } else if let first = tabCards.first {
            selectedCard = first
        } else {
            selectedCard = nil  // Go to board view
        }
    }

    /// Close all tabs that are not favourites
    /// Transient (non-favourite) tabs are removed entirely
    func closeUnfavouritedTabs() {
        let favouriteIds = Set(board.cards.filter { $0.isFavourite }.map { $0.id })

        // Find transient cards to remove
        let transientToRemove = sessionTabs.filter { transientCards[$0] != nil }
        for id in transientToRemove {
            transientCards.removeValue(forKey: id)
            TerminalSessionManager.shared.removeSession(for: id)
        }

        sessionTabs = sessionTabs.filter { favouriteIds.contains($0) }

        // If current selection is no longer in tabs, select first tab or go to board
        if let current = selectedCard, !sessionTabs.contains(current.id) {
            if let first = tabCards.first {
                selectedCard = first
            } else {
                selectedCard = nil
            }
        }
        objectWillChange.send()
    }

    func moveCard(_ card: TerminalCard, to column: Column) {
        let targetCards = board.cards(for: column)
        board.moveCard(card, to: column, at: targetCards.count)
        objectWillChange.send()
        save()
    }

    /// Select a card and add it to session tabs if entering focused mode
    func selectCard(_ card: TerminalCard) {
        selectedCard = card
        // Add to session tabs if not already there
        if !sessionTabs.contains(card.id) {
            sessionTabs.append(card.id)
        }
        // Clear attention indicator when tab is selected
        needsAttention.remove(card.id)
    }

    /// Mark a tab as needing attention (e.g., from terminal bell)
    func markNeedsAttention(_ cardId: UUID) {
        // Only mark if not the currently selected card
        if selectedCard?.id != cardId {
            needsAttention.insert(cardId)
        }
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

    /// Update a card's details
    /// If updating a transient card, promotes it to persistent (user intentionally edited it)
    func updateCard(_ card: TerminalCard) {
        // Promote transient card when user edits it
        if card.isTransient {
            promoteTransientCard(card)
        }

        objectWillChange.send()
        save()
    }

    func updateColumn(_ column: Column) {
        objectWillChange.send()
        save()
    }

    // MARK: - Favourites

    /// Cards marked as favourites (persisted, restored on app restart)
    var favouriteCards: [TerminalCard] {
        board.cards.filter { $0.isFavourite }
    }

    /// Toggle favourite status for a card
    /// If marking a transient card as favourite, promotes it to persistent
    func toggleFavourite(_ card: TerminalCard) {
        card.isFavourite.toggle()

        // If marking as favourite, promote transient card to persistent
        if card.isFavourite && card.isTransient {
            promoteTransientCard(card)
        }

        // If marking as favourite, ensure it's in session tabs
        if card.isFavourite && !sessionTabs.contains(card.id) {
            sessionTabs.append(card.id)
        }

        // Update persisted favourite order
        updateFavouriteOrder()

        objectWillChange.send()
        save()
    }

    // MARK: - Session Tabs

    /// Cards to show as tabs - based on sessionTabs order
    /// Includes both persisted (board) and transient cards
    var tabCards: [TerminalCard] {
        sessionTabs.compactMap { id in
            // Check transient cards first, then board cards
            transientCards[id] ?? board.cards.first { $0.id == id }
        }
    }

    /// Look up a card by ID (from board or transient)
    func card(for id: UUID) -> TerminalCard? {
        transientCards[id] ?? board.cards.first { $0.id == id }
    }

    /// Move a tab from one position to another
    func moveTab(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
            fromIndex >= 0, fromIndex < sessionTabs.count,
            toIndex >= 0, toIndex < sessionTabs.count
        else { return }

        let movedId = sessionTabs.remove(at: fromIndex)
        sessionTabs.insert(movedId, at: toIndex)

        updateFavouriteOrder()
        objectWillChange.send()
        save()
    }

    /// Move a tab by card ID to a new index
    func moveTab(_ cardId: UUID, toIndex: Int) {
        guard let fromIndex = sessionTabs.firstIndex(of: cardId) else { return }
        moveTab(fromIndex: fromIndex, toIndex: toIndex)
    }

    /// Update the persisted favourite order from current session tabs
    private func updateFavouriteOrder() {
        // Only persist the order of favourited tabs
        let favouriteIds = Set(board.cards.filter { $0.isFavourite }.map { $0.id })
        board.favouriteOrder = sessionTabs.filter { favouriteIds.contains($0) }
    }

    // MARK: - Quick Actions

    /// Create a new transient terminal immediately without showing the editor dialog
    /// Transient terminals are not saved to the board until edited or favourited
    /// Uses current terminal's column and working directory if available
    func quickNewTerminal() {
        // Determine column and working directory
        let column: Column
        let workingDirectory: String

        if let current = selectedCard,
            let currentColumn = board.columns.first(where: { $0.id == current.columnId })
        {
            column = currentColumn
            // Use tracked current directory if available
            workingDirectory =
                TerminalSessionManager.shared.getCurrentDirectory(for: current.id)
                ?? current.workingDirectory
        } else if let firstColumn = board.columns.first {
            column = firstColumn
            workingDirectory = NSHomeDirectory()
        } else {
            return  // No columns available
        }

        // Generate a unique title (check both board and transient cards)
        let existingTitles = Set(board.cards.map { $0.title } + transientCards.values.map { $0.title })
        var counter = 1
        var title = "Terminal \(counter)"
        while existingTitles.contains(title) {
            counter += 1
            title = "Terminal \(counter)"
        }

        // Create a transient card (not added to board)
        let card = TerminalCard(
            title: title,
            columnId: column.id,
            workingDirectory: workingDirectory
        )
        card.isTransient = true
        transientCards[card.id] = card

        // Insert tab after current tab (or at end if no selection)
        if let current = selectedCard,
            let currentIndex = sessionTabs.firstIndex(of: current.id)
        {
            sessionTabs.insert(card.id, at: currentIndex + 1)
        } else {
            sessionTabs.append(card.id)
        }

        objectWillChange.send()
        // Don't save - transient cards are not persisted

        // Switch to the new terminal immediately
        selectedCard = card
    }

    /// Promote a transient card to a persistent board card
    private func promoteTransientCard(_ card: TerminalCard) {
        guard card.isTransient, transientCards[card.id] != nil else { return }

        // Remove from transient storage
        transientCards.removeValue(forKey: card.id)

        // Add to board
        card.isTransient = false
        board.cards.append(card)

        objectWillChange.send()
        save()
    }

    /// Switch to the next tab (cycles through)
    func nextTab() {
        let tabs = tabCards
        guard !tabs.isEmpty else { return }

        if let current = selectedCard,
            let currentIndex = tabs.firstIndex(where: { $0.id == current.id })
        {
            let nextIndex = (currentIndex + 1) % tabs.count
            selectedCard = tabs[nextIndex]
        } else if let first = tabs.first {
            selectCard(first)
        }
    }

    /// Switch to the previous tab (cycles through)
    func previousTab() {
        let tabs = tabCards
        guard !tabs.isEmpty else { return }

        if let current = selectedCard,
            let currentIndex = tabs.firstIndex(where: { $0.id == current.id })
        {
            let prevIndex = currentIndex == 0 ? tabs.count - 1 : currentIndex - 1
            selectedCard = tabs[prevIndex]
        } else if let last = tabs.last {
            selectCard(last)
        }
    }
}
