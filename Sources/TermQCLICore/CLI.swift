import AppKit
import ArgumentParser
import Foundation
import MCPServerLib
import TermQShared

// MARK: - Bundle Configuration

func termqBundleIdentifier() -> String {
    return AppProfile.Current.bundleIdentifier
}

func shouldUseDebugMode(_ explicitDebug: Bool) -> Bool {
    #if TERMQ_DEBUG_BUILD
        return true
    #else
        return explicitDebug
    #endif
}

/// Resolves the AppProfile variant for a CLI invocation: in a debug build always `.debug`;
/// in a production build the user's `--debug` flag selects between `.production` and `.debug`.
/// Use this at every `BoardLoader`/`BoardWriter`/`HeadlessWriter` call site so the long-form
/// `AppProfile.Variant(debug: shouldUseDebugMode(debug))` doesn't leak everywhere.
func resolveProfile(_ explicitDebug: Bool) -> AppProfile.Variant {
    AppProfile.Variant(debug: shouldUseDebugMode(explicitDebug))
}

// MARK: - Shared Helpers

func parseTags(_ tagStrings: [String]) -> [(key: String, value: String)] {
    tagStrings.compactMap { tagStr in
        let parts = tagStr.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}

// MARK: - CLI-specific Errors

enum CLIError: Error, LocalizedError {
    case boardNotFound(path: String)
    case columnNotFound(name: String)
    case terminalNotFound(identifier: String)

    var errorDescription: String? {
        switch self {
        case .boardNotFound(let path):
            return "Board file not found at: \(path). Is TermQ installed and has been run at least once?"
        case .columnNotFound(let name):
            return "Column not found: \(name)"
        case .terminalNotFound(let identifier):
            return "Terminal not found: \(identifier)"
        }
    }
}

// MARK: - CLI-specific Output Types (for Pending command)

struct PendingTerminal: Encodable {
    let id: String
    let name: String
    let column: String
    let path: String
    let llmNextAction: String
    let llmPrompt: String
    let staleness: String
    let tags: [String: String]
}

// MARK: - Main CLI

public struct TermQCLI: ParsableCommand {
    public init() {}
    public static let configuration = CommandConfiguration(
        commandName: "termqcli",
        abstract: "Command-line interface for TermQ - Terminal Queue Manager",
        discussion: """
            LLM/AI Assistants: Run 'termqcli pending' at session start, then \
            'termqcli context' for the complete cross-session workflow guide.
            """,
        version: "1.0.0",
        subcommands: [
            New.self, Open.self, Create.self, Launch.self, List.self, Find.self, Set.self, Move.self, Pending.self,
            Context.self, Delete.self,
        ]
    )
}

// MARK: - New Command (Quick Terminal Creation)

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Quick-create a new terminal at current directory",
        discussion: """
            Creates a new terminal in TermQ using the current working directory.
            Name defaults to the directory name. This is the fastest way to create
            a new terminal from any shell.

            Example: cd ~/projects/myapp && termqcli new
            """
    )

    @Option(name: [.short, .long], help: "Custom name (defaults to directory name)")
    var name: String?

    @Option(name: [.short, .long], help: "Column to place terminal in")
    var column: String?

    @Option(help: .hidden)
    var path: String?

    @Option(name: [.customLong("data-dir"), .customLong("data-directory")], help: .hidden)
    var dataDirectory: String?

    func run() throws {
        let cwd = path ?? FileManager.default.currentDirectoryPath
        let defaultName = URL(fileURLWithPath: cwd).lastPathComponent
        let cardName = name ?? defaultName
        let dataDirURL = dataDirectory.map { URL(fileURLWithPath: $0) }

        if GUIDetector.isGUIRunning() {
            try newViaGUI(name: cardName, column: column, workingDirectory: cwd)
        } else {
            do {
                let card = try HeadlessWriter.createCard(
                    HeadlessWriter.CardCreationOptions(
                        workingDirectory: cwd,
                        name: cardName,
                        column: column
                    ),
                    dataDirectory: dataDirURL
                )

                JSONHelper.printJSON(
                    CreateResponse(
                        id: card.id.uuidString,
                        name: card.title,
                        path: cwd,
                        column: column
                    ))
            } catch BoardWriter.WriteError.columnNotFound(let columnName) {
                JSONHelper.printErrorJSON("Column not found: \(columnName)")
                throw ExitCode.failure
            } catch {
                JSONHelper.printErrorJSON("Failed to create terminal: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Open Command

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open an existing terminal by name, ID, or path",
        discussion: "Finds and focuses an existing terminal in TermQ. Returns terminal details as JSON."
    )

    @Argument(help: "Terminal identifier (name, UUID, or path)")
    var terminal: String

    @Flag(name: .long, help: "Use debug data directory (TermQ-Debug)")
    var debug: Bool = false

    @Option(name: [.customLong("data-dir"), .customLong("data-directory")], help: .hidden)
    var dataDirectory: String?

    func run() throws {
        if !GUIDetector.isGUIRunning() {
            if !launchTermQ() {
                let appName = AppProfile.Current.appBundleName
                JSONHelper.printErrorJSON(
                    "The 'open' command requires TermQ GUI to be running."
                        + " Could not launch \(appName)."
                        + " Please ensure \(appName) is in /Applications or current directory"
                )
                throw ExitCode.failure
            }
            Thread.sleep(forTimeInterval: 1.0)
        }

        do {
            let dataDirURL = dataDirectory.map { URL(fileURLWithPath: $0) }
            let board = try BoardLoader.loadBoard(
                dataDirectory: dataDirURL, profile: resolveProfile(debug))

            guard let card = board.findTerminal(identifier: terminal) else {
                JSONHelper.printErrorJSON("Terminal not found: \(terminal)")
                throw ExitCode.failure
            }

            var components = URLComponents()
            components.scheme = AppProfile.Current.urlScheme
            components.host = "focus"
            components.queryItems = [
                URLQueryItem(name: "id", value: card.id.uuidString)
            ]

            guard let url = components.url else {
                JSONHelper.printErrorJSON("Failed to construct URL")
                throw ExitCode.failure
            }

            let workspace = NSWorkspace.shared
            let success = workspace.open(url)

            if success {
                let output = TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
                JSONHelper.printJSON(output)
            } else {
                JSONHelper.printErrorJSON("Failed to communicate with TermQ. Is it running?")
                throw ExitCode.failure
            }

        } catch BoardLoader.LoadError.boardNotFound(let path) {
            JSONHelper.printErrorJSON(
                "Board file not found at: \(path). Is TermQ installed and has been run at least once?"
            )
            throw ExitCode.failure
        } catch let error as ExitCode {
            throw error
        } catch {
            JSONHelper.printErrorJSON("Unexpected error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new terminal in TermQ",
        discussion: "Creates a new terminal at the specified or current directory."
    )

    @Option(name: [.short, .long], help: "Name/title for the terminal")
    var name: String?

    @Option(name: [.short, .long], help: "Description for the terminal")
    var description: String?

    @Option(name: [.short, .long], help: "Column to place the terminal in (e.g., 'To Do', 'In Progress')")
    var column: String?

    @Option(name: [.short, .long], parsing: .upToNextOption, help: "Tags in key=value format")
    var tag: [String] = []

    @Option(name: [.short, .long], help: "Working directory (defaults to current directory)")
    var path: String?

    @Option(name: [.customLong("data-dir"), .customLong("data-directory")], help: .hidden)
    var dataDirectory: String?

    func run() throws {
        let cwd = path ?? FileManager.default.currentDirectoryPath
        let dataDirURL = dataDirectory.map { URL(fileURLWithPath: $0) }

        if GUIDetector.isGUIRunning() {
            try createViaGUI(
                name: name,
                description: description,
                column: column,
                tags: tag,
                workingDirectory: cwd
            )
        } else {
            let parsedTags = parseTags(tag)
            let cardName = name ?? URL(fileURLWithPath: cwd).lastPathComponent

            do {
                let card = try HeadlessWriter.createCard(
                    HeadlessWriter.CardCreationOptions(
                        workingDirectory: cwd,
                        name: cardName,
                        column: column,
                        description: description,
                        tags: parsedTags.isEmpty ? nil : parsedTags
                    ),
                    dataDirectory: dataDirURL,
                    profile: resolveProfile(false)
                )

                JSONHelper.printJSON(
                    CreateResponse(
                        id: card.id.uuidString,
                        name: card.title,
                        path: cwd,
                        column: column
                    ))
            } catch BoardWriter.WriteError.columnNotFound(let columnName) {
                JSONHelper.printErrorJSON("Column not found: \(columnName)")
                throw ExitCode.failure
            } catch {
                JSONHelper.printErrorJSON("Failed to create terminal: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}

/// Helper to launch TermQ app
func launchTermQ() -> Bool {
    let appName = AppProfile.Current.appBundleName
    let possiblePaths = [
        "/Applications/\(appName)",
        "\(NSHomeDirectory())/Applications/\(appName)",
        "\(FileManager.default.currentDirectoryPath)/\(appName)",
    ]

    for appPath in possiblePaths where FileManager.default.fileExists(atPath: appPath) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appPath, "--wait-apps"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            Thread.sleep(forTimeInterval: 1.0)
            return true
        } catch {
            continue
        }
    }
    return false
}

struct Launch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Launch the TermQ application"
    )

    func run() throws {
        let appName = AppProfile.Current.appBundleName
        let possiblePaths = [
            "/Applications/\(appName)",
            "\(NSHomeDirectory())/Applications/\(appName)",
            "\(FileManager.default.currentDirectoryPath)/\(appName)",
        ]

        for appPath in possiblePaths where FileManager.default.fileExists(atPath: appPath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", appPath]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    print("Launched TermQ from: \(appPath)")
                    return
                }
            } catch {
                continue
            }
        }

        print("Error: Could not find \(appName)")
        print("Please ensure \(appName) is in /Applications or current directory")
        throw ExitCode.failure
    }
}

// MARK: - List Command

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all terminals in the board",
        discussion: "Outputs terminal information as JSON for LLM consumption."
    )

    @Flag(name: .long, help: "Use debug data directory (TermQ-Debug)")
    var debug: Bool = false

    @Option(name: .long, help: "Filter by column name (case-insensitive)")
    var column: String?

    @Flag(name: .long, help: "Include column information in output")
    var columns: Bool = false

    @Option(name: [.customLong("data-dir"), .customLong("data-directory")], help: .hidden)
    var dataDirectory: String?

    func run() throws {
        do {
            let dataDirURL = dataDirectory.map { URL(fileURLWithPath: $0) }
            let board = try BoardLoader.loadBoard(
                dataDirectory: dataDirURL, profile: resolveProfile(debug))

            if columns {
                let columnOutput = board.sortedColumns().map { col in
                    let count = board.activeCards.filter { $0.columnId == col.id }.count
                    return ColumnOutput(from: col, terminalCount: count)
                }
                JSONHelper.printJSON(columnOutput)
                return
            }

            var cards = board.activeCards

            if let columnFilter = column {
                let filterLower = columnFilter.lowercased()
                let matchingColumnIds = board.columns
                    .filter { $0.name.lowercased().contains(filterLower) }
                    .map { $0.id }
                cards = cards.filter { matchingColumnIds.contains($0.columnId) }
            }

            cards.sort { lhs, rhs in
                let lhsColOrder = board.columns.first { $0.id == lhs.columnId }?.orderIndex ?? 0
                let rhsColOrder = board.columns.first { $0.id == rhs.columnId }?.orderIndex ?? 0
                if lhsColOrder != rhsColOrder {
                    return lhsColOrder < rhsColOrder
                }
                return lhs.orderIndex < rhs.orderIndex
            }

            let output = cards.map { card in
                TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
            }

            JSONHelper.printJSON(output)

        } catch {
            JSONHelper.printErrorJSON(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}
