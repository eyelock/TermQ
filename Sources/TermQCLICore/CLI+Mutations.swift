import ArgumentParser
import Foundation
import MCPServerLib
import TermQShared

// MARK: - Set Command

struct Set: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Modify terminal properties",
        discussion: "Update a terminal's name, description, column, or tags via URL scheme."
    )

    @Argument(help: "Terminal identifier (UUID or name)")
    var terminal: String

    @Flag(name: .long, help: "Use debug data directory (TermQ-Debug)")
    var debug: Bool = false

    @Option(name: .long, help: "Set terminal name")
    var name: String?

    @Option(name: .long, help: "Set terminal description")
    var setDescription: String?

    @Option(name: .long, help: "Move to column (by name)")
    var column: String?

    @Option(name: .long, help: "Set badge text")
    var badge: String?

    @Option(name: .long, help: "Set persistent LLM context for this terminal")
    var llmPrompt: String?

    @Option(name: .long, help: "Set one-time LLM action (runs on next open, then clears)")
    var llmNextAction: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Add tags in key=value format")
    var tag: [String] = []

    @Flag(name: .long, help: "Replace all tags instead of adding (use with --tag)")
    var replaceTags: Bool = false

    @Option(name: .long, help: "Set command to run when terminal opens")
    var initCommand: String?

    @Flag(name: .long, help: "Mark as favourite")
    var favourite: Bool = false

    @Flag(name: .long, help: "Remove favourite status")
    var unfavourite: Bool = false

    @Option(help: .hidden)
    var dataDirectory: String?

    func run() throws {
        do {
            let debugMode = shouldUseDebugMode(debug)
            let dataDirURL = dataDirectory.map { URL(fileURLWithPath: $0) }
            let board = try BoardLoader.loadBoard(dataDirectory: dataDirURL, debug: debugMode)

            guard let card = board.findTerminal(identifier: terminal) else {
                JSONHelper.printErrorJSON("Terminal not found: \(terminal)")
                throw ExitCode.failure
            }

            if GUIDetector.isGUIRunning() {
                try setViaGUI(
                    SetOptions(
                        cardId: card.id,
                        name: name,
                        description: setDescription,
                        column: column,
                        badge: badge,
                        llmPrompt: llmPrompt,
                        llmNextAction: llmNextAction,
                        tags: tag,
                        replaceTags: replaceTags,
                        initCommand: initCommand,
                        favourite: favourite,
                        unfavourite: unfavourite
                    ))
            } else {
                let parsedTags = parseTags(tag)
                let favouriteValue: Bool? = favourite ? true : (unfavourite ? false : nil)

                let params = HeadlessWriter.UpdateParameters(
                    name: name,
                    description: setDescription,
                    badge: badge,
                    llmPrompt: llmPrompt,
                    llmNextAction: llmNextAction,
                    favourite: favouriteValue,
                    tags: parsedTags.isEmpty ? nil : parsedTags,
                    replaceTags: replaceTags
                )

                if let columnName = column {
                    _ = try HeadlessWriter.moveCard(
                        identifier: card.id.uuidString,
                        toColumn: columnName,
                        dataDirectory: dataDirURL,
                        debug: debugMode
                    )
                }

                _ = try HeadlessWriter.updateCard(
                    identifier: card.id.uuidString,
                    params: params,
                    dataDirectory: dataDirURL,
                    debug: debugMode
                )

                if initCommand != nil {
                    JSONHelper.printErrorJSON(
                        "Warning: initCommand is only supported when TermQ GUI is running. Value ignored in headless mode."
                    )
                }

                JSONHelper.printJSON(SetResponse(success: true, id: card.id.uuidString))
            }
        } catch BoardLoader.LoadError.boardNotFound(let path) {
            JSONHelper.printErrorJSON(
                "Board file not found at: \(path). Is TermQ installed and has been run at least once?"
            )
            throw ExitCode.failure
        } catch BoardWriter.WriteError.cardNotFound(let identifier) {
            JSONHelper.printErrorJSON("Terminal not found: \(identifier)")
            throw ExitCode.failure
        } catch BoardWriter.WriteError.columnNotFound(let name) {
            JSONHelper.printErrorJSON("Column not found: \(name)")
            throw ExitCode.failure
        } catch let error as ExitCode {
            throw error
        } catch {
            JSONHelper.printErrorJSON("Unexpected error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

// MARK: - Move Command

struct Move: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Move a terminal to a different column"
    )

    @Argument(help: "Terminal identifier (UUID or name)")
    var terminal: String

    @Argument(help: "Target column name")
    var toColumn: String

    @Flag(name: .long, help: "Use debug data directory (TermQ-Debug)")
    var debug: Bool = false

    @Option(help: .hidden)
    var dataDirectory: String?

    func run() throws {
        do {
            let debugMode = shouldUseDebugMode(debug)
            let dataDirURL = dataDirectory.map { URL(fileURLWithPath: $0) }
            let board = try BoardLoader.loadBoard(dataDirectory: dataDirURL, debug: debugMode)

            guard let card = board.findTerminal(identifier: terminal) else {
                JSONHelper.printErrorJSON("Terminal not found: \(terminal)")
                throw ExitCode.failure
            }

            if GUIDetector.isGUIRunning() {
                try moveViaGUI(cardId: card.id, toColumn: toColumn)
            } else {
                _ = try HeadlessWriter.moveCard(
                    identifier: card.id.uuidString,
                    toColumn: toColumn,
                    dataDirectory: dataDirURL,
                    debug: debugMode
                )

                JSONHelper.printJSON(
                    MoveResponse(
                        success: true,
                        id: card.id.uuidString,
                        column: toColumn
                    ))
            }

        } catch BoardLoader.LoadError.boardNotFound(let path) {
            JSONHelper.printErrorJSON(
                "Board file not found at: \(path). Is TermQ installed and has been run at least once?")
            throw ExitCode.failure
        } catch BoardWriter.WriteError.cardNotFound(let identifier) {
            JSONHelper.printErrorJSON("Terminal not found: \(identifier)")
            throw ExitCode.failure
        } catch BoardWriter.WriteError.columnNotFound(let name) {
            JSONHelper.printErrorJSON("Column not found: \(name)")
            throw ExitCode.failure
        } catch let error as ExitCode {
            throw error
        } catch {
            JSONHelper.printErrorJSON("Unexpected error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

// MARK: - Delete Command

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete a terminal",
        discussion: "Moves terminal to bin (soft delete). Use --permanent to skip bin."
    )

    @Argument(help: "Terminal identifier (UUID or name)")
    var terminal: String

    @Flag(name: .long, help: "Use debug data directory (TermQ-Debug)")
    var debug: Bool = false

    @Flag(name: .long, help: "Permanently delete (skip bin, cannot be recovered)")
    var permanent: Bool = false

    @Option(help: .hidden)
    var dataDirectory: String?

    func run() throws {
        do {
            let debugMode = shouldUseDebugMode(debug)
            let dataDirURL = dataDirectory.map { URL(fileURLWithPath: $0) }
            let board = try BoardLoader.loadBoard(dataDirectory: dataDirURL, debug: debugMode)

            guard let card = board.findTerminal(identifier: terminal) else {
                JSONHelper.printErrorJSON("Terminal not found: \(terminal)")
                throw ExitCode.failure
            }

            if GUIDetector.isGUIRunning() {
                try deleteViaGUI(cardId: card.id, permanent: permanent)
            } else {
                try HeadlessWriter.deleteCard(
                    identifier: card.id.uuidString,
                    permanent: permanent,
                    dataDirectory: dataDirURL,
                    debug: debugMode
                )

                JSONHelper.printJSON(
                    DeleteResponse(
                        id: card.id.uuidString,
                        permanent: permanent
                    ))
            }

        } catch BoardLoader.LoadError.boardNotFound(let path) {
            JSONHelper.printErrorJSON(
                "Board file not found at: \(path). Is TermQ installed and has been run at least once?")
            throw ExitCode.failure
        } catch BoardWriter.WriteError.cardNotFound(let identifier) {
            JSONHelper.printErrorJSON("Terminal not found: \(identifier)")
            throw ExitCode.failure
        } catch let error as ExitCode {
            throw error
        } catch {
            JSONHelper.printErrorJSON("Unexpected error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
