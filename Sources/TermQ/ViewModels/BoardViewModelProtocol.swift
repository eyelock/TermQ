import Foundation
import TermQCore

// MARK: - BoardViewModelProtocol

/// Defines the subset of BoardViewModel surface that URLHandler requires.
/// Introducing this protocol allows URLHandler to be tested with a lightweight mock
/// rather than a fully-initialised BoardViewModel.
@MainActor
protocol BoardViewModelProtocol: AnyObject {
    /// The board model — used to look up columns by name.
    var board: Board { get }

    /// Looks up a card by its UUID (searches active cards and open tabs).
    func card(for id: UUID) -> TerminalCard?

    /// Moves a card into the given column (appends to end).
    func moveCard(_ card: TerminalCard, to column: Column)

    /// Persists any in-place mutations made to a card.
    func updateCard(_ card: TerminalCard)

    /// Selects a card, adding it to the tab bar if necessary.
    func selectCard(_ card: TerminalCard)

    /// Soft-deletes a card (moves it to the bin).
    func deleteCard(_ card: TerminalCard)

    /// Permanently removes a card from the board.
    func permanentlyDeleteCard(_ card: TerminalCard)

    /// Toggles the favourite flag on a card.
    func toggleFavourite(_ card: TerminalCard)
}
