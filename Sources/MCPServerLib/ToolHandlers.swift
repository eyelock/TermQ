import Foundation
import MCP
import TermQShared

// MARK: - Tool Handler Implementations

extension TermQMCPServer {
    /// Build a `CallTool.Result` that satisfies the tool's `outputSchema` by populating
    /// both legacy `text` content (for back-compat with clients that don't read
    /// `structuredContent`) and the new `structuredContent` field. The dual encoding
    /// roughly doubles the response payload — acceptable on stdio for a single-user app
    /// (see audit §3.3 payload note), and the `text` mirror can be dropped after one
    /// release once clients have migrated.
    func structuredResult<T: Codable>(_ output: T) throws -> CallTool.Result {
        let json = try JSONHelper.encode(output)
        // Throwing init handles the Codable -> Value conversion internally.
        return try CallTool.Result(
            content: [.text(text: json, annotations: nil, _meta: nil)],
            structuredContent: output
        )
    }

    /// Dispatch tool calls to appropriate handlers
    func dispatchToolCall(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "pending":
            return try await handlePending(params.arguments)
        case "context":
            return try await handleContext()
        case "list":
            return try await handleList(params.arguments)
        case "find":
            return try await handleFind(params.arguments)
        case "open":
            return try await handleOpen(params.arguments)
        case "create":
            return try await handleCreate(params.arguments)
        case "set":
            return try await handleSet(params.arguments)
        case "move":
            return try await handleMove(params.arguments)
        case "get":
            return try await handleGet(params.arguments)
        case "record_handshake":
            return try await handleRecordHandshake(params.arguments)
        case "whoami":
            return try await handleWhoami(params.arguments)
        case "restore":
            return try await handleRestore(params.arguments)
        case "create_column":
            return try await handleCreateColumn(params.arguments)
        case "rename_column":
            return try await handleRenameColumn(params.arguments)
        case "delete_column":
            return try await handleDeleteColumn(params.arguments)
        case "create_worktree":
            return try await handleCreateWorktree(params.arguments)
        case "remove_worktree":
            return try await handleRemoveWorktree(params.arguments)
        case "harness_launch":
            return try await handleHarnessLaunch(params.arguments)
        case "delete":
            return try await handleDelete(params.arguments)
        default:
            throw MCPError.invalidRequest("Unknown tool: \(params.name)")
        }
    }

    // MARK: - Helper Types

    /// Parameters for updating a terminal card
    private struct SetParameters {
        let name: String?
        let description: String?
        let badge: String?
        let column: String?
        let llmPrompt: String?
        let llmNextAction: String?
        let initCommand: String?
        let favourite: Bool?
        let tags: [(key: String, value: String)]?
        let replaceTags: Bool
    }

    // MARK: - Tool Implementations

    func handlePending(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let actionsOnly = InputValidator.optionalBool("actionsOnly", from: arguments)

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

            return try structuredResult(output)

        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    func handleContext() async throws -> CallTool.Result {
        let context = Self.contextDocumentation
        return CallTool.Result(content: [.text(text: context, annotations: nil, _meta: nil)])
    }

    func handleList(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let columnFilter = InputValidator.optionalString("column", from: arguments)
        let columnsOnly = InputValidator.optionalBool("columnsOnly", from: arguments)
        let includeDeleted = InputValidator.optionalBool("includeDeleted", from: arguments)
        let cursor = InputValidator.optionalString("cursor", from: arguments)
        let limit = (arguments?["limit"]).flatMap { value -> Int? in
            if case .int(let i) = value { return i }
            return nil
        }

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
                return try structuredResult(columns)
            }

            // Source set — active by default, all cards (incl. soft-deleted) when requested.
            var cards = includeDeleted ? board.cards : board.activeCards
            cards = CardFilterEngine.filterByColumn(cards, column: columnFilter, columns: board.columns)

            // Sort by column order, then card order — stable across pagination calls.
            cards = CardFilterEngine.sortByColumnThenOrder(cards, columns: board.columns)

            let paginated = paginate(cards, cursor: cursor, limit: limit)
            let output = paginated.items.map {
                TerminalOutput(from: $0, columnName: board.columnName(for: $0.columnId))
            }
            // When the caller asked for pagination, wrap; otherwise emit the bare array
            // for back-compat with existing clients (the outputSchema only describes that
            // shape — paginated callers can read `_meta.nextCursor` from the response).
            if cursor != nil || limit != nil {
                return try structuredResult(
                    PaginatedTerminals(items: output, nextCursor: paginated.nextCursor))
            }
            return try structuredResult(output)

        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    /// Envelope used when the caller opted into pagination by passing `cursor` or
    /// `limit`. Unpaginated calls keep returning the bare array.
    struct PaginatedTerminals: Codable {
        let items: [TerminalOutput]
        let nextCursor: String?
    }

    /// Cursor-based pagination over a stable slice. Cursor is a base64-encoded integer
    /// offset — opaque to the client, stable while sort order is stable.
    func paginate<T>(_ items: [T], cursor: String?, limit: Int?) -> (items: [T], nextCursor: String?) {
        let start: Int = {
            guard let cursor,
                let data = Data(base64Encoded: cursor),
                let s = String(data: data, encoding: .utf8),
                let n = Int(s),
                n >= 0,
                n <= items.count
            else { return 0 }
            return n
        }()
        let end: Int = {
            guard let limit, limit > 0 else { return items.count }
            return min(start + limit, items.count)
        }()
        let slice = Array(items[start..<end])
        let nextCursor: String? = {
            guard end < items.count else { return nil }
            return Data("\(end)".utf8).base64EncodedString()
        }()
        return (slice, nextCursor)
    }

    func handleFind(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let query = InputValidator.optionalString("query", from: arguments)
        let nameFilter = InputValidator.optionalString("name", from: arguments)
        let columnFilter = InputValidator.optionalString("column", from: arguments)
        let tagFilter = InputValidator.optionalString("tag", from: arguments)
        let badgeFilter = InputValidator.optionalString("badge", from: arguments)
        let favouritesOnly = InputValidator.optionalBool("favourites", from: arguments)

        // Validate optional UUID filter
        let idFilter: UUID?
        do {
            idFilter = try InputValidator.optionalUUID("id", from: arguments)
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }

        do {
            let board = try loadBoard()
            var cards = board.activeCards
            var relevanceScores: [UUID: Int] = [:]

            // Smart query search (multi-word, multi-field)
            if let query = query, !query.isEmpty {
                let queryWords = CardFilterEngine.normalizeToWords(query)
                guard !queryWords.isEmpty else {
                    return try structuredResult([TerminalOutput]())
                }

                cards = cards.filter { card in
                    let score = CardFilterEngine.relevanceScore(card: card, queryWords: queryWords)
                    if score > 0 {
                        relevanceScores[card.id] = score
                        return true
                    }
                    return false
                }
            }

            // Filter by ID (exact match)
            if let idFilter = idFilter {
                cards = cards.filter { $0.id == idFilter }
            }

            // Filter by name (case-insensitive partial match)
            if let nameFilter = nameFilter {
                let filterLower = nameFilter.lowercased()
                cards = cards.filter { $0.title.lowercased().contains(filterLower) }
            }

            cards = CardFilterEngine.filterByColumn(cards, column: columnFilter, columns: board.columns)
            cards = try CardFilterEngine.filterByTag(cards, tagFilter: tagFilter)
            cards = CardFilterEngine.filterByBadge(cards, badge: badgeFilter)
            if favouritesOnly { cards = CardFilterEngine.filterFavourites(cards) }

            if !relevanceScores.isEmpty {
                cards = CardFilterEngine.sortByRelevance(cards, scores: relevanceScores)
            }

            let cursor = InputValidator.optionalString("cursor", from: arguments)
            let limit = (arguments?["limit"]).flatMap { value -> Int? in
                if case .int(let i) = value { return i }
                return nil
            }
            let paginated = paginate(cards, cursor: cursor, limit: limit)
            let output = paginated.items.map {
                TerminalOutput(from: $0, columnName: board.columnName(for: $0.columnId))
            }
            if cursor != nil || limit != nil {
                return try structuredResult(
                    PaginatedTerminals(items: output, nextCursor: paginated.nextCursor))
            }
            return try structuredResult(output)

        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    func handleOpen(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let identifier: String
        do {
            identifier = try InputValidator.requireNonEmptyString("identifier", from: arguments, tool: "open")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }

        do {
            let board = try loadBoard()

            guard let card = board.findTerminal(identifier: identifier) else {
                return CallTool.Result(
                    content: [.text(text: "Error: Terminal not found: \(identifier)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }

            let output = TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))

            // Note: MCP server is read-only, it cannot open terminals in the GUI
            // The CLI uses URL schemes to communicate with the app
            // For MCP, we just return the terminal data
            return try structuredResult(output)

        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    /// Record an LLM handshake — write the `lastLLMGet` timestamp without returning the
    /// card payload. Idiomatic pair with reading `termq://terminal/{id}` as a pure
    /// resource. The `get` tool keeps doing both for one release as the deprecation
    /// alias for callers who haven't migrated yet (see audit §3.1 deprecation policy).
    func handleRecordHandshake(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let id: String
        do {
            let uuid = try InputValidator.requireUUID("id", from: arguments, tool: "record_handshake")
            id = uuid.uuidString
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }

        do {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let nowString = formatter.string(from: Date())
            _ = try BoardWriter.updateCard(
                identifier: id,
                updates: ["lastLLMGet": nowString],
                dataDirectory: dataDirectory
            )
            return CallTool.Result(
                content: [
                    .text(
                        text: "{\"ok\": true, \"id\": \"\(id)\", \"lastLLMGet\": \"\(nowString)\"}",
                        annotations: nil, _meta: nil)
                ])
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    func handleGet(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let id: String
        do {
            let uuid = try InputValidator.requireUUID("id", from: arguments, tool: "get")
            id = uuid.uuidString
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }

        do {
            // Record the LLM handshake - this terminal's LLM now knows about TermQ
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let nowString = formatter.string(from: Date())

            _ = try BoardWriter.updateCard(
                identifier: id,
                updates: ["lastLLMGet": nowString],
                dataDirectory: dataDirectory
            )

            // Reload to get updated card
            let board = try loadBoard()

            guard let card = board.findTerminal(identifier: id) else {
                return CallTool.Result(
                    content: [.text(text: "Error: Terminal not found with ID: \(id)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }

            let output = TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
            return try structuredResult(output)

        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    func handleCreate(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        // Parse all arguments upfront
        let name = InputValidator.optionalString("name", from: arguments)
        let column = InputValidator.optionalString("column", from: arguments)
        let description = InputValidator.optionalString("description", from: arguments)
        let llmPrompt = InputValidator.optionalString("llmPrompt", from: arguments)
        let llmNextAction = InputValidator.optionalString("llmNextAction", from: arguments)
        let initCommand = InputValidator.optionalString("initCommand", from: arguments)

        // Parse tags if provided (array of "key=value" strings)
        var tags: [(key: String, value: String)]?
        if let tagValues = arguments?["tags"]?.arrayValue {
            tags = tagValues.compactMap { tagValue -> (key: String, value: String)? in
                guard let tagStr = tagValue.stringValue,
                    let eqIndex = tagStr.firstIndex(of: "=")
                else { return nil }
                let key = String(tagStr[..<eqIndex])
                let value = String(tagStr[tagStr.index(after: eqIndex)...])
                return (key: key, value: value)
            }
        }

        // Validate path if provided
        let path: String
        do {
            if let providedPath = try InputValidator.optionalPath("path", from: arguments, mustExist: false) {
                path = providedPath
            } else {
                path = FileManager.default.currentDirectoryPath
            }
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }

        // Check if GUI is available
        let guiAvailable: Bool
        if GUIDetector.isGUIRunning() {
            guiAvailable = true
        } else {
            guiAvailable = await GUIDetector.waitForGUI()
        }

        let options = HeadlessWriter.CardCreationOptions(
            workingDirectory: path,
            name: name,
            column: column,
            description: description,
            llmPrompt: llmPrompt,
            llmNextAction: llmNextAction,
            initCommand: initCommand,
            tags: tags
        )
        if guiAvailable {
            return try await handleCreateViaGUI(options)
        } else {
            return try await handleCreateHeadless(options)
        }
    }

    private func handleCreateViaGUI(_ options: HeadlessWriter.CardCreationOptions) async throws -> CallTool.Result {
        // Generate card ID upfront so we can return it
        let cardId = UUID()

        // Build and open the URL to create the terminal via GUI
        let urlString = URLOpener.buildOpenURL(
            params: URLOpener.OpenURLParams(
                cardId: cardId,
                path: options.workingDirectory,
                name: options.name,
                description: options.description,
                column: options.column,
                tags: options.tags,
                llmPrompt: options.llmPrompt,
                llmNextAction: options.llmNextAction,
                initCommand: options.initCommand
            )
        )

        do {
            try await URLOpener.open(urlString)

            // Wait for GUI to process with retry and exponential backoff
            let dataDir = dataDirectory
            let found = await URLOpener.waitForCondition {
                let board = try BoardLoader.loadBoard(dataDirectory: dataDir)
                return board.findTerminal(identifier: cardId.uuidString) != nil
            }

            if found {
                let board = try loadBoard()
                if let card = board.findTerminal(identifier: cardId.uuidString) {
                    let output = TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
                    return try structuredResult(output)
                }
            }

            // Card not found after retries - GUI might still be processing
            let pendingOutput = PendingCreateResponse(
                id: cardId.uuidString,
                message: "Terminal creation requested. The terminal may take a moment to appear in TermQ."
            )
            return try structuredResult(pendingOutput)
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    private func handleCreateHeadless(_ options: HeadlessWriter.CardCreationOptions) async throws -> CallTool.Result {
        do {
            let card = try HeadlessWriter.createCard(options, dataDirectory: dataDirectory)

            let board = try loadBoard()
            let output = TerminalOutput(
                from: card,
                columnName: board.columnName(for: card.columnId)
            )
            return try structuredResult(output)

        } catch let error as BoardWriter.WriteError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    func handleSet(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let identifier: String
        do {
            identifier = try InputValidator.requireNonEmptyString("identifier", from: arguments, tool: "set")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }

        // First, find the card to get its UUID
        let board = try loadBoard()
        guard let card = board.findTerminal(identifier: identifier) else {
            return CallTool.Result(
                content: [.text(text: "Error: Terminal not found: \(identifier)", annotations: nil, _meta: nil)],
                isError: true)
        }

        // Parse tags if provided (accepts either `tag` singular string or `tags` array of "key=value")
        var tags: [(key: String, value: String)]?
        let parseTagString: (String) -> (key: String, value: String)? = { tagStr in
            guard let eqIndex = tagStr.firstIndex(of: "=") else { return nil }
            let key = String(tagStr[..<eqIndex])
            let value = String(tagStr[tagStr.index(after: eqIndex)...])
            return (key: key, value: value)
        }
        if let tagValues = arguments?["tags"]?.arrayValue {
            tags = tagValues.compactMap { tagValue -> (key: String, value: String)? in
                guard let tagStr = tagValue.stringValue else { return nil }
                return parseTagString(tagStr)
            }
        }
        if let singleTag = arguments?["tag"]?.stringValue, let parsed = parseTagString(singleTag) {
            var merged = tags ?? []
            merged.append(parsed)
            tags = merged
        }

        let replaceTags = InputValidator.optionalBool("replaceTags", from: arguments)

        // Create parameters struct
        let params = SetParameters(
            name: arguments?["name"]?.stringValue,
            description: arguments?["description"]?.stringValue,
            badge: arguments?["badge"]?.stringValue,
            column: arguments?["column"]?.stringValue,
            llmPrompt: arguments?["llmPrompt"]?.stringValue,
            llmNextAction: arguments?["llmNextAction"]?.stringValue,
            initCommand: arguments?["initCommand"]?.stringValue,
            favourite: arguments?["favourite"]?.boolValue,
            tags: tags,
            replaceTags: replaceTags
        )

        // Check if GUI is available
        let guiAvailable: Bool
        if GUIDetector.isGUIRunning() {
            guiAvailable = true
        } else {
            guiAvailable = await GUIDetector.waitForGUI()
        }

        if guiAvailable {
            // GUI path - use URL scheme
            return try await handleSetViaGUI(card: card, params: params)
        } else {
            // Headless path - use BoardWriter directly
            return try await handleSetHeadless(identifier: identifier, params: params)
        }
    }

    private func handleSetViaGUI(card: Card, params: SetParameters) async throws -> CallTool.Result {
        // Build and open the URL to update the terminal via GUI
        let urlString = URLOpener.buildUpdateURL(
            params: URLOpener.UpdateURLParams(
                cardId: card.id,
                name: params.name,
                description: params.description,
                badge: params.badge,
                column: params.column,
                llmPrompt: params.llmPrompt,
                llmNextAction: params.llmNextAction,
                initCommand: params.initCommand,
                favourite: params.favourite,
                tags: params.tags,
                replaceTags: params.replaceTags
            )
        )

        do {
            try await URLOpener.open(urlString)

            // Wait for GUI to process with retry and exponential backoff
            let dataDir = dataDirectory
            let cardIdStr = card.id.uuidString
            _ = await URLOpener.waitForCondition {
                // Just verify the card still exists - we trust the GUI applied the update
                let board = try BoardLoader.loadBoard(dataDirectory: dataDir)
                return board.findTerminal(identifier: cardIdStr) != nil
            }

            // Reload to get updated state
            let updatedBoard = try loadBoard()
            if let updatedCard = updatedBoard.findTerminal(identifier: card.id.uuidString) {
                let output = TerminalOutput(
                    from: updatedCard, columnName: updatedBoard.columnName(for: updatedCard.columnId))
                return try structuredResult(output)
            } else {
                return CallTool.Result(
                    content: [.text(text: "Error: Terminal not found after update", annotations: nil, _meta: nil)],
                    isError: true)
            }
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    private func handleSetHeadless(identifier: String, params: SetParameters) async throws -> CallTool.Result {
        do {
            let updateParams = HeadlessWriter.UpdateParameters(
                name: params.name,
                description: params.description,
                badge: params.badge,
                llmPrompt: params.llmPrompt,
                llmNextAction: params.llmNextAction,
                favourite: params.favourite,
                tags: params.tags,
                replaceTags: params.replaceTags
            )

            var card = try HeadlessWriter.updateCard(
                identifier: identifier,
                params: updateParams,
                dataDirectory: dataDirectory
            )

            // `set` with a `column` argument is equivalent to a move — apply it
            // after the field updates so a rename + column change in one call both land.
            if let column = params.column {
                card = try HeadlessWriter.moveCard(
                    identifier: card.id.uuidString,
                    toColumn: column,
                    dataDirectory: dataDirectory
                )
            }

            let board = try loadBoard()
            let output = TerminalOutput(
                from: card,
                columnName: board.columnName(for: card.columnId)
            )
            return try structuredResult(output)

        } catch let error as BoardWriter.WriteError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    func handleMove(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let identifier: String
        let column: String
        do {
            identifier = try InputValidator.requireNonEmptyString("identifier", from: arguments, tool: "move")
            column = try InputValidator.requireNonEmptyString("column", from: arguments, tool: "move")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }

        // First, find the card to get its UUID
        let board = try loadBoard()
        guard let card = board.findTerminal(identifier: identifier) else {
            return CallTool.Result(
                content: [.text(text: "Error: Terminal not found: \(identifier)", annotations: nil, _meta: nil)],
                isError: true)
        }

        // Check if GUI is available
        let guiAvailable: Bool
        if GUIDetector.isGUIRunning() {
            guiAvailable = true
        } else {
            guiAvailable = await GUIDetector.waitForGUI()
        }

        if guiAvailable {
            // GUI path - use URL scheme
            return try await handleMoveViaGUI(card: card, column: column)
        } else {
            // Headless path - use BoardWriter directly
            return try await handleMoveHeadless(identifier: identifier, column: column)
        }
    }

    private func handleMoveViaGUI(card: Card, column: String) async throws -> CallTool.Result {
        // Build and open the URL to move the terminal via GUI
        let urlString = URLOpener.buildMoveURL(cardId: card.id, column: column)

        do {
            try await URLOpener.open(urlString)

            // Wait for GUI to process with retry and exponential backoff
            let dataDir = dataDirectory
            let cardIdStr = card.id.uuidString
            let targetColumn = column.lowercased()
            _ = await URLOpener.waitForCondition {
                // Verify the card moved to the target column
                let board = try BoardLoader.loadBoard(dataDirectory: dataDir)
                guard let movedCard = board.findTerminal(identifier: cardIdStr) else { return false }
                let columnName = board.columnName(for: movedCard.columnId).lowercased()
                return columnName == targetColumn
            }

            // Reload to get updated state
            let updatedBoard = try loadBoard()
            if let updatedCard = updatedBoard.findTerminal(identifier: card.id.uuidString) {
                let output = TerminalOutput(
                    from: updatedCard, columnName: updatedBoard.columnName(for: updatedCard.columnId))
                return try structuredResult(output)
            } else {
                return CallTool.Result(
                    content: [.text(text: "Error: Terminal not found after move", annotations: nil, _meta: nil)],
                    isError: true)
            }
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    private func handleMoveHeadless(identifier: String, column: String) async throws -> CallTool.Result {
        do {
            let card = try HeadlessWriter.moveCard(
                identifier: identifier,
                toColumn: column,
                dataDirectory: dataDirectory
            )

            let board = try loadBoard()
            let output = TerminalOutput(
                from: card,
                columnName: board.columnName(for: card.columnId)
            )
            return try structuredResult(output)

        } catch let error as BoardWriter.WriteError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    func handleDelete(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let identifier: String
        do {
            identifier = try InputValidator.requireNonEmptyString("identifier", from: arguments, tool: "delete")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }

        let permanent = InputValidator.optionalBool("permanent", from: arguments)

        // First, find the card to get its UUID
        let board = try loadBoard()
        guard let card = board.findTerminal(identifier: identifier) else {
            return CallTool.Result(
                content: [.text(text: "Error: Terminal not found: \(identifier)", annotations: nil, _meta: nil)],
                isError: true)
        }

        // Check if GUI is available
        let guiAvailable: Bool
        if GUIDetector.isGUIRunning() {
            guiAvailable = true
        } else {
            guiAvailable = await GUIDetector.waitForGUI()
        }

        if guiAvailable {
            // GUI path - use URL scheme
            return try await handleDeleteViaGUI(card: card, permanent: permanent)
        } else {
            // Headless path - use BoardWriter directly
            return try await handleDeleteHeadless(identifier: identifier, permanent: permanent)
        }
    }

    private func handleDeleteViaGUI(card: Card, permanent: Bool) async throws -> CallTool.Result {
        // Build and open the URL to delete the terminal via GUI
        let urlString = URLOpener.buildDeleteURL(cardId: card.id, permanent: permanent)

        do {
            try await URLOpener.open(urlString)

            // Wait for GUI to process with retry and exponential backoff
            let dataDir = dataDirectory
            let cardIdStr = card.id.uuidString
            _ = await URLOpener.waitForCondition {
                // Verify the card is no longer in active cards (deleted or in bin)
                let board = try BoardLoader.loadBoard(dataDirectory: dataDir)
                return board.findTerminal(identifier: cardIdStr) == nil
            }

            let result = DeleteResponse(
                id: card.id.uuidString,
                permanent: permanent
            )
            return try structuredResult(result)
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    private func handleDeleteHeadless(identifier: String, permanent: Bool) async throws -> CallTool.Result {
        do {
            // Get card ID before deletion for response
            let board = try loadBoard()
            guard let card = board.findTerminal(identifier: identifier) else {
                return CallTool.Result(
                    content: [.text(text: "Error: Terminal not found: \(identifier)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }

            try HeadlessWriter.deleteCard(
                identifier: identifier,
                permanent: permanent,
                dataDirectory: dataDirectory
            )

            let result = DeleteResponse(
                id: card.id.uuidString,
                permanent: permanent
            )
            return try structuredResult(result)

        } catch let error as BoardWriter.WriteError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    // MARK: - Tier 2 handlers (whoami / restore / column CRUD)

    /// Resolve the current card from `TERMQ_TERMINAL_ID`. Returns a null structured
    /// content when the env var is unset, so callers can distinguish "no env" from a
    /// real error.
    func handleWhoami(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let envValue = ProcessInfo.processInfo.environment["TERMQ_TERMINAL_ID"],
            !envValue.isEmpty,
            let uuid = UUID(uuidString: envValue)
        else {
            // Surface as a non-error empty result — top-level Claude sessions (no TermQ
            // container) hit this routinely and shouldn't see an error.
            return CallTool.Result(
                content: [
                    .text(
                        text: "{\"terminal\": null, \"reason\": \"TERMQ_TERMINAL_ID not set or invalid\"}",
                        annotations: nil, _meta: nil)
                ])
        }
        do {
            let board = try loadBoard()
            guard let card = board.activeCards.first(where: { $0.id == uuid }) else {
                return CallTool.Result(
                    content: [
                        .text(
                            text:
                                "{\"terminal\": null, \"reason\": \"Terminal not found for env id\"}",
                            annotations: nil, _meta: nil)
                    ])
            }
            let output = TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
            return try structuredResult(output)
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    func handleRestore(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let identifier: String
        do {
            identifier = try InputValidator.requireString("identifier", from: arguments, tool: "restore")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
        do {
            let restored = try BoardWriter.restoreCard(
                identifier: identifier, dataDirectory: dataDirectory)
            let board = try loadBoard()
            let output = TerminalOutput(
                from: restored, columnName: board.columnName(for: restored.columnId))
            return try structuredResult(output)
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    func handleCreateColumn(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let name: String
        do {
            name = try InputValidator.requireString("name", from: arguments, tool: "create_column")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
        let description = InputValidator.optionalString("description", from: arguments) ?? ""
        let color = InputValidator.optionalString("color", from: arguments) ?? "#6B7280"
        do {
            let column = try BoardWriter.createColumn(
                name: name, description: description, color: color, dataDirectory: dataDirectory)
            return CallTool.Result(
                content: [
                    .text(
                        text:
                            "{\"id\": \"\(column.id.uuidString)\", \"name\": \"\(column.name)\"}",
                        annotations: nil, _meta: nil)
                ])
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    func handleRenameColumn(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let identifier: String
        let newName: String
        do {
            identifier = try InputValidator.requireString(
                "identifier", from: arguments, tool: "rename_column")
            newName = try InputValidator.requireString("newName", from: arguments, tool: "rename_column")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
        do {
            let column = try BoardWriter.renameColumn(
                identifier: identifier, newName: newName, dataDirectory: dataDirectory)
            return CallTool.Result(
                content: [
                    .text(
                        text:
                            "{\"id\": \"\(column.id.uuidString)\", \"name\": \"\(column.name)\"}",
                        annotations: nil, _meta: nil)
                ])
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    // MARK: - Tier 3 handlers — worktrees, harnesses

    /// Look up a registered repository by UUID. Returns the GitRepository or throws a
    /// CLI-flavoured error if not found / config can't be loaded.
    private func loadRepo(repoId: String) throws -> GitRepository {
        let config = try RepoConfigLoader.load()
        guard let uuid = UUID(uuidString: repoId),
            let repo = config.repositories.first(where: { $0.id == uuid })
        else {
            throw MCPError.invalidParams("Unknown repository: \(repoId)")
        }
        return repo
    }

    func handleCreateWorktree(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let repoId: String
        let branch: String
        do {
            repoId = try InputValidator.requireString("repoId", from: arguments, tool: "create_worktree")
            branch = try InputValidator.requireString("branch", from: arguments, tool: "create_worktree")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
        let createBranch = InputValidator.optionalBool("createBranch", from: arguments)
        do {
            let repo = try loadRepo(repoId: repoId)
            let basePath = repo.worktreeBasePath ?? URL(fileURLWithPath: repo.path).deletingLastPathComponent().path
            let worktreePath = "\(basePath)/\(branch)"
            // GitServiceShared.addWorktree always creates a branch (`-b <branch>`); the
            // `createBranch` flag here is informational — passing false won't suppress
            // the -b flag. Threaded onto the wire surface for future expansion.
            _ = createBranch
            try await GitServiceShared.addWorktree(
                repoPath: repo.path,
                branch: branch,
                worktreePath: worktreePath
            )
            return CallTool.Result(
                content: [
                    .text(
                        text:
                            "{\"ok\": true, \"path\": \"\(worktreePath)\", \"branch\": \"\(branch)\"}",
                        annotations: nil, _meta: nil)
                ])
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    func handleRemoveWorktree(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let repoId: String
        let path: String
        do {
            repoId = try InputValidator.requireString("repoId", from: arguments, tool: "remove_worktree")
            path = try InputValidator.requireString("path", from: arguments, tool: "remove_worktree")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
        // `force` is currently informational — GitServiceShared.removeWorktree doesn't
        // take a force flag in the public API yet. Threaded here so the wire surface is
        // stable; future revision can plumb it through.
        _ = InputValidator.optionalBool("force", from: arguments)
        do {
            let repo = try loadRepo(repoId: repoId)
            try await GitServiceShared.removeWorktree(repoPath: repo.path, worktreePath: path)
            return CallTool.Result(
                content: [
                    .text(text: "{\"ok\": true, \"removed\": \"\(path)\"}", annotations: nil, _meta: nil)
                ])
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    /// Launch a harness via `ynh run <harness>`. The most consequential write tool —
    /// permissioned clients should treat the `destructiveHint` as a strong prompt for
    /// user confirmation (full `elicitation/create` integration is a follow-up).
    func handleHarnessLaunch(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let harness: String
        let workingDirectory: String
        do {
            harness = try InputValidator.requireString("harness", from: arguments, tool: "harness_launch")
            workingDirectory = try InputValidator.requireString(
                "workingDirectory", from: arguments, tool: "harness_launch")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
        let prompt = InputValidator.optionalString("prompt", from: arguments)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = ["ynh", "run", harness]
        if let prompt, !prompt.isEmpty {
            args.append(contentsOf: ["--prompt", prompt])
        }
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let status = process.terminationStatus
            // Truncate excessive output so the MCP frame stays bounded.
            let snippet = output.count > 4096 ? String(output.suffix(4096)) : output
            let body: [String: Any] = [
                "ok": status == 0,
                "exitCode": status,
                "output": snippet,
            ]
            let json = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted])
            return CallTool.Result(
                content: [
                    .text(text: String(data: json, encoding: .utf8) ?? "{}", annotations: nil, _meta: nil)
                ],
                isError: status != 0)
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    func handleDeleteColumn(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let identifier: String
        do {
            identifier = try InputValidator.requireString(
                "identifier", from: arguments, tool: "delete_column")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
        let force = InputValidator.optionalBool("force", from: arguments)
        do {
            try BoardWriter.deleteColumn(
                identifier: identifier, force: force, dataDirectory: dataDirectory)
            return CallTool.Result(
                content: [
                    .text(
                        text: "{\"ok\": true, \"deleted\": \"\(identifier)\", \"force\": \(force)}",
                        annotations: nil, _meta: nil)
                ])
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }
}
