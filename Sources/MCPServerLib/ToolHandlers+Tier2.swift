import Foundation
import MCP
import TermQShared

// MARK: - Tier 2 handlers (whoami / restore / column CRUD)

extension TermQMCPServer {
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
                identifier: identifier, dataDirectory: dataDirectory, boardFilename: boardFilename)
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
                name: name, description: description, color: color,
                dataDirectory: dataDirectory, boardFilename: boardFilename)
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
                identifier: identifier, newName: newName,
                dataDirectory: dataDirectory, boardFilename: boardFilename)
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
                identifier: identifier, force: force,
                dataDirectory: dataDirectory, boardFilename: boardFilename)
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
