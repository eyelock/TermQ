import Foundation
import MCP
import TermQShared

// MARK: - Card Mutation Handlers

// `set`, `move` and `delete` each carry two implementations: one that asks the running app to make
// the change over the URL scheme, and one that writes board.json directly. They live here rather
// than beside their tool entry points so ToolHandlers.swift stays within its length budget.

extension TermQMCPServer {

    // MARK: - Helper Types

    /// Parameters for updating a terminal card
    struct SetParameters {
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

    // MARK: - GUI Result Builders

    /// Reject an unknown column with the same wording the headless writer uses, plus the names
    /// that would have worked — the caller is usually holding a stale copy of the board.
    func columnNotFoundResult(_ name: String, in board: Board) -> CallTool.Result {
        let available = GUIConfirmation.columnNames(in: board).joined(separator: ", ")
        return CallTool.Result(
            content: [
                .text(
                    text: "Error: Column not found: \(name). Available columns: \(available)",
                    annotations: nil, _meta: nil)
            ],
            isError: true)
    }

    /// Report a GUI-routed mutation that never showed up on the board.
    ///
    /// This is an error rather than a success: the board write behind these commands is
    /// synchronous, so a change still missing after the full retry budget was not applied.
    /// Reporting it as success is what let a dropped command look like a completed one.
    func unconfirmedResult(action: String, hint: String? = nil) -> CallTool.Result {
        var message =
            "Error: TermQ accepted the \(action) request but the board never changed,"
            + " so the command was not applied."
        if let hint {
            message += " \(hint)"
        }
        return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }

    func handleSetViaGUI(card: Card, params: SetParameters) async throws -> CallTool.Result {
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
            let requestedTags = params.tags?.map { Tag(key: $0.key, value: $0.value) }
            let expected = GUIConfirmation.ExpectedUpdate(
                title: params.name,
                description: params.description,
                badge: params.badge,
                llmPrompt: params.llmPrompt,
                llmNextAction: params.llmNextAction,
                isFavourite: params.favourite,
                column: params.column,
                requiredTags: params.replaceTags ? nil : requestedTags,
                exactTags: params.replaceTags ? (requestedTags ?? []) : nil
            )

            let confirmed = await URLOpener.waitForCondition {
                let board = try BoardLoader.loadBoard(dataDirectory: dataDir, boardFilename: boardFilename)
                // `initCommand` is the one field `set` accepts that never reaches board.json, so a
                // request carrying only that can be confirmed no further than the card surviving.
                guard expected.hasObservableFields else {
                    return !GUIConfirmation.cardIsAbsent(board, cardId: cardIdStr)
                }
                return GUIConfirmation.cardMatches(board, cardId: cardIdStr, expected: expected)
            }

            guard confirmed else {
                let touchesLLMFields = params.llmPrompt != nil || params.llmNextAction != nil
                return unconfirmedResult(
                    action: "update",
                    hint: touchesLLMFields
                        ? "TermQ can be set to confirm external LLM changes — a prompt may still be open."
                        : nil)
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

    func handleSetHeadless(identifier: String, params: SetParameters) async throws -> CallTool.Result {
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
                dataDirectory: dataDirectory,
                boardFilename: boardFilename
            )

            // `set` with a `column` argument is equivalent to a move — apply it
            // after the field updates so a rename + column change in one call both land.
            if let column = params.column {
                card = try HeadlessWriter.moveCard(
                    identifier: card.id.uuidString,
                    toColumn: column,
                    dataDirectory: dataDirectory,
                    boardFilename: boardFilename
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

    func handleMoveViaGUI(card: Card, column: String) async throws -> CallTool.Result {
        // Build and open the URL to move the terminal via GUI
        let urlString = URLOpener.buildMoveURL(cardId: card.id, column: column)

        do {
            try await URLOpener.open(urlString)

            // Wait for GUI to process with retry and exponential backoff
            let dataDir = dataDirectory
            let cardIdStr = card.id.uuidString
            let confirmed = await URLOpener.waitForCondition {
                // Verify the card moved to the target column
                let board = try BoardLoader.loadBoard(dataDirectory: dataDir, boardFilename: boardFilename)
                return GUIConfirmation.cardIsInColumn(board, cardId: cardIdStr, column: column)
            }

            guard confirmed else {
                return unconfirmedResult(action: "move")
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

    func handleMoveHeadless(identifier: String, column: String) async throws -> CallTool.Result {
        do {
            let card = try HeadlessWriter.moveCard(
                identifier: identifier,
                toColumn: column,
                dataDirectory: dataDirectory,
                boardFilename: boardFilename
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

    func handleDeleteViaGUI(card: Card, permanent: Bool) async throws -> CallTool.Result {
        // Build and open the URL to delete the terminal via GUI
        let urlString = URLOpener.buildDeleteURL(cardId: card.id, permanent: permanent)

        do {
            try await URLOpener.open(urlString)

            // Wait for GUI to process with retry and exponential backoff
            let dataDir = dataDirectory
            let cardIdStr = card.id.uuidString
            let confirmed = await URLOpener.waitForCondition {
                // Verify the card is no longer in active cards (deleted or in bin)
                let board = try BoardLoader.loadBoard(dataDirectory: dataDir, boardFilename: boardFilename)
                return GUIConfirmation.cardIsAbsent(board, cardId: cardIdStr)
            }

            guard confirmed else {
                return unconfirmedResult(action: "delete")
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

    func handleDeleteHeadless(identifier: String, permanent: Bool) async throws -> CallTool.Result {
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
                dataDirectory: dataDirectory,
                boardFilename: boardFilename
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
}
