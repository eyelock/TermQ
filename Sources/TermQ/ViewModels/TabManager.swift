import Foundation
import TermQCore

/// Manages terminal tab state and navigation
/// Extracted from BoardViewModel for single responsibility
@MainActor
public final class TabManager: ObservableObject {
    /// Session tabs - ordered list of card IDs currently open as tabs (not persisted)
    @Published private(set) var sessionTabs: [UUID] = []

    /// Tabs that need attention (received a bell) - cleared when selected
    @Published private(set) var needsAttention: Set<UUID> = []

    /// Transient terminals - not persisted, exist only as tabs until promoted
    private(set) var transientCards: [UUID: TerminalCard] = [:]

    /// Callback to get board reference (avoids circular dependency)
    private var getBoard: (() -> Board)?
    private var onSave: (() -> Void)?

    init() {}

    /// Configure callbacks after init (to avoid Swift init order issues)
    func configure(board: @escaping () -> Board, onSave: @escaping () -> Void) {
        self.getBoard = board
        self.onSave = onSave
    }

    private var board: Board {
        getBoard?() ?? Board()
    }

    // MARK: - Initialization

    /// Initialize session tabs from persisted favourite order
    func initializeFromFavourites() {
        let board = board
        let favouriteIds = Set(board.activeCards.filter { $0.isFavourite }.map { $0.id })
        sessionTabs = board.favouriteOrder.filter { favouriteIds.contains($0) }

        // Add any favourites not in the order
        for card in board.activeCards where card.isFavourite && !sessionTabs.contains(card.id) {
            sessionTabs.append(card.id)
        }
    }

    // MARK: - Tab State

    /// Cards to show as tabs - based on sessionTabs order
    var tabCards: [TerminalCard] {
        let board = board
        return sessionTabs.compactMap { id in
            transientCards[id] ?? board.cards.first { $0.id == id }
        }
    }

    /// Look up a card by ID (from board or transient)
    func card(for id: UUID) -> TerminalCard? {
        let board = board
        return transientCards[id] ?? board.cards.first { $0.id == id }
    }

    /// Check if a card ID is in session tabs
    func hasTab(_ cardId: UUID) -> Bool {
        sessionTabs.contains(cardId)
    }

    // MARK: - Tab Operations

    /// Add a card ID to session tabs if not already present
    func addTab(_ cardId: UUID) {
        if !sessionTabs.contains(cardId) {
            sessionTabs.append(cardId)
        }
    }

    /// Insert a tab after a specific card ID
    func insertTab(_ cardId: UUID, after existingId: UUID) {
        if let index = sessionTabs.firstIndex(of: existingId) {
            sessionTabs.insert(cardId, at: index + 1)
        } else {
            sessionTabs.append(cardId)
        }
    }

    /// Remove a card ID from session tabs
    func removeTab(_ cardId: UUID) {
        sessionTabs.removeAll { $0 == cardId }
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
        onSave?()
    }

    /// Move a tab by card ID to a new index
    func moveTab(_ cardId: UUID, toIndex: Int) {
        guard let fromIndex = sessionTabs.firstIndex(of: cardId) else { return }
        moveTab(fromIndex: fromIndex, toIndex: toIndex)
    }

    // MARK: - Tab Navigation

    /// Get the next tab index (cycles through)
    func nextTabId(from currentId: UUID?) -> UUID? {
        let tabs = tabCards
        guard !tabs.isEmpty else { return nil }

        if let current = currentId,
            let currentIndex = tabs.firstIndex(where: { $0.id == current })
        {
            let nextIndex = (currentIndex + 1) % tabs.count
            return tabs[nextIndex].id
        }
        return tabs.first?.id
    }

    /// Get the previous tab index (cycles through)
    func previousTabId(from currentId: UUID?) -> UUID? {
        let tabs = tabCards
        guard !tabs.isEmpty else { return nil }

        if let current = currentId,
            let currentIndex = tabs.firstIndex(where: { $0.id == current })
        {
            let prevIndex = currentIndex == 0 ? tabs.count - 1 : currentIndex - 1
            return tabs[prevIndex].id
        }
        return tabs.last?.id
    }

    /// Get adjacent tab (for deletion scenarios)
    /// Returns left neighbor, or right if none, or nil if empty
    func adjacentTabId(to cardId: UUID) -> UUID? {
        let tabs = tabCards
        guard let index = tabs.firstIndex(where: { $0.id == cardId }) else { return nil }

        if index > 0 {
            return tabs[index - 1].id
        } else if tabs.count > 1 {
            return tabs[1].id
        }
        return nil
    }

    // MARK: - Attention State

    /// Mark a tab as needing attention (e.g., from terminal bell)
    func markNeedsAttention(_ cardId: UUID, currentSelection: UUID?) {
        #if DEBUG
            print(
                "[TabManager] markNeedsAttention called for: \(cardId), selected: \(currentSelection?.uuidString ?? "nil")"
            )
        #endif
        if currentSelection != cardId {
            needsAttention.insert(cardId)
        }
    }

    /// Clear attention indicator for a card
    func clearAttention(_ cardId: UUID) {
        needsAttention.remove(cardId)
    }

    // MARK: - Transient Cards

    /// Add a transient card
    func addTransientCard(_ card: TerminalCard) {
        transientCards[card.id] = card
    }

    /// Remove a transient card
    func removeTransientCard(_ cardId: UUID) {
        transientCards.removeValue(forKey: cardId)
    }

    /// Promote a transient card to board (returns the card if found)
    func promoteTransientCard(_ cardId: UUID) -> TerminalCard? {
        guard let card = transientCards[cardId] else { return nil }
        transientCards.removeValue(forKey: cardId)
        card.isTransient = false
        return card
    }

    // MARK: - Favourite Order

    /// Update the persisted favourite order from current session tabs
    func updateFavouriteOrder() {
        let board = board
        let favouriteIds = Set(board.activeCards.filter { $0.isFavourite }.map { $0.id })
        board.favouriteOrder = sessionTabs.filter { favouriteIds.contains($0) }
    }

    /// Close all tabs that are not favourites
    /// Returns IDs of transient cards that were removed
    func closeUnfavouritedTabs() -> [UUID] {
        let board = board
        let favouriteIds = Set(board.cards.filter { $0.isFavourite }.map { $0.id })

        // Find transient cards to remove
        let transientToRemove = sessionTabs.filter { transientCards[$0] != nil }
        for id in transientToRemove {
            transientCards.removeValue(forKey: id)
        }

        sessionTabs = sessionTabs.filter { favouriteIds.contains($0) }

        return transientToRemove
    }
}
