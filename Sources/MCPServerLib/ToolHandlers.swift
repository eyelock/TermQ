import Foundation
import MCP

// MARK: - Tool Handler Implementations

extension TermQMCPServer {
    /// Dispatch tool calls to appropriate handlers
    func dispatchToolCall(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "termq_pending":
            return try await handlePending(params.arguments)
        case "termq_context":
            return try await handleContext()
        case "termq_list":
            return try await handleList(params.arguments)
        case "termq_find":
            return try await handleFind(params.arguments)
        case "termq_open":
            return try await handleOpen(params.arguments)
        case "termq_create":
            return try await handleCreate(params.arguments)
        case "termq_set":
            return try await handleSet(params.arguments)
        case "termq_move":
            return try await handleMove(params.arguments)
        default:
            throw MCPError.invalidRequest("Unknown tool: \(params.name)")
        }
    }

    // MARK: - Tool Implementations

    func handlePending(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let actionsOnly = arguments?["actionsOnly"]?.boolValue ?? false

        do {
            let board = try loadBoard()
            var cards = board.activeCards

            // Filter if actionsOnly
            if actionsOnly {
                cards = cards.filter { !$0.llmNextAction.isEmpty }
            }

            // Sort: pending actions first, then by staleness (stale → ageing → fresh)
            cards.sort { card1, card2 in
                let has1 = !card1.llmNextAction.isEmpty
                let has2 = !card2.llmNextAction.isEmpty
                if has1 != has2 { return has1 }

                let staleness1 = card1.stalenessRank
                let staleness2 = card2.stalenessRank
                if staleness1 != staleness2 { return staleness1 > staleness2 }

                return card1.title < card2.title
            }

            // Build output
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
            return CallTool.Result(content: [.text(json)])

        } catch {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    func handleContext() async throws -> CallTool.Result {
        let context = Self.contextDocumentation
        return CallTool.Result(content: [.text(context)])
    }

    func handleList(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let columnFilter = arguments?["column"]?.stringValue
        let columnsOnly = arguments?["columnsOnly"]?.boolValue ?? false

        do {
            let board = try loadBoard()

            // If columnsOnly, return just column info
            if columnsOnly {
                let columns = board.sortedColumns().map { column in
                    ColumnOutput(
                        from: column,
                        terminalCount: board.activeCards.filter { $0.columnId == column.id }.count
                    )
                }
                let json = try JSONHelper.encode(columns)
                return CallTool.Result(content: [.text(json)])
            }

            // Get cards, optionally filtered by column
            var cards = board.activeCards

            if let columnFilter = columnFilter {
                let filterLower = columnFilter.lowercased()
                let matchingColumnIds = board.columns
                    .filter { $0.name.lowercased().contains(filterLower) }
                    .map { $0.id }
                cards = cards.filter { matchingColumnIds.contains($0.columnId) }
            }

            // Sort by column order, then card order
            cards.sort { lhs, rhs in
                let lhsColOrder = board.columns.first { $0.id == lhs.columnId }?.orderIndex ?? 0
                let rhsColOrder = board.columns.first { $0.id == rhs.columnId }?.orderIndex ?? 0
                if lhsColOrder != rhsColOrder {
                    return lhsColOrder < rhsColOrder
                }
                return lhs.orderIndex < rhs.orderIndex
            }

            let output = cards.map { TerminalOutput(from: $0, columnName: board.columnName(for: $0.columnId)) }
            let json = try JSONHelper.encode(output)
            return CallTool.Result(content: [.text(json)])

        } catch {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    func handleFind(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let nameFilter = arguments?["name"]?.stringValue
        let columnFilter = arguments?["column"]?.stringValue
        let tagFilter = arguments?["tag"]?.stringValue
        let idFilter = arguments?["id"]?.stringValue
        let badgeFilter = arguments?["badge"]?.stringValue
        let favouritesOnly = arguments?["favourites"]?.boolValue ?? false

        do {
            let board = try loadBoard()
            var cards = board.activeCards

            // Filter by ID (exact match)
            if let idFilter = idFilter {
                if let uuid = UUID(uuidString: idFilter) {
                    cards = cards.filter { $0.id == uuid }
                } else {
                    // Invalid UUID format - return empty
                    let json = try JSONHelper.encode([TerminalOutput]())
                    return CallTool.Result(content: [.text(json)])
                }
            }

            // Filter by name (case-insensitive partial match)
            if let nameFilter = nameFilter {
                let filterLower = nameFilter.lowercased()
                cards = cards.filter { $0.title.lowercased().contains(filterLower) }
            }

            // Filter by column
            if let columnFilter = columnFilter {
                let filterLower = columnFilter.lowercased()
                let matchingColumnIds = board.columns
                    .filter { $0.name.lowercased().contains(filterLower) }
                    .map { $0.id }
                cards = cards.filter { matchingColumnIds.contains($0.columnId) }
            }

            // Filter by tag
            if let tagFilter = tagFilter {
                if tagFilter.contains("=") {
                    // key=value format
                    let parts = tagFilter.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        let key = String(parts[0]).lowercased()
                        let value = String(parts[1]).lowercased()
                        cards = cards.filter { card in
                            card.tags.contains { $0.key.lowercased() == key && $0.value.lowercased() == value }
                        }
                    }
                } else {
                    // key only format
                    let key = tagFilter.lowercased()
                    cards = cards.filter { card in
                        card.tags.contains { $0.key.lowercased() == key }
                    }
                }
            }

            // Filter by badge
            if let badgeFilter = badgeFilter {
                let filterLower = badgeFilter.lowercased()
                cards = cards.filter { $0.badge.lowercased().contains(filterLower) }
            }

            // Filter by favourites
            if favouritesOnly {
                cards = cards.filter { $0.isFavourite }
            }

            let output = cards.map { TerminalOutput(from: $0, columnName: board.columnName(for: $0.columnId)) }
            let json = try JSONHelper.encode(output)
            return CallTool.Result(content: [.text(json)])

        } catch {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    func handleOpen(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let identifier = arguments?["identifier"]?.stringValue else {
            throw MCPError.invalidParams("identifier is required")
        }

        do {
            let board = try loadBoard()

            guard let card = board.findTerminal(identifier: identifier) else {
                return CallTool.Result(
                    content: [.text("Error: Terminal not found: \(identifier)")],
                    isError: true
                )
            }

            let output = TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
            let json = try JSONHelper.encode(output)

            // Note: MCP server is read-only, it cannot open terminals in the GUI
            // The CLI uses URL schemes to communicate with the app
            // For MCP, we just return the terminal data
            return CallTool.Result(content: [.text(json)])

        } catch {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    func handleCreate(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        // MCP server is read-only by design - creation requires app interaction
        // Return instructions for how to create via CLI or app
        let name = arguments?["name"]?.stringValue ?? "New Terminal"
        let column = arguments?["column"]?.stringValue ?? "To Do"
        let path = arguments?["path"]?.stringValue ?? "."

        let message = """
            MCP Server is read-only for safety. To create a terminal, use the CLI:

            termq create --name "\(name)" --column "\(column)" --path "\(path)"

            Or create it directly in the TermQ app.
            """
        return CallTool.Result(content: [.text(message)])
    }

    func handleSet(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let identifier = arguments?["identifier"]?.stringValue else {
            throw MCPError.invalidParams("identifier is required")
        }

        // MCP server is read-only by design - modification requires app interaction
        // Build CLI command for the user
        var cliArgs: [String] = ["termq set \"\(identifier)\""]

        if let name = arguments?["name"]?.stringValue {
            cliArgs.append("--name \"\(name)\"")
        }
        if let description = arguments?["description"]?.stringValue {
            cliArgs.append("--description \"\(description)\"")
        }
        if let column = arguments?["column"]?.stringValue {
            cliArgs.append("--column \"\(column)\"")
        }
        if let badge = arguments?["badge"]?.stringValue {
            cliArgs.append("--badge \"\(badge)\"")
        }
        if let llmPrompt = arguments?["llmPrompt"]?.stringValue {
            cliArgs.append("--llm-prompt \"\(llmPrompt)\"")
        }
        if let llmNextAction = arguments?["llmNextAction"]?.stringValue {
            cliArgs.append("--llm-next-action \"\(llmNextAction)\"")
        }
        if let favourite = arguments?["favourite"]?.boolValue {
            cliArgs.append(favourite ? "--favourite" : "--unfavourite")
        }

        let cliCommand = cliArgs.joined(separator: " ")

        let message = """
            MCP Server is read-only for safety. To modify the terminal, use the CLI:

            \(cliCommand)
            """
        return CallTool.Result(content: [.text(message)])
    }

    func handleMove(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let identifier = arguments?["identifier"]?.stringValue,
            let column = arguments?["column"]?.stringValue
        else {
            throw MCPError.invalidParams("identifier and column are required")
        }

        // MCP server is read-only by design
        let message = """
            MCP Server is read-only for safety. To move the terminal, use the CLI:

            termq move "\(identifier)" "\(column)"
            """
        return CallTool.Result(content: [.text(message)])
    }
}
