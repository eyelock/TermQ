import Combine
import Foundation
import SwiftUI
import TermQCore

// MARK: - Board View Model

@MainActor
class BoardViewModel: ObservableObject {
    /// Shared instance for app-wide access (e.g., from Settings window)
    static let shared = BoardViewModel()

    @Published var board: Board
    @Published var selectedCard: TerminalCard?
    @Published var isEditingCard: TerminalCard?
    @Published var isEditingNewCard: Bool = false
    @Published var isEditingColumn: Column?
    @Published var isEditingNewColumn: Bool = false
    @Published var draftColumn: Column?
    @Published var showDeleteConfirmation: Bool = false

    /// Terminals currently processing (have recent output activity)
    @Published private(set) var processingCards: Set<UUID> = []

    /// Terminals with active background sessions
    @Published private(set) var activeSessionCards: Set<UUID> = []

    /// Recovered tmux sessions that can be reattached
    @Published var recoverableSessions: [TmuxSessionInfo] = []

    /// Whether to show the session recovery sheet
    @Published var showSessionRecovery: Bool = false

    /// Timer for updating processing status
    private var processingTimer: Timer?

    // MARK: - Extracted Managers

    private let persistence: BoardPersistence
    let tabManager: TabManager

    // MARK: - Published Proxies (for backwards compatibility)

    /// Session tabs - proxied from TabManager
    var sessionTabs: [UUID] { tabManager.sessionTabs }

    /// Tabs that need attention - proxied from TabManager
    var needsAttention: Set<UUID> { tabManager.needsAttention }

    init() {
        self.persistence = BoardPersistence()
        self.tabManager = TabManager()
        self.board = persistence.loadBoard()

        // Configure TabManager callbacks after all properties initialized
        tabManager.configure(
            board: { [weak self] in self?.board ?? Board() },
            onSave: { [weak self] in self?.save() }
        )

        // Initialize tabs from favourites
        tabManager.initializeFromFavourites()

        // Purge expired cards from bin on startup
        purgeExpiredCards()

        // Start timer to periodically update processing status
        startProcessingTimer()

        // Set up centralized bell handler for reliable notification across all sessions
        TerminalSessionManager.shared.onBellForCard = { [weak self] cardId in
            self?.markNeedsAttention(cardId)
        }

        // Start monitoring file for external changes
        persistence.startFileMonitoring { [weak self] in
            self?.handleFileChange()
        }

        // Check for recoverable tmux sessions (async)
        Task {
            await checkForRecoverableSessions()
        }
    }

    // MARK: - Private Helpers

    private func startProcessingTimer() {
        processingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProcessingStatus()
            }
        }
    }

    private func refreshProcessingStatus() {
        let newProcessing = TerminalSessionManager.shared.processingCardIds()
        if newProcessing != processingCards {
            processingCards = newProcessing
        }

        let newActiveSessions = TerminalSessionManager.shared.activeSessionCardIds()
        if newActiveSessions != activeSessionCards {
            activeSessionCards = newActiveSessions
        }
    }

    private func handleFileChange() {
        guard let loaded = persistence.reloadForExternalChanges() else { return }
        BoardPersistence.mergeExternalChanges(from: loaded, into: board)
        objectWillChange.send()
    }

    func save() {
        persistence.save(board)

        // Trigger automatic backup if configured
        BackupManager.backupIfNeeded()
    }

    /// Reload board from disk (used after restore)
    func reloadFromDisk() {
        guard let loaded = persistence.reloadForExternalChanges() else {
            #if DEBUG
                print("[BoardViewModel] Failed to reload board from disk")
            #endif
            return
        }

        self.board = loaded

        // Re-initialize tabs from restored favourites
        tabManager.reinitializeFromBoard(board)

        objectWillChange.send()

        #if DEBUG
            print("[BoardViewModel] Reloaded board from disk with \(board.cards.count) cards")
        #endif
    }

    // MARK: - Card Operations

    func addTerminal(to column: Column) {
        let card = board.addCard(to: column)
        objectWillChange.send()
        save()

        isEditingNewCard = true
        isEditingCard = card
    }

    func duplicateTerminal(_ source: TerminalCard) {
        // Find the target column
        guard let column = board.columns.first(where: { $0.id == source.columnId }) else {
            return
        }

        // Create a new card with copied properties
        let maxIndex = board.cards(for: column).map(\.orderIndex).max() ?? -1
        let newCard = TerminalCard(
            title: "",  // Will be set by user in editor
            description: source.description,
            tags: source.tags,
            columnId: source.columnId,
            orderIndex: maxIndex + 1,
            shellPath: source.shellPath,
            workingDirectory: source.workingDirectory,
            isFavourite: false,  // Start unfavourited
            initCommand: source.initCommand,
            llmPrompt: source.llmPrompt,
            llmNextAction: "",  // Don't copy one-time action
            badge: source.badge,
            fontName: source.fontName,
            fontSize: source.fontSize,
            safePasteEnabled: source.safePasteEnabled,
            themeId: source.themeId,
            allowAutorun: source.allowAutorun,
            allowOscClipboard: source.allowOscClipboard,
            confirmExternalModifications: source.confirmExternalModifications,
            backend: source.backend,
            environmentVariables: source.environmentVariables
        )

        board.cards.append(newCard)
        objectWillChange.send()
        save()

        // Open the editor for the new card
        isEditingNewCard = true
        isEditingCard = newCard
    }

    func deleteCard(_ card: TerminalCard) {
        tabManager.removeTab(card.id)

        if selectedCard?.id == card.id {
            selectedCard = nil
        }
        // Kill tmux sessions when deleting - user is getting rid of the card
        TerminalSessionManager.shared.removeSession(for: card.id, killTmuxSession: true)

        card.deletedAt = Date()

        objectWillChange.send()
        save()
    }

    func deleteTabCard(_ card: TerminalCard) {
        let nextCardId = tabManager.adjacentTabId(to: card.id)

        tabManager.removeTab(card.id)
        // Kill tmux sessions when deleting - user is getting rid of the card
        TerminalSessionManager.shared.removeSession(for: card.id, killTmuxSession: true)

        if card.isTransient {
            tabManager.removeTransientCard(card.id)
        } else {
            card.deletedAt = Date()
            save()
        }

        objectWillChange.send()

        if let nextId = nextCardId, let next = tabManager.card(for: nextId) {
            selectedCard = next
        } else if let first = tabManager.tabCards.first {
            selectedCard = first
        } else {
            selectedCard = nil
        }
    }

    func closeTab(_ card: TerminalCard) {
        let nextCardId = tabManager.adjacentTabId(to: card.id)

        tabManager.removeTab(card.id)

        if card.isTransient {
            tabManager.removeTransientCard(card.id)
            TerminalSessionManager.shared.removeSession(for: card.id)
        }

        objectWillChange.send()

        if let nextId = nextCardId, let next = tabManager.card(for: nextId) {
            selectedCard = next
        } else if let first = tabManager.tabCards.first {
            selectedCard = first
        } else {
            selectedCard = nil
        }
    }

    func closeUnfavouritedTabs() {
        let removedIds = tabManager.closeUnfavouritedTabs()
        for id in removedIds {
            TerminalSessionManager.shared.removeSession(for: id)
        }

        if let current = selectedCard, !tabManager.hasTab(current.id) {
            if let first = tabManager.tabCards.first {
                selectedCard = first
            } else {
                selectedCard = nil
            }
        }
        objectWillChange.send()
    }

    /// Forcefully kill a terminal session (for stuck/unresponsive terminals)
    /// After killing, the terminal can be re-opened fresh
    func killTerminal(for card: TerminalCard) {
        TerminalSessionManager.shared.killSession(for: card.id)
        objectWillChange.send()
    }

    func moveCard(_ card: TerminalCard, to column: Column) {
        let targetCards = board.cards(for: column)
        board.moveCard(card, to: column, at: targetCards.count)
        objectWillChange.send()
        save()
    }

    func moveCard(_ card: TerminalCard, to column: Column, at index: Int) {
        board.moveCard(card, to: column, at: index)
        objectWillChange.send()
        save()
    }

    func selectCard(_ card: TerminalCard) {
        selectedCard = card
        tabManager.addTab(card.id)
        tabManager.clearAttention(card.id)
    }

    func markNeedsAttention(_ cardId: UUID) {
        tabManager.markNeedsAttention(cardId, currentSelection: selectedCard?.id)
    }

    func deselectCard() {
        selectedCard = nil
    }

    func updateCard(_ card: TerminalCard) {
        if card.isTransient {
            promoteTransientCard(card)
        }

        // Sync metadata to tmux session if using tmux backend
        TerminalSessionManager.shared.syncMetadataToTmuxSession(card: card)

        objectWillChange.send()
        save()
    }

    // MARK: - Column Operations

    func addColumn() {
        let maxIndex = board.columns.map(\.orderIndex).max() ?? -1
        let column = Column(name: "New Column", orderIndex: maxIndex + 1)
        draftColumn = column
        isEditingNewColumn = true
        isEditingColumn = column
    }

    func commitDraftColumn() {
        guard let column = draftColumn else { return }
        board.columns.append(column)
        draftColumn = nil
        objectWillChange.send()
        save()
    }

    func discardDraftColumn() {
        draftColumn = nil
    }

    func canDeleteColumn(_ column: Column) -> Bool {
        return board.cards(for: column).isEmpty
    }

    func deleteColumn(_ column: Column) {
        guard canDeleteColumn(column) else { return }
        board.removeColumn(column)
        objectWillChange.send()
        save()
    }

    func updateColumn(_ column: Column) {
        objectWillChange.send()
        save()
    }

    func moveColumn(_ column: Column, toIndex: Int) {
        board.moveColumn(column, to: toIndex)
        objectWillChange.send()
        save()
    }

    // MARK: - Favourites

    var favouriteCards: [TerminalCard] {
        board.activeCards.filter { $0.isFavourite }
    }

    func toggleFavourite(_ card: TerminalCard) {
        card.isFavourite.toggle()

        if card.isFavourite && card.isTransient {
            promoteTransientCard(card)
        }

        if card.isFavourite {
            tabManager.addTab(card.id)
        }

        tabManager.updateFavouriteOrder()
        objectWillChange.send()
        save()
    }

    // MARK: - Tab Proxies (for backwards compatibility)

    var tabCards: [TerminalCard] {
        tabManager.tabCards
    }

    var allTerminals: [TerminalCard] {
        var terminals = board.activeCards
        for (_, card) in tabManager.transientCards {
            if !terminals.contains(where: { $0.id == card.id }) {
                terminals.append(card)
            }
        }
        return terminals.sorted { lhs, rhs in
            if lhs.isFavourite != rhs.isFavourite {
                return lhs.isFavourite
            }
            return lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
    }

    func card(for id: UUID) -> TerminalCard? {
        tabManager.card(for: id)
    }

    func moveTab(fromIndex: Int, toIndex: Int) {
        tabManager.moveTab(fromIndex: fromIndex, toIndex: toIndex)
        objectWillChange.send()
    }

    func moveTab(_ cardId: UUID, toIndex: Int) {
        tabManager.moveTab(cardId, toIndex: toIndex)
        objectWillChange.send()
    }

    // MARK: - Quick Actions

    func quickNewTerminal() {
        let column: Column
        let workingDirectory: String

        if let current = selectedCard,
            let currentColumn = board.columns.first(where: { $0.id == current.columnId })
        {
            column = currentColumn
            workingDirectory =
                TerminalSessionManager.shared.getCurrentDirectory(for: current.id)
                ?? current.workingDirectory
        } else if let firstColumn = board.columns.first {
            column = firstColumn
            workingDirectory = NSHomeDirectory()
        } else {
            return
        }

        let existingTitles = Set(board.cards.map { $0.title } + tabManager.transientCards.values.map { $0.title })
        var counter = 1
        var title = "Terminal \(counter)"
        while existingTitles.contains(title) {
            counter += 1
            title = "Terminal \(counter)"
        }

        // Determine backend for transient card - use tmux if available and enabled
        let tmuxEnabled = UserDefaults.standard.object(forKey: "tmuxEnabled") as? Bool ?? true
        let tmuxManager = TmuxManager.shared
        let defaultBackend: TerminalBackend = (tmuxManager.isAvailable && tmuxEnabled) ? .tmux : .direct

        let card = TerminalCard(
            title: title,
            columnId: column.id,
            workingDirectory: workingDirectory,
            backend: defaultBackend
        )
        card.isTransient = true
        tabManager.addTransientCard(card)

        if let current = selectedCard {
            tabManager.insertTab(card.id, after: current.id)
        } else {
            tabManager.addTab(card.id)
        }

        objectWillChange.send()
        selectedCard = card
    }

    private func promoteTransientCard(_ card: TerminalCard) {
        guard card.isTransient else { return }
        if let promoted = tabManager.promoteTransientCard(card.id) {
            board.cards.append(promoted)
            objectWillChange.send()
            save()
        }
    }

    func nextTab() {
        if let nextId = tabManager.nextTabId(from: selectedCard?.id),
            let next = tabManager.card(for: nextId)
        {
            selectedCard = next
        }
    }

    func previousTab() {
        if let prevId = tabManager.previousTabId(from: selectedCard?.id),
            let prev = tabManager.card(for: prevId)
        {
            selectedCard = prev
        }
    }

    // MARK: - Session Management

    /// Close an active terminal session (detaches tmux sessions)
    func closeSession(for card: TerminalCard) {
        TerminalSessionManager.shared.closeSession(for: card.id)
        objectWillChange.send()
    }

    /// Kill a terminal session (fully terminates tmux sessions)
    func killSession(for card: TerminalCard) {
        TerminalSessionManager.shared.killSession(for: card.id)
        objectWillChange.send()
    }

    /// Restart a terminal session (close and reopen)
    func restartSession(for card: TerminalCard) {
        TerminalSessionManager.shared.restartSession(for: card.id)
        objectWillChange.send()
    }

    // MARK: - Bin (Soft Delete)

    var binCards: [TerminalCard] {
        board.deletedCards
    }

    func permanentlyDeleteCard(_ card: TerminalCard) {
        board.removeCard(card)
        objectWillChange.send()
        save()
    }

    func restoreCard(_ card: TerminalCard) {
        card.deletedAt = nil

        if !board.columns.contains(where: { $0.id == card.columnId }) {
            if let firstColumn = board.columns.first {
                card.columnId = firstColumn.id
            }
        }

        objectWillChange.send()
        save()
    }

    func emptyBin() {
        let deletedCards = board.deletedCards
        for card in deletedCards {
            board.removeCard(card)
        }
        objectWillChange.send()
        save()
    }

    private func purgeExpiredCards() {
        let retentionDays = UserDefaults.standard.integer(forKey: "binRetentionDays")
        let effectiveRetentionDays = retentionDays > 0 ? retentionDays : 14

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -effectiveRetentionDays, to: Date()) ?? Date()

        var purged = false
        for card in board.deletedCards {
            if let deletedAt = card.deletedAt, deletedAt < cutoffDate {
                board.removeCard(card)
                purged = true
            }
        }

        if purged {
            save()
        }
    }
}
