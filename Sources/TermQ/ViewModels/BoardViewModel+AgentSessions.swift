import Foundation
import TermQCore

// MARK: - Agent Session Cards

extension BoardViewModel {
    /// Create a new card configured as an agent session against the given
    /// harness identifier.
    ///
    /// `harnessId` is the qualified harness name (e.g. `"eyelock/x/coding-agent"`)
    /// stored in `agentConfig.harness`. `title` becomes the card title.
    /// The card is created in the currently-selected card's column (or the
    /// first column if none selected). Returns `nil` if the board has no
    /// columns.
    @discardableResult
    func createAgentCard(harnessId: String, title: String, description: String = "") -> TerminalCard? {
        let column: Column
        if let current = selectedCard,
            let currentColumn = board.columns.first(where: { $0.id == current.columnId })
        {
            column = currentColumn
        } else if let firstColumn = board.columns.first {
            column = firstColumn
        } else {
            return nil
        }

        let maxIndex = board.cards(for: column).map(\.orderIndex).max() ?? -1
        let defaults = newTerminalDefaults()

        let card = TerminalCard(
            title: title,
            description: description,
            columnId: column.id,
            orderIndex: maxIndex + 1,
            workingDirectory: defaults.workingDirectory,
            safePasteEnabled: nil,
            allowAutorun: defaults.allowAutorun,
            allowOscClipboard: defaults.allowOscClipboard,
            confirmExternalModifications: defaults.confirmExternalModifications,
            backend: nil,
            agentConfig: AgentConfig(harness: harnessId)
        )

        board.cards.append(card)
        objectWillChange.send()
        save()

        return card
    }

    /// Create a fleet of `count` agent session cards that all share a
    /// `fleetId`, placed in the same column as the currently-selected card
    /// (or the first column). Each card's `loopDriverCommand` is set to a
    /// complete `ynh agent run` invocation with the given harness, task
    /// (written inline with shell quoting), and a distinct worktree path
    /// under `baseWorktreeDir`.
    ///
    /// Returns the created cards, or an empty array if the board has no
    /// columns or `count < 2`.
    @discardableResult
    func createFleet(
        harnessId: String,
        task: String,
        count: Int,
        baseWorktreeDir: String,
        driverBase: String
    ) -> [TerminalCard] {
        guard count >= 2 else { return [] }

        let column: Column
        if let current = selectedCard,
            let currentColumn = board.columns.first(where: { $0.id == current.columnId })
        {
            column = currentColumn
        } else if let firstColumn = board.columns.first {
            column = firstColumn
        } else {
            return []
        }

        let fleetId = UUID()
        let defaults = newTerminalDefaults()
        var created: [TerminalCard] = []
        let maxIndex = board.cards(for: column).map(\.orderIndex).max() ?? -1

        for i in 1...count {
            let worktreePath = "\(baseWorktreeDir)/session-\(i)"
            let escapedTask = task.replacingOccurrences(of: "'", with: "'\\''")
            let command = "\(driverBase) --harness '\(harnessId)' --task '\(escapedTask)' --worktree '\(worktreePath)'"

            var config = AgentConfig(harness: harnessId, fleetId: fleetId)
            config.loopDriverCommand = command

            let card = TerminalCard(
                title: "\(harnessId.components(separatedBy: "/").last ?? harnessId) (\(i)/\(count))",
                columnId: column.id,
                orderIndex: maxIndex + i,
                workingDirectory: defaults.workingDirectory,
                safePasteEnabled: nil,
                allowAutorun: defaults.allowAutorun,
                allowOscClipboard: defaults.allowOscClipboard,
                confirmExternalModifications: defaults.confirmExternalModifications,
                backend: nil,
                agentConfig: config
            )
            board.cards.append(card)
            created.append(card)
        }

        objectWillChange.send()
        save()
        return created
    }

    /// Flip persisted agent statuses that can't be substantiated post-restart
    /// back to `.idle`:
    ///
    /// - `running`, `planning`, `awaitingPlanApproval`, `awaitingTurnApproval`
    ///   were claiming an active loop driver that no longer exists.
    /// - `errored` was attached to a `lastError` payload we never persisted,
    ///   so showing the red pill with no banner is worse than silent — there's
    ///   nothing the user can do with it.
    /// - `converged` and `stuck` are kept: they're terminal outcomes the user
    ///   may want to revisit. `paused` is kept (user intentionally stopped).
    func resetStaleAgentStatuses() {
        var changed = false
        for card in board.cards {
            guard var config = card.agentConfig else { continue }
            switch config.status {
            case .running, .planning, .awaitingPlanApproval, .awaitingTurnApproval, .errored:
                config.status = .idle
                card.agentConfig = config
                changed = true
            default:
                break
            }
        }
        if changed { save() }
    }
}
