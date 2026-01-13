import Foundation
import MCP

// MARK: - Resource Handler Implementations

extension TermQMCPServer {
    /// Handle resource read requests
    func dispatchResourceRead(_ params: ReadResource.Parameters) async throws -> ReadResource.Result {
        let uri = params.uri

        switch uri {
        case "termq://terminals":
            return try await handleTerminalsResource(uri: uri)

        case "termq://columns":
            return try await handleColumnsResource(uri: uri)

        case "termq://pending":
            return try await handlePendingResource(uri: uri)

        case "termq://context":
            return ReadResource.Result(contents: [.text(Self.contextDocumentation, uri: uri)])

        default:
            throw MCPError.invalidRequest("Unknown resource: \(uri)")
        }
    }

    // MARK: - Resource Implementations

    private func handleTerminalsResource(uri: String) async throws -> ReadResource.Result {
        do {
            let board = try loadBoard()
            let output = board.activeCards.map {
                TerminalOutput(from: $0, columnName: board.columnName(for: $0.columnId))
            }
            let json = try JSONHelper.encode(output)
            return ReadResource.Result(contents: [.text(json, uri: uri)])
        } catch {
            return ReadResource.Result(contents: [.text("[]", uri: uri)])
        }
    }

    private func handleColumnsResource(uri: String) async throws -> ReadResource.Result {
        do {
            let board = try loadBoard()
            let columns = board.sortedColumns().map { column in
                ColumnOutput(
                    from: column,
                    terminalCount: board.activeCards.filter { $0.columnId == column.id }.count
                )
            }
            let json = try JSONHelper.encode(columns)
            return ReadResource.Result(contents: [.text(json, uri: uri)])
        } catch {
            return ReadResource.Result(contents: [.text("[]", uri: uri)])
        }
    }

    private func handlePendingResource(uri: String) async throws -> ReadResource.Result {
        do {
            let board = try loadBoard()
            var cards = board.activeCards

            // Sort: pending actions first, then by staleness
            cards.sort { card1, card2 in
                let has1 = !card1.llmNextAction.isEmpty
                let has2 = !card2.llmNextAction.isEmpty
                if has1 != has2 { return has1 }
                return card1.stalenessRank > card2.stalenessRank
            }

            var terminals: [PendingTerminalOutput] = []
            var withNextAction = 0
            var staleCount = 0
            var freshCount = 0

            for card in cards {
                let staleness = card.staleness
                if !card.llmNextAction.isEmpty { withNextAction += 1 }
                switch staleness {
                case "stale", "old": staleCount += 1
                case "fresh": freshCount += 1
                default: break
                }
                terminals.append(
                    PendingTerminalOutput(
                        from: card,
                        columnName: board.columnName(for: card.columnId),
                        staleness: staleness
                    ))
            }

            let output = PendingOutput(
                terminals: terminals,
                summary: PendingSummary(
                    total: terminals.count,
                    withNextAction: withNextAction,
                    stale: staleCount,
                    fresh: freshCount
                )
            )
            let json = try JSONHelper.encode(output)
            return ReadResource.Result(contents: [.text(json, uri: uri)])
        } catch {
            return ReadResource.Result(contents: [.text("{}", uri: uri)])
        }
    }
}
