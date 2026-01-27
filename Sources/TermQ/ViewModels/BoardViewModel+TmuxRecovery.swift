import Foundation
import TermQCore

// MARK: - TMUX Session Recovery

extension BoardViewModel {
    /// Check for tmux sessions that can be recovered
    /// If auto-reattach is enabled, silently reattach sessions that have matching cards
    func checkForRecoverableSessions() async {
        let tmuxManager = TmuxManager.shared

        // Ensure tmux detection has completed
        await tmuxManager.detectTmux()

        guard tmuxManager.isAvailable else {
            recoverableSessions = []
            return
        }

        // Check if tmux is enabled globally (default true to match @AppStorage)
        let tmuxEnabled = UserDefaults.standard.object(forKey: "tmuxEnabled") as? Bool ?? true
        guard tmuxEnabled else {
            recoverableSessions = []
            return
        }

        // Get list of detached TermQ sessions
        let sessions = await tmuxManager.listSessions()
        let detached = sessions.filter { !$0.isAttached }

        // Filter out sessions that match existing cards already open as tabs
        let openCardIds = Set(
            sessionTabs.compactMap { id -> String? in
                guard let card = card(for: id) else { return nil }
                return card.tmuxSessionName
            })

        let candidates = detached.filter { !openCardIds.contains($0.name) }

        // Check auto-reattach setting
        let autoReattach = UserDefaults.standard.object(forKey: "tmuxAutoReattach") as? Bool ?? true

        if autoReattach {
            // Silently reattach sessions that have matching cards
            var orphanSessions: [TmuxSessionInfo] = []

            for session in candidates {
                let prefix = session.cardIdPrefix.lowercased()
                // Only match active (non-deleted) cards
                if let matchingCard = board.cards.first(where: {
                    !$0.isDeleted
                        && ($0.tmuxSessionName == session.name
                            || $0.id.uuidString.prefix(8).lowercased() == prefix)
                }) {
                    // Auto-reattach: add to tabs silently
                    tabManager.addTab(matchingCard.id)
                    tmuxManager.markSessionRecovered(name: session.name)
                } else {
                    // No matching card - this is an orphan session
                    orphanSessions.append(session)
                }
            }

            recoverableSessions = orphanSessions
        } else {
            // Auto-reattach disabled - show all recoverable sessions
            recoverableSessions = candidates
        }

        // Show recovery sheet only if there are orphan sessions (or all if auto-reattach disabled)
        if !recoverableSessions.isEmpty {
            showSessionRecovery = true
        }
    }

    /// Recover a tmux session by finding or creating a card for it
    /// Priority order: 1) Restore deleted card, 2) Use active card, 3) Create new card
    func recoverSession(_ session: TmuxSessionInfo) {
        let prefix = session.cardIdPrefix.lowercased()

        // First, check if there's a deleted card that matches - restore it
        if let deletedCard = board.cards.first(where: {
            $0.isDeleted
                && ($0.tmuxSessionName == session.name
                    || $0.id.uuidString.prefix(8).lowercased() == prefix)
        }) {
            // Restore the deleted card to the board without opening it
            deletedCard.deletedAt = nil
            objectWillChange.send()
            save()
        }
        // Second, check if there's an active card that matches
        else if board.cards.contains(where: {
            !$0.isDeleted
                && ($0.tmuxSessionName == session.name
                    || $0.id.uuidString.prefix(8).lowercased() == prefix)
        }) {
            // Card already active - nothing to do
            // Session is already linked to the card
        }
        // Finally, create a new card if no match found
        else {
            // No matching card - create a placeholder card
            // First, try to recover metadata from the tmux session
            Task {
                await recoverSessionWithMetadata(session)
            }
            return  // The async task will handle the rest
        }

        // Remove from recoverable list
        recoverableSessions.removeAll { $0.name == session.name }
        TmuxManager.shared.markSessionRecovered(name: session.name)
    }

    /// Recover session with metadata restoration from tmux environment
    func recoverSessionWithMetadata(_ session: TmuxSessionInfo) async {
        let tmuxManager = TmuxManager.shared

        // Try to recover metadata from tmux session
        let metadata = await tmuxManager.getMetadataFromSession(sessionName: session.name)

        // Get a default column (or use recovered one if valid)
        var column = board.columns.first ?? createDefaultColumn()
        if let recoveredColumnId = metadata?.columnId,
            let matchedColumn = board.columns.first(where: { $0.id == recoveredColumnId }) {
            column = matchedColumn
        }

        // Determine card details from metadata or fallback
        let title: String
        let description: String
        let tags: [Tag]
        let llmPrompt: String
        let llmNextAction: String
        let badge: String
        let isFavourite: Bool
        let workingDir: String

        if let meta = metadata {
            title = meta.title
            description = meta.description
            tags = meta.tags
            llmPrompt = meta.llmPrompt
            llmNextAction = meta.llmNextAction
            badge = meta.badge
            isFavourite = meta.isFavourite
            workingDir = session.currentPath ?? NSHomeDirectory()
        } else {
            // No metadata - use basic recovery
            title = session.name.replacingOccurrences(of: TmuxManager.sessionPrefix, with: "Recovered: ")
            description = ""
            tags = []
            llmPrompt = ""
            llmNextAction = ""
            badge = ""
            isFavourite = false
            workingDir = session.currentPath ?? NSHomeDirectory()
        }

        let card = TerminalCard(
            title: title,
            description: description,
            tags: tags,
            columnId: column.id,
            workingDirectory: workingDir,
            isFavourite: isFavourite,
            llmPrompt: llmPrompt,
            llmNextAction: llmNextAction,
            badge: badge,
            backend: .tmux
        )

        // Add to board without opening it
        board.cards.append(card)

        // If marked as favourite, add to favourite order
        if isFavourite {
            board.favouriteOrder.append(card.id)
        }

        save()
        objectWillChange.send()

        // Remove from recoverable list
        recoverableSessions.removeAll { $0.name == session.name }
        tmuxManager.markSessionRecovered(name: session.name)
    }

    /// Dismiss a recoverable session (don't recover, but also don't kill)
    func dismissRecoverableSession(_ session: TmuxSessionInfo) {
        recoverableSessions.removeAll { $0.name == session.name }
        TmuxManager.shared.markSessionRecovered(name: session.name)
    }

    /// Kill a recoverable tmux session (fully terminate)
    func killRecoverableSession(_ session: TmuxSessionInfo) {
        Task {
            try? await TmuxManager.shared.killSession(name: session.name)
            recoverableSessions.removeAll { $0.name == session.name }
        }
    }

    /// Create a default column if none exist
    func createDefaultColumn() -> Column {
        let column = Column(name: "Terminals", orderIndex: 0)
        board.columns.append(column)
        save()
        return column
    }
}
