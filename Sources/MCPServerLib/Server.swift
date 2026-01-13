import Foundation
import MCP

/// TermQ MCP Server implementation
///
/// Provides Model Context Protocol interface for LLM assistants to interact
/// with TermQ's terminal management functionality.
///
/// - Warning: This server is designed for LOCAL USE ONLY. Do not deploy
///   as a networked service or expose to the internet.
public final class TermQMCPServer: @unchecked Sendable {
    private let server: Server
    private let dataDirectory: URL?

    /// Server name identifier
    public static let serverName = "termq"

    /// Server version
    public static let serverVersion = "1.0.0"

    /// Initialize the MCP server
    /// - Parameter dataDirectory: Optional custom data directory (nil uses default)
    public init(dataDirectory: URL? = nil) {
        self.dataDirectory = dataDirectory
        self.server = Server(
            name: Self.serverName,
            version: Self.serverVersion,
            capabilities: Server.Capabilities(
                logging: .init(),
                prompts: .init(listChanged: true),
                resources: .init(subscribe: true, listChanged: true),
                tools: .init(listChanged: true)
            )
        )
    }

    // MARK: - Running

    /// Run the server with the specified transport
    /// - Parameter transport: The transport to use (stdio or HTTP)
    public func run(transport: any Transport) async throws {
        // Register handlers before starting
        await registerHandlers()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Handler Registration

    private func registerHandlers() async {
        // Register tool handlers
        _ = await server.withMethodHandler(ListTools.self) { [weak self] _ in
            guard self != nil else {
                return ListTools.Result(tools: [])
            }
            return ListTools.Result(tools: Self.availableTools)
        }

        _ = await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self = self else {
                throw MCPError.internalError("Server deallocated")
            }
            return try await self.handleToolCall(params)
        }

        // Register resource handlers
        _ = await server.withMethodHandler(ListResources.self) { [weak self] _ in
            guard self != nil else {
                return ListResources.Result(resources: [])
            }
            return ListResources.Result(resources: Self.availableResources)
        }

        _ = await server.withMethodHandler(ReadResource.self) { [weak self] params in
            guard let self = self else {
                throw MCPError.internalError("Server deallocated")
            }
            return try await self.handleResourceRead(params)
        }

        // Register prompt handlers
        _ = await server.withMethodHandler(ListPrompts.self) { [weak self] _ in
            guard self != nil else {
                return ListPrompts.Result(prompts: [])
            }
            return ListPrompts.Result(prompts: Self.availablePrompts)
        }

        _ = await server.withMethodHandler(GetPrompt.self) { [weak self] params in
            guard let self = self else {
                throw MCPError.internalError("Server deallocated")
            }
            return try await self.handlePromptGet(params)
        }
    }

    // MARK: - Tool Handlers

    private func handleToolCall(_ params: CallTool.Parameters) async throws -> CallTool.Result {
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

    private func handlePending(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let actionsOnly = arguments?["actionsOnly"]?.boolValue ?? false

        do {
            let board = try BoardLoader.loadBoard(dataDirectory: dataDirectory)
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

    private func handleContext() async throws -> CallTool.Result {
        let context = Self.contextDocumentation
        return CallTool.Result(content: [.text(context)])
    }

    private func handleList(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let columnFilter = arguments?["column"]?.stringValue
        let columnsOnly = arguments?["columnsOnly"]?.boolValue ?? false

        do {
            let board = try BoardLoader.loadBoard(dataDirectory: dataDirectory)

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

    private func handleFind(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let nameFilter = arguments?["name"]?.stringValue
        let columnFilter = arguments?["column"]?.stringValue
        let tagFilter = arguments?["tag"]?.stringValue
        let idFilter = arguments?["id"]?.stringValue
        let badgeFilter = arguments?["badge"]?.stringValue
        let favouritesOnly = arguments?["favourites"]?.boolValue ?? false

        do {
            let board = try BoardLoader.loadBoard(dataDirectory: dataDirectory)
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

    private func handleOpen(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let identifier = arguments?["identifier"]?.stringValue else {
            throw MCPError.invalidParams("identifier is required")
        }

        do {
            let board = try BoardLoader.loadBoard(dataDirectory: dataDirectory)

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

    private func handleCreate(_ arguments: [String: Value]?) async throws -> CallTool.Result {
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

    private func handleSet(_ arguments: [String: Value]?) async throws -> CallTool.Result {
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

    private func handleMove(_ arguments: [String: Value]?) async throws -> CallTool.Result {
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

    // MARK: - Resource Handlers

    private func handleResourceRead(_ params: ReadResource.Parameters) async throws -> ReadResource.Result {
        let uri = params.uri

        switch uri {
        case "termq://terminals":
            do {
                let board = try BoardLoader.loadBoard(dataDirectory: dataDirectory)
                let output = board.activeCards.map {
                    TerminalOutput(from: $0, columnName: board.columnName(for: $0.columnId))
                }
                let json = try JSONHelper.encode(output)
                return ReadResource.Result(contents: [.text(json, uri: uri)])
            } catch {
                return ReadResource.Result(contents: [.text("[]", uri: uri)])
            }

        case "termq://columns":
            do {
                let board = try BoardLoader.loadBoard(dataDirectory: dataDirectory)
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

        case "termq://pending":
            do {
                let board = try BoardLoader.loadBoard(dataDirectory: dataDirectory)
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

        case "termq://context":
            return ReadResource.Result(contents: [.text(Self.contextDocumentation, uri: uri)])

        default:
            throw MCPError.invalidRequest("Unknown resource: \(uri)")
        }
    }

    // MARK: - Prompt Handlers

    private func handlePromptGet(_ params: GetPrompt.Parameters) async throws -> GetPrompt.Result {
        switch params.name {
        case "session_start":
            return try await buildSessionStartPrompt()

        case "workflow_guide":
            return GetPrompt.Result(
                description: "TermQ Workflow Guide",
                messages: [
                    .user(.text(text: Self.contextDocumentation))
                ]
            )

        case "terminal_summary":
            let terminal = params.arguments?["terminal"] ?? "unknown"
            return try await buildTerminalSummaryPrompt(identifier: String(describing: terminal))

        default:
            throw MCPError.invalidRequest("Unknown prompt: \(params.name)")
        }
    }

    private func buildSessionStartPrompt() async throws -> GetPrompt.Result {
        var content = "# TermQ Session Start\n\n"

        do {
            let board = try BoardLoader.loadBoard(dataDirectory: dataDirectory)

            // Pending actions
            let pendingCards = board.activeCards.filter { !$0.llmNextAction.isEmpty }
            if pendingCards.isEmpty {
                content += "## Pending Actions\n\nNo pending actions.\n\n"
            } else {
                content += "## Pending Actions\n\n"
                for card in pendingCards {
                    content += "- **\(card.title)**: \(card.llmNextAction)\n"
                }
                content += "\n"
            }

            // Board overview
            content += "## Board Overview\n\n"
            for column in board.sortedColumns() {
                let count = board.activeCards.filter { $0.columnId == column.id }.count
                content += "- \(column.name): \(count) terminals\n"
            }
            content += "\n"

            // Recommended actions
            content += "## Recommended Actions\n\n"
            if !pendingCards.isEmpty {
                content += "1. Address pending actions above\n"
            }
            content += "2. Use `termq_pending` for detailed terminal view\n"
            content += "3. Use `termq_context` for workflow guide\n"

        } catch {
            content += "Error loading board: \(error.localizedDescription)\n\n"
            content += "Make sure TermQ has been run at least once to create the board file."
        }

        return GetPrompt.Result(
            description: "TermQ Session Start",
            messages: [.user(.text(text: content))]
        )
    }

    private func buildTerminalSummaryPrompt(identifier: String) async throws -> GetPrompt.Result {
        var content = "# Terminal Summary: \(identifier)\n\n"

        do {
            let board = try BoardLoader.loadBoard(dataDirectory: dataDirectory)

            guard let card = board.findTerminal(identifier: identifier) else {
                content += "Terminal not found: \(identifier)"
                return GetPrompt.Result(
                    description: "Terminal Summary: \(identifier)",
                    messages: [.user(.text(text: content))]
                )
            }

            content += "## Details\n\n"
            content += "- **Name**: \(card.title)\n"
            content += "- **Column**: \(board.columnName(for: card.columnId))\n"
            content += "- **Path**: \(card.workingDirectory)\n"
            content += "- **ID**: \(card.id.uuidString)\n"

            if !card.description.isEmpty {
                content += "\n## Description\n\n\(card.description)\n"
            }

            if !card.llmPrompt.isEmpty {
                content += "\n## LLM Context\n\n\(card.llmPrompt)\n"
            }

            if !card.llmNextAction.isEmpty {
                content += "\n## Pending Action\n\n\(card.llmNextAction)\n"
            }

            if !card.tags.isEmpty {
                content += "\n## Tags\n\n"
                for tag in card.tags {
                    content += "- \(tag.key): \(tag.value)\n"
                }
            }

        } catch {
            content += "Error loading board: \(error.localizedDescription)"
        }

        return GetPrompt.Result(
            description: "Terminal Summary: \(identifier)",
            messages: [.user(.text(text: content))]
        )
    }

    // MARK: - Context Documentation

    private static let contextDocumentation = """
        # TermQ MCP Server - LLM Assistant Guide

        You are working with TermQ, a Kanban-style terminal manager that enables
        cross-session continuity for LLM assistants.

        ## SESSION START CHECKLIST (Do This First!)

        1. Use the `termq_pending` tool to see what needs attention:
           - Shows terminals with queued tasks (llmNextAction)
           - Shows staleness indicators

        2. Check the summary in the output:
           - `withNextAction`: Terminals with tasks queued for you
           - `stale`: Terminals that haven't been touched recently

        3. If there are pending actions, handle them or acknowledge to user.

        ## SESSION END CHECKLIST (Do This Before Ending!)

        1. **Queue next action** if work is incomplete:
           ```
           termq set "Terminal" --llm-next-action "Continue from: [specific point]"
           ```

        2. **Update staleness** to mark as recently worked:
           ```
           termq set "Terminal" --tag staleness=fresh
           ```

        3. **Update persistent context** if you learned something important:
           ```
           termq set "Terminal" --llm-prompt "Updated project context..."
           ```

        ## TAG SCHEMA (Cross-Session State Tracking)

        Use these tags to track state across sessions:

        | Tag | Values | Purpose |
        |-----|--------|---------|
        | `staleness` | fresh, ageing, stale | How recently worked on |
        | `status` | pending, active, blocked, review | Work state |
        | `project` | org/repo | Project identifier |
        | `worktree` | branch-name | Current git branch |
        | `priority` | high, medium, low | Importance |
        | `blocked-by` | ci, review, user | What's blocking |
        | `type` | feature, bugfix, chore, docs | Work category |

        ## AVAILABLE MCP TOOLS

        ### Read-Only Tools (Fully Implemented)
        - `termq_pending` - Check terminals needing attention (SESSION START)
        - `termq_context` - Get this documentation
        - `termq_list` - List all terminals or filter by column
        - `termq_find` - Search terminals by name, column, tag, etc.
        - `termq_open` - Get terminal details by name, UUID, or path

        ### Write Tools (Return CLI Commands)
        The MCP server is read-only for safety. These tools return CLI commands:
        - `termq_create` - Returns CLI command to create terminal
        - `termq_set` - Returns CLI command to modify terminal
        - `termq_move` - Returns CLI command to move terminal

        ## TERMINAL FIELDS

        Each terminal has:
        - **name**: Display name
        - **description**: What this terminal is for
        - **column**: Workflow stage (To Do, In Progress, Done)
        - **path**: Working directory
        - **tags**: Key-value metadata (use for state tracking!)
        - **llmPrompt**: Persistent context (never auto-cleared)
        - **llmNextAction**: One-time task (cleared after terminal opens)

        ## TIPS

        - ALWAYS use `termq_pending` at session start
        - ALWAYS set `llmNextAction` when parking incomplete work
        - Use `staleness` tag to track what needs attention
        - Use `project` tag to group related terminals
        - Keep `llmPrompt` updated with key project context
        - Move terminals through columns as work progresses
        """
}
