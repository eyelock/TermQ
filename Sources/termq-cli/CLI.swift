import AppKit
import ArgumentParser
import Foundation

// MARK: - Data Structures for Reading Board

/// Minimal Tag representation for CLI
struct CLITag: Codable {
    let id: UUID
    let key: String
    let value: String
}

/// Minimal Column representation for CLI
struct CLIColumn: Codable {
    let id: UUID
    let name: String
    let orderIndex: Int
    let color: String
}

/// Minimal TerminalCard representation for CLI
struct CLICard: Codable {
    let id: UUID
    let title: String
    let description: String
    let tags: [CLITag]
    let columnId: UUID
    let orderIndex: Int
    let workingDirectory: String
    let isFavourite: Bool
    let badge: String
    let llmPrompt: String
    let deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }
}

/// Minimal Board representation for CLI
struct CLIBoard: Codable {
    let columns: [CLIColumn]
    let cards: [CLICard]

    var activeCards: [CLICard] {
        cards.filter { !$0.isDeleted }
    }
}

/// JSON output format for terminals
struct TerminalOutput: Encodable {
    let id: String
    let name: String
    let description: String
    let column: String
    let columnId: String
    let tags: [String: String]
    let path: String
    let badges: [String]
    let isFavourite: Bool
    let llmPrompt: String
}

/// Error output format
struct ErrorOutput: Encodable {
    let error: String
    let code: Int
}

/// Success response for set command
struct SetResponse: Encodable {
    let success: Bool
    let id: String
}

/// Success response for move command
struct MoveResponse: Encodable {
    let success: Bool
    let id: String
    let column: String
}

// MARK: - Shared Helpers

/// Get the TermQ data directory path
func getDataDirectoryPath(debug: Bool) -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dirName = debug ? "TermQ-Debug" : "TermQ"
    return appSupport.appendingPathComponent(dirName, isDirectory: true)
}

/// Load the board from disk
func loadBoard(debug: Bool) throws -> CLIBoard {
    let dataDir = getDataDirectoryPath(debug: debug)
    let boardURL = dataDir.appendingPathComponent("board.json")

    guard FileManager.default.fileExists(atPath: boardURL.path) else {
        throw CLIError.boardNotFound(path: boardURL.path)
    }

    let data = try Data(contentsOf: boardURL)
    return try JSONDecoder().decode(CLIBoard.self, from: data)
}

/// Convert a card to output format
func cardToOutput(_ card: CLICard, columnName: String) -> TerminalOutput {
    var tagsDict: [String: String] = [:]
    for tag in card.tags {
        tagsDict[tag.key] = tag.value
    }

    let badges =
        card.badge.isEmpty
        ? []
        : card.badge.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

    return TerminalOutput(
        id: card.id.uuidString,
        name: card.title,
        description: card.description,
        column: columnName,
        columnId: card.columnId.uuidString,
        tags: tagsDict,
        path: card.workingDirectory,
        badges: badges,
        isFavourite: card.isFavourite,
        llmPrompt: card.llmPrompt
    )
}

/// Print JSON output
func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value),
        let string = String(data: data, encoding: .utf8)
    {
        print(string)
    }
}

/// Print error as JSON
func printErrorJSON(_ message: String, code: Int = 1) {
    printJSON(ErrorOutput(error: message, code: code))
}

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

@main
struct TermQCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "termq",
        abstract: "Command-line interface for TermQ - Terminal Queue Manager",
        version: "1.0.0",
        subcommands: [Open.self, Launch.self, List.self, Find.self, Set.self, Move.self],
        defaultSubcommand: Open.self
    )
}

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open a new terminal in TermQ at the current directory"
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

    func run() throws {
        let cwd = path ?? FileManager.default.currentDirectoryPath

        // Build URL with parameters
        var components = URLComponents()
        components.scheme = "termq"
        components.host = "open"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "path", value: cwd)
        ]

        if let name = name {
            queryItems.append(URLQueryItem(name: "name", value: name))
        }

        if let description = description {
            queryItems.append(URLQueryItem(name: "description", value: description))
        }

        if let column = column {
            queryItems.append(URLQueryItem(name: "column", value: column))
        }

        for tagStr in tag {
            queryItems.append(URLQueryItem(name: "tag", value: tagStr))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            print("Error: Failed to construct URL")
            throw ExitCode.failure
        }

        // First, ensure TermQ is running
        let workspace = NSWorkspace.shared
        let bundleId = "com.termq.app"

        // Check if TermQ is running
        let runningApps = workspace.runningApplications.filter { $0.bundleIdentifier == bundleId }

        if runningApps.isEmpty {
            // Try to launch TermQ using 'open' command (avoids semaphore deadlock)
            print("TermQ is not running. Launching...")

            // Try common locations
            let possiblePaths = [
                "/Applications/TermQ.app",
                "\(NSHomeDirectory())/Applications/TermQ.app",
                "\(FileManager.default.currentDirectoryPath)/TermQ.app",
                // Also check the build directory relative to the CLI
                URL(fileURLWithPath: #file)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("TermQ.app")
                    .path,
            ]

            var launched = false
            for appPath in possiblePaths {
                if FileManager.default.fileExists(atPath: appPath) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    process.arguments = ["-a", appPath, "--wait-apps"]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice

                    do {
                        try process.run()
                        // Wait briefly for app to initialize
                        Thread.sleep(forTimeInterval: 1.0)
                        launched = true
                        break
                    } catch {
                        continue
                    }
                }
            }

            if !launched {
                print("Error: Could not find or launch TermQ.app")
                print("Please ensure TermQ.app is in /Applications or current directory")
                throw ExitCode.failure
            }
        }

        // Open the URL
        let success = workspace.open(url)

        if success {
            print("Opening terminal in TermQ: \(cwd)")
            if let name = name {
                print("  Name: \(name)")
            }
            if let description = description {
                print("  Description: \(description)")
            }
            if let column = column {
                print("  Column: \(column)")
            }
        } else {
            print("Error: Failed to communicate with TermQ")
            print("Make sure TermQ is running")
            throw ExitCode.failure
        }
    }
}

struct Launch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Launch the TermQ application"
    )

    func run() throws {
        let possiblePaths = [
            "/Applications/TermQ.app",
            "\(NSHomeDirectory())/Applications/TermQ.app",
            "\(FileManager.default.currentDirectoryPath)/TermQ.app",
        ]

        for appPath in possiblePaths {
            if FileManager.default.fileExists(atPath: appPath) {
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
        }

        print("Error: Could not find TermQ.app")
        print("Please ensure TermQ.app is in /Applications or current directory")
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

    func run() throws {
        do {
            let board = try loadBoard(debug: debug)

            // Build column lookup
            var columnLookup: [UUID: String] = [:]
            for col in board.columns {
                columnLookup[col.id] = col.name
            }

            // If --columns flag, output column info
            if columns {
                let columnOutput = board.columns.sorted { $0.orderIndex < $1.orderIndex }.map { col in
                    [
                        "id": col.id.uuidString,
                        "name": col.name,
                        "color": col.color,
                    ]
                }
                printJSON(columnOutput)
                return
            }

            // Filter cards
            var cards = board.activeCards

            if let columnFilter = column {
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

            // Convert to output format
            let output = cards.map { card in
                cardToOutput(card, columnName: columnLookup[card.columnId] ?? "Unknown")
            }

            printJSON(output)

        } catch {
            printErrorJSON(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

// MARK: - Find Command

struct Find: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find terminals by various criteria",
        discussion: "Search for terminals by name, column, tag, or ID. Returns matching terminals as JSON."
    )

    @Flag(name: .long, help: "Use debug data directory (TermQ-Debug)")
    var debug: Bool = false

    @Option(name: .long, help: "Search by name (case-insensitive partial match)")
    var name: String?

    @Option(name: .long, help: "Filter by column name (case-insensitive)")
    var column: String?

    @Option(name: .long, help: "Filter by tag (format: key or key=value)")
    var tag: String?

    @Option(name: .long, help: "Find by exact terminal ID (UUID)")
    var id: String?

    @Option(name: .long, help: "Filter by badge (case-insensitive partial match)")
    var badge: String?

    @Flag(name: .long, help: "Only show favourites")
    var favourites: Bool = false

    func run() throws {
        do {
            let board = try loadBoard(debug: debug)

            // Build column lookup
            var columnLookup: [UUID: String] = [:]
            for col in board.columns {
                columnLookup[col.id] = col.name
            }

            var cards = board.activeCards

            // Filter by ID (exact match)
            if let idFilter = id {
                if let uuid = UUID(uuidString: idFilter) {
                    cards = cards.filter { $0.id == uuid }
                } else {
                    // Invalid UUID format
                    printJSON([TerminalOutput]())
                    return
                }
            }

            // Filter by name (case-insensitive partial match)
            if let nameFilter = name {
                let filterLower = nameFilter.lowercased()
                cards = cards.filter { $0.title.lowercased().contains(filterLower) }
            }

            // Filter by column
            if let columnFilter = column {
                let filterLower = columnFilter.lowercased()
                let matchingColumnIds = board.columns
                    .filter { $0.name.lowercased().contains(filterLower) }
                    .map { $0.id }
                cards = cards.filter { matchingColumnIds.contains($0.columnId) }
            }

            // Filter by tag
            if let tagFilter = tag {
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
            if let badgeFilter = badge {
                let filterLower = badgeFilter.lowercased()
                cards = cards.filter { card in
                    card.badge.lowercased().contains(filterLower)
                }
            }

            // Filter by favourites
            if favourites {
                cards = cards.filter { $0.isFavourite }
            }

            // Convert to output format
            let output = cards.map { card in
                cardToOutput(card, columnName: columnLookup[card.columnId] ?? "Unknown")
            }

            printJSON(output)

        } catch {
            printErrorJSON(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

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

    @Option(name: .long, help: "Set LLM prompt/context for this terminal")
    var llmPrompt: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Add tags in key=value format")
    var tag: [String] = []

    @Flag(name: .long, help: "Mark as favourite")
    var favourite: Bool = false

    @Flag(name: .long, help: "Remove favourite status")
    var unfavourite: Bool = false

    func run() throws {
        // First, resolve the terminal identifier to a UUID
        do {
            let board = try loadBoard(debug: debug)

            var targetCard: CLICard?

            // Try as UUID first
            if let uuid = UUID(uuidString: terminal) {
                targetCard = board.activeCards.first { $0.id == uuid }
            }

            // Try as name (case-insensitive)
            if targetCard == nil {
                let terminalLower = terminal.lowercased()
                targetCard = board.activeCards.first { $0.title.lowercased() == terminalLower }
            }

            guard let card = targetCard else {
                printErrorJSON("Terminal not found: \(terminal)")
                throw ExitCode.failure
            }

            // Build URL for update
            var components = URLComponents()
            components.scheme = "termq"
            components.host = "update"

            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "id", value: card.id.uuidString)
            ]

            if let name = name {
                queryItems.append(URLQueryItem(name: "name", value: name))
            }

            if let desc = setDescription {
                queryItems.append(URLQueryItem(name: "description", value: desc))
            }

            if let column = column {
                queryItems.append(URLQueryItem(name: "column", value: column))
            }

            if let badge = badge {
                queryItems.append(URLQueryItem(name: "badge", value: badge))
            }

            if let llmPrompt = llmPrompt {
                queryItems.append(URLQueryItem(name: "llmPrompt", value: llmPrompt))
            }

            for tagStr in tag {
                queryItems.append(URLQueryItem(name: "tag", value: tagStr))
            }

            if favourite {
                queryItems.append(URLQueryItem(name: "favourite", value: "true"))
            }

            if unfavourite {
                queryItems.append(URLQueryItem(name: "favourite", value: "false"))
            }

            components.queryItems = queryItems

            guard let url = components.url else {
                printErrorJSON("Failed to construct URL")
                throw ExitCode.failure
            }

            // Open the URL scheme
            let workspace = NSWorkspace.shared
            let success = workspace.open(url)

            if success {
                printJSON(SetResponse(success: true, id: card.id.uuidString))
            } else {
                printErrorJSON("Failed to send update to TermQ. Is it running?")
                throw ExitCode.failure
            }

        } catch let error as CLIError {
            printErrorJSON(error.localizedDescription)
            throw ExitCode.failure
        } catch let error as ExitCode {
            throw error
        } catch {
            printErrorJSON("Unexpected error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

// MARK: - Move Command

struct Move: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Move a terminal to a different column",
        discussion: "Move a terminal between columns via URL scheme."
    )

    @Argument(help: "Terminal identifier (UUID or name)")
    var terminal: String

    @Argument(help: "Target column name")
    var toColumn: String

    @Flag(name: .long, help: "Use debug data directory (TermQ-Debug)")
    var debug: Bool = false

    func run() throws {
        do {
            let board = try loadBoard(debug: debug)

            var targetCard: CLICard?

            // Try as UUID first
            if let uuid = UUID(uuidString: terminal) {
                targetCard = board.activeCards.first { $0.id == uuid }
            }

            // Try as name (case-insensitive)
            if targetCard == nil {
                let terminalLower = terminal.lowercased()
                targetCard = board.activeCards.first { $0.title.lowercased() == terminalLower }
            }

            guard let card = targetCard else {
                printErrorJSON("Terminal not found: \(terminal)")
                throw ExitCode.failure
            }

            // Build URL for move
            var components = URLComponents()
            components.scheme = "termq"
            components.host = "move"

            components.queryItems = [
                URLQueryItem(name: "id", value: card.id.uuidString),
                URLQueryItem(name: "column", value: toColumn),
            ]

            guard let url = components.url else {
                printErrorJSON("Failed to construct URL")
                throw ExitCode.failure
            }

            // Open the URL scheme
            let workspace = NSWorkspace.shared
            let success = workspace.open(url)

            if success {
                printJSON(MoveResponse(success: true, id: card.id.uuidString, column: toColumn))
            } else {
                printErrorJSON("Failed to send move command to TermQ. Is it running?")
                throw ExitCode.failure
            }

        } catch let error as CLIError {
            printErrorJSON(error.localizedDescription)
            throw ExitCode.failure
        } catch let error as ExitCode {
            throw error
        } catch {
            printErrorJSON("Unexpected error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
