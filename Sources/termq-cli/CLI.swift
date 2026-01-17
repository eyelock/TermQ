import AppKit
import ArgumentParser
import Foundation
import TermQShared

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

/// Pending terminal output format (CLI-specific, includes slightly different fields)
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

@main
struct TermQCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
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

    func run() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let defaultName = URL(fileURLWithPath: cwd).lastPathComponent

        // Build URL with parameters
        var components = URLComponents()
        components.scheme = "termq"
        components.host = "open"

        // Generate a card ID upfront so we can track it
        let cardId = UUID()

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "id", value: cardId.uuidString),
            URLQueryItem(name: "path", value: cwd),
            URLQueryItem(name: "name", value: name ?? defaultName),
        ]

        if let column = column {
            queryItems.append(URLQueryItem(name: "column", value: column))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            print("Error: Failed to construct URL")
            throw ExitCode.failure
        }

        // Ensure TermQ is running
        let workspace = NSWorkspace.shared
        let bundleId = "com.termq.app"
        let runningApps = workspace.runningApplications.filter { $0.bundleIdentifier == bundleId }

        if runningApps.isEmpty {
            if !launchTermQ() {
                print("Error: Could not find or launch TermQ.app")
                print("Please ensure TermQ.app is in /Applications or current directory")
                throw ExitCode.failure
            }
        }

        // Open the URL
        let success = workspace.open(url)

        if success {
            // Output JSON for easy parsing
            let output = PendingCreateResponse(
                id: cardId.uuidString,
                status: "created",
                message: "Terminal created at: \(cwd)"
            )
            JSONHelper.printJSON(output)
        } else {
            print("Error: Failed to communicate with TermQ")
            throw ExitCode.failure
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

    func run() throws {
        do {
            let board = try BoardLoader.loadBoard(debug: debug)

            guard let card = board.findTerminal(identifier: terminal) else {
                JSONHelper.printErrorJSON("Terminal not found: \(terminal)")
                throw ExitCode.failure
            }

            // Build URL to focus the terminal
            var components = URLComponents()
            components.scheme = "termq"
            components.host = "focus"
            components.queryItems = [
                URLQueryItem(name: "id", value: card.id.uuidString)
            ]

            guard let url = components.url else {
                JSONHelper.printErrorJSON("Failed to construct URL")
                throw ExitCode.failure
            }

            // Ensure TermQ is running and focus the terminal
            let workspace = NSWorkspace.shared
            let bundleId = "com.termq.app"
            let runningApps = workspace.runningApplications.filter { $0.bundleIdentifier == bundleId }

            if runningApps.isEmpty {
                // Launch TermQ first
                if !launchTermQ() {
                    JSONHelper.printErrorJSON("Could not find or launch TermQ.app")
                    throw ExitCode.failure
                }
            }

            let success = workspace.open(url)

            if success {
                // Output terminal details as JSON
                let output = TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
                JSONHelper.printJSON(output)
            } else {
                JSONHelper.printErrorJSON("Failed to communicate with TermQ. Is it running?")
                throw ExitCode.failure
            }

        } catch BoardLoader.LoadError.boardNotFound(let path) {
            JSONHelper.printErrorJSON(
                "Board file not found at: \(path). Is TermQ installed and has been run at least once?")
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

        // Ensure TermQ is running
        let workspace = NSWorkspace.shared
        let bundleId = "com.termq.app"
        let runningApps = workspace.runningApplications.filter { $0.bundleIdentifier == bundleId }

        if runningApps.isEmpty {
            print("TermQ is not running. Launching...")
            if !launchTermQ() {
                print("Error: Could not find or launch TermQ.app")
                print("Please ensure TermQ.app is in /Applications or current directory")
                throw ExitCode.failure
            }
        }

        // Open the URL
        let success = workspace.open(url)

        if success {
            print("Creating terminal in TermQ: \(cwd)")
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

/// Helper to launch TermQ app
func launchTermQ() -> Bool {
    let possiblePaths = [
        "/Applications/TermQ.app",
        "\(NSHomeDirectory())/Applications/TermQ.app",
        "\(FileManager.default.currentDirectoryPath)/TermQ.app",
    ]

    for appPath in possiblePaths {
        if FileManager.default.fileExists(atPath: appPath) {
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
    }
    return false
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
            let board = try BoardLoader.loadBoard(debug: debug)

            // If --columns flag, output column info
            if columns {
                let columnOutput = board.sortedColumns().map { col in
                    let count = board.activeCards.filter { $0.columnId == col.id }.count
                    return ColumnOutput(from: col, terminalCount: count)
                }
                JSONHelper.printJSON(columnOutput)
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
                TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
            }

            JSONHelper.printJSON(output)

        } catch {
            JSONHelper.printErrorJSON(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

// MARK: - Find Command

struct Find: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find terminals by various criteria",
        discussion: """
            Search for terminals by name, column, tag, or ID. Returns matching terminals as JSON.
            Use --query for smart multi-word search across all fields.
            """
    )

    @Flag(name: .long, help: "Use debug data directory (TermQ-Debug)")
    var debug: Bool = false

    @Option(name: [.short, .long], help: "Smart search: matches words across name, description, path, tags")
    var query: String?

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
            let board = try BoardLoader.loadBoard(debug: debug)

            var cards = board.activeCards
            var relevanceScores: [UUID: Int] = [:]

            // Smart query search (multi-word, multi-field)
            if let queryStr = query, !queryStr.isEmpty {
                let queryWords = normalizeToWords(queryStr)
                guard !queryWords.isEmpty else {
                    JSONHelper.printJSON([TerminalOutput]())
                    return
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
            if let idFilter = id {
                if let uuid = UUID(uuidString: idFilter) {
                    cards = cards.filter { $0.id == uuid }
                } else {
                    // Invalid UUID format
                    JSONHelper.printJSON([TerminalOutput]())
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

            // Sort by relevance if query was used
            if !relevanceScores.isEmpty {
                cards.sort { card1, card2 in
                    let score1 = relevanceScores[card1.id] ?? 0
                    let score2 = relevanceScores[card2.id] ?? 0
                    return score1 > score2
                }
            }

            // Convert to output format
            let output = cards.map { card in
                TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
            }

            JSONHelper.printJSON(output)

        } catch {
            JSONHelper.printErrorJSON(error.localizedDescription)
            throw ExitCode.failure
        }
    }

    // MARK: - Smart Search Helpers

    /// Normalize text to searchable words (lowercase, remove punctuation, split on separators)
    private func normalizeToWords(_ text: String) -> Swift.Set<String> {
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

        return Swift.Set(words)
    }

    /// Calculate relevance score for a card based on query words
    private func calculateRelevanceScore(card: Card, queryWords: Swift.Set<String>) -> Int {
        var score = 0

        // Get searchable words from card fields
        let titleWords = normalizeToWords(card.title)
        let descriptionWords = normalizeToWords(card.description)
        let pathWords = normalizeToWords(card.workingDirectory)
        var tagWords = Swift.Set<String>()
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

    func run() throws {
        // First, resolve the terminal identifier to a UUID
        do {
            let board = try BoardLoader.loadBoard(debug: debug)

            guard let card = board.findTerminal(identifier: terminal) else {
                JSONHelper.printErrorJSON("Terminal not found: \(terminal)")
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

            if let llmNextAction = llmNextAction {
                queryItems.append(URLQueryItem(name: "llmNextAction", value: llmNextAction))
            }

            for tagStr in tag {
                queryItems.append(URLQueryItem(name: "tag", value: tagStr))
            }

            if replaceTags {
                queryItems.append(URLQueryItem(name: "replaceTags", value: "true"))
            }

            if let initCommand = initCommand {
                queryItems.append(URLQueryItem(name: "initCommand", value: initCommand))
            }

            if favourite {
                queryItems.append(URLQueryItem(name: "favourite", value: "true"))
            }

            if unfavourite {
                queryItems.append(URLQueryItem(name: "favourite", value: "false"))
            }

            components.queryItems = queryItems

            guard let url = components.url else {
                JSONHelper.printErrorJSON("Failed to construct URL")
                throw ExitCode.failure
            }

            // Open the URL scheme
            let workspace = NSWorkspace.shared
            let success = workspace.open(url)

            if success {
                JSONHelper.printJSON(SetResponse(success: true, id: card.id.uuidString))
            } else {
                JSONHelper.printErrorJSON("Failed to send update to TermQ. Is it running?")
                throw ExitCode.failure
            }

        } catch BoardLoader.LoadError.boardNotFound(let path) {
            JSONHelper.printErrorJSON(
                "Board file not found at: \(path). Is TermQ installed and has been run at least once?")
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

    func run() throws {
        do {
            let board = try BoardLoader.loadBoard(debug: debug)

            guard let card = board.findTerminal(identifier: terminal) else {
                JSONHelper.printErrorJSON("Terminal not found: \(terminal)")
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
                JSONHelper.printErrorJSON("Failed to construct URL")
                throw ExitCode.failure
            }

            // Open the URL scheme
            let workspace = NSWorkspace.shared
            let success = workspace.open(url)

            if success {
                JSONHelper.printJSON(MoveResponse(success: true, id: card.id.uuidString, column: toColumn))
            } else {
                JSONHelper.printErrorJSON("Failed to send move command to TermQ. Is it running?")
                throw ExitCode.failure
            }

        } catch BoardLoader.LoadError.boardNotFound(let path) {
            JSONHelper.printErrorJSON(
                "Board file not found at: \(path). Is TermQ installed and has been run at least once?")
            throw ExitCode.failure
        } catch let error as ExitCode {
            throw error
        } catch {
            JSONHelper.printErrorJSON("Unexpected error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

// MARK: - Pending Command (LLM Session Start)

struct Pending: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show terminals needing attention (LLM session start)",
        discussion: """
            Run this at the START of every LLM session. Shows terminals with:
            - Pending llmNextAction (queued tasks for you)
            - Staleness indicators based on tags

            This is your entry point for cross-session continuity.
            """
    )

    @Flag(name: .long, help: "Use debug data directory (TermQ-Debug)")
    var debug: Bool = false

    @Flag(name: .long, help: "Only show terminals with llmNextAction set")
    var actionsOnly: Bool = false

    func run() throws {
        do {
            let board = try BoardLoader.loadBoard(debug: debug)
            let cards = getFilteredAndSortedCards(from: board)
            let output = buildPendingOutput(cards: cards, board: board)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(output)
            if let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        } catch {
            JSONHelper.printErrorJSON("Failed to load board: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    private func getFilteredAndSortedCards(from board: Board) -> [Card] {
        var cards = board.activeCards

        if actionsOnly {
            cards = cards.filter { !$0.llmNextAction.isEmpty }
        }

        cards.sort { card1, card2 in
            let has1 = !card1.llmNextAction.isEmpty
            let has2 = !card2.llmNextAction.isEmpty
            if has1 != has2 { return has1 }

            let staleness1 = card1.stalenessRank
            let staleness2 = card2.stalenessRank
            if staleness1 != staleness2 { return staleness1 > staleness2 }

            return card1.title < card2.title
        }
        return cards
    }

    private func buildPendingOutput(cards: [Card], board: Board) -> PendingOutput {
        var pendingTerminals: [PendingTerminalOutput] = []
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

            pendingTerminals.append(
                PendingTerminalOutput(
                    from: card,
                    columnName: board.columnName(for: card.columnId),
                    staleness: staleness
                )
            )
        }

        return PendingOutput(
            terminals: pendingTerminals,
            summary: PendingSummary(
                total: pendingTerminals.count,
                withNextAction: withNextAction,
                stale: staleCount,
                fresh: freshCount
            )
        )
    }
}

// MARK: - Context Command (LLM Discovery)

struct Context: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show LLM-friendly context and usage guide",
        discussion: "Outputs comprehensive documentation for AI assistants including cross-session workflows."
    )

    func run() throws {
        let context = """
            # TermQ CLI - LLM Assistant Guide

            You are working with TermQ, a Kanban-style terminal manager that enables
            cross-session continuity for LLM assistants.

            ## ⚡ SESSION START CHECKLIST (Do This First!)

            1. Run `termq pending` to see what needs attention:
               ```bash
               termq pending
               ```
               This shows terminals with queued tasks (llmNextAction) and staleness.

            2. Check the summary in the output:
               - `withNextAction`: Terminals with tasks queued for you
               - `stale`: Terminals that haven't been touched recently

            3. If there are pending actions, handle them or acknowledge to user.

            ## 🛑 SESSION END CHECKLIST (Do This Before Ending!)

            1. **Queue next action** if work is incomplete:
               ```bash
               termq set "Terminal" --llm-next-action "Continue from: [specific point]"
               ```

            2. **Update staleness** to mark as recently worked:
               ```bash
               termq set "Terminal" --tag staleness=fresh
               ```

            3. **Update persistent context** if you learned something important:
               ```bash
               termq set "Terminal" --llm-prompt "Updated project context..."
               ```

            ## 📋 TAG SCHEMA (Cross-Session State Tracking)

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

            Set tags with:
            ```bash
            termq set "Terminal" --tag staleness=fresh --tag status=active
            ```

            ## 🔧 COMMAND REFERENCE

            ### Essential Commands
            ```bash
            termq pending                    # SESSION START - see what needs attention
            termq open "Name"                # Open terminal, get context
            termq set "Name" --llm-next-action "..."  # Queue task for next session
            termq set "Name" --llm-prompt "..."       # Update persistent context
            termq set "Name" --tag key=value          # Update state tags
            ```

            ### Discovery Commands
            ```bash
            termq list                       # All terminals as JSON
            termq find --tag staleness=stale # Find stale terminals
            termq find --column "In Progress" # Find by workflow stage
            termq find --tag project=org/repo # Find by project
            ```

            ### Workflow Commands
            ```bash
            termq move "Name" "Done"         # Move to column
            termq create --name "New" --column "To Do"  # New terminal
            ```

            ## 📊 TERMINAL FIELDS

            Each terminal has:
            - **name**: Display name
            - **description**: What this terminal is for
            - **column**: Workflow stage (To Do, In Progress, Done)
            - **path**: Working directory
            - **tags**: Key-value metadata (use for state tracking!)
            - **llmPrompt**: Persistent context (never auto-cleared)
            - **llmNextAction**: One-time task (cleared after terminal opens)

            ## 🔄 CROSS-SESSION WORKFLOW EXAMPLE

            ```bash
            # Session 1: Starting work
            termq pending  # Check what needs attention
            termq open "API Project"  # Get context
            # ... do work ...
            termq set "API Project" --llm-next-action "Implement auth middleware"
            termq set "API Project" --tag staleness=fresh --tag status=active

            # Session 2: Resuming
            termq pending  # Shows "API Project" with pending action
            # You see: "Implement auth middleware"
            termq open "API Project"  # Get full context
            # ... continue work ...
            termq set "API Project" --llm-next-action ""  # Clear if done
            termq set "API Project" --tag status=review
            termq move "API Project" "Review"
            ```

            ## 💡 TIPS

            - ALWAYS run `termq pending` at session start
            - ALWAYS set `llmNextAction` when parking incomplete work
            - Use `staleness` tag to track what needs attention
            - Use `project` tag to group related terminals
            - Keep `llmPrompt` updated with key project context
            - Move terminals through columns as work progresses
            """
        print(context)
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

    func run() throws {
        do {
            let board = try BoardLoader.loadBoard(debug: debug)

            guard let card = board.findTerminal(identifier: terminal) else {
                JSONHelper.printErrorJSON("Terminal not found: \(terminal)")
                throw ExitCode.failure
            }

            // Build URL for delete
            var components = URLComponents()
            components.scheme = "termq"
            components.host = "delete"

            components.queryItems = [
                URLQueryItem(name: "id", value: card.id.uuidString),
                URLQueryItem(name: "permanent", value: permanent ? "true" : "false"),
            ]

            guard let url = components.url else {
                JSONHelper.printErrorJSON("Failed to construct URL")
                throw ExitCode.failure
            }

            // Open the URL scheme
            let workspace = NSWorkspace.shared
            let success = workspace.open(url)

            if success {
                JSONHelper.printJSON(DeleteResponse(id: card.id.uuidString, permanent: permanent))
            } else {
                JSONHelper.printErrorJSON("Failed to send delete command to TermQ. Is it running?")
                throw ExitCode.failure
            }

        } catch BoardLoader.LoadError.boardNotFound(let path) {
            JSONHelper.printErrorJSON(
                "Board file not found at: \(path). Is TermQ installed and has been run at least once?")
            throw ExitCode.failure
        } catch let error as ExitCode {
            throw error
        } catch {
            JSONHelper.printErrorJSON("Unexpected error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
