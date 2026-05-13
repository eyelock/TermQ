import Foundation
import MCP
import TermQShared

// MARK: - Completion Handler
//
// Implements `completion/complete` per the MCP spec. The TermQ server provides
// completion values for the `terminal` argument of the `terminal_summary` prompt:
// matching terminal names from the live board.

extension TermQMCPServer {
    /// Maximum number of completion suggestions returned per the spec (clients display these).
    private static let maxCompletionValues = 100

    /// Handle `completion/complete` requests.
    func dispatchCompletion(_ params: Complete.Parameters) async throws -> Complete.Result {
        switch params.ref {
        case .prompt(let promptRef):
            return try completePromptArgument(promptName: promptRef.name, argument: params.argument)
        case .resource:
            // Tier 1b will add resource template completions (e.g. for `termq://terminal/{id}`).
            // For now, return an empty completion rather than erroring — the spec allows this.
            return Complete.Result(completion: .init(values: [], total: 0, hasMore: false))
        }
    }

    private func completePromptArgument(
        promptName: String,
        argument: Complete.Parameters.Argument
    ) throws -> Complete.Result {
        switch (promptName, argument.name) {
        case ("terminal_summary", "terminal"):
            return try completeTerminalIdentifier(prefix: argument.value)
        default:
            // Unknown (prompt, argument) pair — return empty completion. Clients show
            // nothing rather than an error; the user just gets no suggestions.
            return Complete.Result(completion: .init(values: [], total: 0, hasMore: false))
        }
    }

    /// Suggest terminal names matching the user's partial input.
    ///
    /// Matches by case-insensitive substring on the title. If the user types nothing,
    /// returns the first `maxCompletionValues` active terminals so they can pick from a
    /// browsable list.
    private func completeTerminalIdentifier(prefix: String) throws -> Complete.Result {
        let board: Board
        do {
            board = try loadBoard()
        } catch {
            // No board / load failure — return empty completion. Surfacing an error here
            // would prevent autocomplete from working at all in a degraded environment.
            return Complete.Result(completion: .init(values: [], total: 0, hasMore: false))
        }

        let prefixLower = prefix.lowercased()
        let matching = board.activeCards.filter { card in
            prefixLower.isEmpty || card.title.lowercased().contains(prefixLower)
        }
        let values = matching.prefix(Self.maxCompletionValues).map { $0.title }
        return Complete.Result(
            completion: .init(
                values: Array(values),
                total: matching.count,
                hasMore: matching.count > Self.maxCompletionValues
            )
        )
    }
}
