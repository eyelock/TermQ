import Foundation
import MCP
import TermQShared

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
        case "termq_get":
            return try await handleGet(params.arguments)
        case "termq_delete":
            return try await handleDelete(params.arguments)
        default:
            throw MCPError.invalidRequest("Unknown tool: \(params.name)")
        }
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
        let columnFilter = InputValidator.optionalString("column", from: arguments)
        let columnsOnly = InputValidator.optionalBool("columnsOnly", from: arguments)

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
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }

        do {
            let board = try loadBoard()
            var cards = board.activeCards
            var relevanceScores: [UUID: Int] = [:]

            // Smart query search (multi-word, multi-field)
            if let query = query, !query.isEmpty {
                let queryWords = normalizeToWords(query)
                guard !queryWords.isEmpty else {
                    let json = try JSONHelper.encode([TerminalOutput]())
                    return CallTool.Result(content: [.text(json)])
                }

                cards = cards.filter { card in
                    let score = calculateRelevanceScore(card: card, queryWords: queryWords)
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

            // Sort by relevance if query was used, otherwise maintain default order
            if !relevanceScores.isEmpty {
                cards.sort { card1, card2 in
                    let score1 = relevanceScores[card1.id] ?? 0
                    let score2 = relevanceScores[card2.id] ?? 0
                    return score1 > score2
                }
            }

            let output = cards.map { TerminalOutput(from: $0, columnName: board.columnName(for: $0.columnId)) }
            let json = try JSONHelper.encode(output)
            return CallTool.Result(content: [.text(json)])

        } catch {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    // MARK: - Smart Search Helpers

    /// Normalize text to searchable words (lowercase, remove punctuation, split on separators)
    private func normalizeToWords(_ text: String) -> Set<String> {
        // Replace common separators with spaces
        let normalized =
            text
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ".", with: " ")

        // Split into words and filter out empty/short words
        let words =
            normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }

        return Set(words)
    }

    /// Calculate relevance score for a card based on query words
    private func calculateRelevanceScore(card: Card, queryWords: Set<String>) -> Int {
        var score = 0

        // Get searchable words from card fields
        let titleWords = normalizeToWords(card.title)
        let descriptionWords = normalizeToWords(card.description)
        let pathWords = normalizeToWords(card.workingDirectory)
        var tagWords = Set<String>()
        for tag in card.tags {
            tagWords.formUnion(normalizeToWords(tag.key))
            tagWords.formUnion(normalizeToWords(tag.value))
        }

        // Score each query word
        for queryWord in queryWords {
            // Exact word matches (higher score)
            if titleWords.contains(queryWord) { score += 10 }
            if descriptionWords.contains(queryWord) { score += 5 }
            if pathWords.contains(queryWord) { score += 3 }
            if tagWords.contains(queryWord) { score += 7 }

            // Prefix matches (lower score but still useful)
            if titleWords.contains(where: { $0.hasPrefix(queryWord) || queryWord.hasPrefix($0) }) { score += 4 }
            if descriptionWords.contains(where: { $0.hasPrefix(queryWord) || queryWord.hasPrefix($0) }) { score += 2 }
            if pathWords.contains(where: { $0.hasPrefix(queryWord) || queryWord.hasPrefix($0) }) { score += 1 }
            if tagWords.contains(where: { $0.hasPrefix(queryWord) || queryWord.hasPrefix($0) }) { score += 3 }
        }

        return score
    }

    func handleOpen(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let identifier: String
        do {
            identifier = try InputValidator.requireNonEmptyString("identifier", from: arguments, tool: "termq_open")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
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

    func handleGet(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let id: String
        do {
            let uuid = try InputValidator.requireUUID("id", from: arguments, tool: "termq_get")
            id = uuid.uuidString
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
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
                    content: [.text("Error: Terminal not found with ID: \(id)")],
                    isError: true
                )
            }

            let output = TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
            let json = try JSONHelper.encode(output)
            return CallTool.Result(content: [.text(json)])

        } catch {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    func handleCreate(_ arguments: [String: Value]?) async throws -> CallTool.Result {
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

        // Validate path if provided (don't require existence - user can create terminals pointing anywhere)
        let path: String
        do {
            if let providedPath = try InputValidator.optionalPath("path", from: arguments, mustExist: false) {
                path = providedPath
            } else {
                path = FileManager.default.currentDirectoryPath
            }
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }

        // Generate card ID upfront so we can return it
        let cardId = UUID()

        // Build and open the URL to create the terminal via GUI
        let urlString = URLOpener.buildOpenURL(
            params: URLOpener.OpenURLParams(
                cardId: cardId,
                path: path,
                name: name,
                description: description,
                column: column,
                tags: tags,
                llmPrompt: llmPrompt,
                llmNextAction: llmNextAction,
                initCommand: initCommand
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
                    let json = try JSONHelper.encode(output)
                    return CallTool.Result(content: [.text(json)])
                }
            }

            // Card not found after retries - GUI might still be processing or not running
            // Return the ID anyway so the LLM can use it
            let pendingOutput = PendingCreateResponse(
                id: cardId.uuidString,
                message: "Terminal creation requested. The terminal may take a moment to appear in TermQ."
            )
            let json = try JSONHelper.encode(pendingOutput)
            return CallTool.Result(content: [.text(json)])
        } catch {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    func handleSet(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let identifier: String
        do {
            identifier = try InputValidator.requireNonEmptyString("identifier", from: arguments, tool: "termq_set")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }

        // First, find the card to get its UUID
        let board = try loadBoard()
        guard let card = board.findTerminal(identifier: identifier) else {
            return CallTool.Result(content: [.text("Error: Terminal not found: \(identifier)")], isError: true)
        }

        // Parse tags if provided
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

        let replaceTags = InputValidator.optionalBool("replaceTags", from: arguments)

        // Build and open the URL to update the terminal via GUI
        let urlString = URLOpener.buildUpdateURL(
            params: URLOpener.UpdateURLParams(
                cardId: card.id,
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
                let json = try JSONHelper.encode(output)
                return CallTool.Result(content: [.text(json)])
            } else {
                return CallTool.Result(content: [.text("Error: Terminal not found after update")], isError: true)
            }
        } catch {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    func handleMove(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let identifier: String
        let column: String
        do {
            identifier = try InputValidator.requireNonEmptyString("identifier", from: arguments, tool: "termq_move")
            column = try InputValidator.requireNonEmptyString("column", from: arguments, tool: "termq_move")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }

        // First, find the card to get its UUID
        let board = try loadBoard()
        guard let card = board.findTerminal(identifier: identifier) else {
            return CallTool.Result(content: [.text("Error: Terminal not found: \(identifier)")], isError: true)
        }

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
                let json = try JSONHelper.encode(output)
                return CallTool.Result(content: [.text(json)])
            } else {
                return CallTool.Result(content: [.text("Error: Terminal not found after move")], isError: true)
            }
        } catch {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    func handleDelete(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let identifier: String
        do {
            identifier = try InputValidator.requireNonEmptyString("identifier", from: arguments, tool: "termq_delete")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }

        let permanent = InputValidator.optionalBool("permanent", from: arguments)

        // First, find the card to get its UUID
        let board = try loadBoard()
        guard let card = board.findTerminal(identifier: identifier) else {
            return CallTool.Result(content: [.text("Error: Terminal not found: \(identifier)")], isError: true)
        }

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
            let json = try JSONHelper.encode(result)
            return CallTool.Result(content: [.text(json)])
        } catch {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }
}
