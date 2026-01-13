import Foundation

// MARK: - Board Data Structures (read-only for MCP)

/// Minimal Tag representation for MCP
struct MCPTag: Codable, Sendable {
    let id: UUID
    let key: String
    let value: String
}

/// Minimal Column representation for MCP
struct MCPColumn: Codable, Sendable {
    let id: UUID
    let name: String
    let orderIndex: Int
    let color: String
}

/// Minimal TerminalCard representation for MCP
struct MCPCard: Codable, Sendable {
    let id: UUID
    let title: String
    let description: String
    let tags: [MCPTag]
    let columnId: UUID
    let orderIndex: Int
    let workingDirectory: String
    let isFavourite: Bool
    let badge: String
    let llmPrompt: String
    let llmNextAction: String
    let deletedAt: Date?

    // Custom decoding to handle missing fields for backwards compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        tags = try container.decodeIfPresent([MCPTag].self, forKey: .tags) ?? []
        columnId = try container.decode(UUID.self, forKey: .columnId)
        orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex) ?? 0
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
        isFavourite = try container.decodeIfPresent(Bool.self, forKey: .isFavourite) ?? false
        badge = try container.decodeIfPresent(String.self, forKey: .badge) ?? ""
        llmPrompt = try container.decodeIfPresent(String.self, forKey: .llmPrompt) ?? ""
        llmNextAction = try container.decodeIfPresent(String.self, forKey: .llmNextAction) ?? ""
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, tags, columnId, orderIndex
        case workingDirectory, isFavourite, badge, llmPrompt, llmNextAction, deletedAt
    }

    var isDeleted: Bool { deletedAt != nil }

    /// Parsed badges from comma-separated badge string
    var badges: [String] {
        guard !badge.isEmpty else { return [] }
        return
            badge
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Convert tags to dictionary
    var tagsDictionary: [String: String] {
        var dict: [String: String] = [:]
        for tag in tags {
            dict[tag.key] = tag.value
        }
        return dict
    }
}

/// Minimal Board representation for MCP
struct MCPBoard: Codable, Sendable {
    let columns: [MCPColumn]
    let cards: [MCPCard]

    var activeCards: [MCPCard] {
        cards.filter { !$0.isDeleted }
    }

    func columnName(for columnId: UUID) -> String {
        columns.first { $0.id == columnId }?.name ?? "Unknown"
    }

    func sortedColumns() -> [MCPColumn] {
        columns.sorted { $0.orderIndex < $1.orderIndex }
    }
}

// MARK: - Board Loader

/// Loads board data from disk
enum BoardLoader {
    enum LoadError: Error, LocalizedError {
        case boardNotFound(path: String)
        case decodingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .boardNotFound(let path):
                return "Board file not found at: \(path). Is TermQ installed and has been run at least once?"
            case .decodingFailed(let error):
                return "Failed to decode board: \(error.localizedDescription)"
            }
        }
    }

    /// Get the TermQ data directory path
    static func getDataDirectoryPath(customDirectory: URL? = nil, debug: Bool = false) -> URL {
        if let custom = customDirectory {
            return custom
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dirName = debug ? "TermQ-Debug" : "TermQ"
        return appSupport.appendingPathComponent(dirName, isDirectory: true)
    }

    /// Load the board from disk
    static func loadBoard(dataDirectory: URL? = nil, debug: Bool = false) throws -> MCPBoard {
        let dataDir = getDataDirectoryPath(customDirectory: dataDirectory, debug: debug)
        let boardURL = dataDir.appendingPathComponent("board.json")

        guard FileManager.default.fileExists(atPath: boardURL.path) else {
            throw LoadError.boardNotFound(path: boardURL.path)
        }

        do {
            let data = try Data(contentsOf: boardURL)
            return try JSONDecoder().decode(MCPBoard.self, from: data)
        } catch let error as DecodingError {
            throw LoadError.decodingFailed(error)
        }
    }
}

// MARK: - Board Writer (for MCP write operations)

/// Handles board modifications using raw JSON to preserve unknown fields
enum BoardWriter {
    enum WriteError: Error, LocalizedError {
        case boardNotFound(path: String)
        case cardNotFound(identifier: String)
        case columnNotFound(name: String)
        case encodingFailed(Error)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .boardNotFound(let path):
                return "Board file not found at: \(path)"
            case .cardNotFound(let identifier):
                return "Terminal not found: \(identifier)"
            case .columnNotFound(let name):
                return "Column not found: \(name)"
            case .encodingFailed(let error):
                return "Failed to encode board: \(error.localizedDescription)"
            case .writeFailed(let error):
                return "Failed to write board: \(error.localizedDescription)"
            }
        }
    }

    /// Load board as raw JSON dictionary (preserves all fields)
    static func loadRawBoard(
        dataDirectory: URL? = nil, debug: Bool = false
    ) throws -> (
        url: URL, data: [String: Any]
    ) {
        let dataDir = BoardLoader.getDataDirectoryPath(customDirectory: dataDirectory, debug: debug)
        let boardURL = dataDir.appendingPathComponent("board.json")

        guard FileManager.default.fileExists(atPath: boardURL.path) else {
            throw WriteError.boardNotFound(path: boardURL.path)
        }

        let jsonData = try Data(contentsOf: boardURL)
        guard let board = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw WriteError.encodingFailed(
                NSError(
                    domain: "BoardWriter", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Invalid board format"
                    ]))
        }

        return (boardURL, board)
    }

    /// Save raw board JSON to disk
    static func saveRawBoard(_ board: [String: Any], to url: URL) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: board, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: url, options: .atomic)
    }

    /// Update a card's fields
    static func updateCard(
        identifier: String,
        updates: [String: Any],
        dataDirectory: URL? = nil,
        debug: Bool = false
    ) throws -> MCPCard {
        let rawBoard = try loadRawBoard(dataDirectory: dataDirectory, debug: debug)
        let boardURL = rawBoard.url
        var board = rawBoard.data
        guard var cards = board["cards"] as? [[String: Any]] else {
            throw WriteError.encodingFailed(
                NSError(
                    domain: "BoardWriter", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Invalid cards format"
                    ]))
        }

        // Find the card to update
        let cardIndex = try findCardIndex(identifier: identifier, in: cards)

        // Apply updates
        for (key, value) in updates {
            cards[cardIndex][key] = value
        }

        // Save back
        board["cards"] = cards
        try saveRawBoard(board, to: boardURL)

        // Return the updated board's card
        let updatedBoard = try BoardLoader.loadBoard(dataDirectory: dataDirectory, debug: debug)
        guard let updatedCard = updatedBoard.findTerminal(identifier: identifier) else {
            throw WriteError.cardNotFound(identifier: identifier)
        }
        return updatedCard
    }

    /// Move a card to a different column
    static func moveCard(
        identifier: String,
        toColumn columnName: String,
        dataDirectory: URL? = nil,
        debug: Bool = false
    ) throws -> MCPCard {
        let rawBoard = try loadRawBoard(dataDirectory: dataDirectory, debug: debug)
        let boardURL = rawBoard.url
        var board = rawBoard.data
        guard var cards = board["cards"] as? [[String: Any]],
            let columns = board["columns"] as? [[String: Any]]
        else {
            throw WriteError.encodingFailed(
                NSError(
                    domain: "BoardWriter", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Invalid board format"
                    ]))
        }

        // Find target column
        let columnNameLower = columnName.lowercased()
        guard
            let targetColumn = columns.first(where: {
                ($0["name"] as? String)?.lowercased() == columnNameLower
            }),
            let targetColumnId = targetColumn["id"] as? String
        else {
            throw WriteError.columnNotFound(name: columnName)
        }

        // Find the card to move
        let cardIndex = try findCardIndex(identifier: identifier, in: cards)

        // Calculate new orderIndex (put at end of target column)
        let cardsInTargetColumn = cards.filter { ($0["columnId"] as? String) == targetColumnId }
        let maxOrderIndex = cardsInTargetColumn.compactMap { $0["orderIndex"] as? Int }.max() ?? -1

        // Update the card
        cards[cardIndex]["columnId"] = targetColumnId
        cards[cardIndex]["orderIndex"] = maxOrderIndex + 1

        // Save back
        board["cards"] = cards
        try saveRawBoard(board, to: boardURL)

        // Return the updated card
        let updatedBoard = try BoardLoader.loadBoard(dataDirectory: dataDirectory, debug: debug)
        guard let updatedCard = updatedBoard.findTerminal(identifier: identifier) else {
            throw WriteError.cardNotFound(identifier: identifier)
        }
        return updatedCard
    }

    /// Create a new card
    static func createCard(
        name: String,
        columnName: String?,
        workingDirectory: String,
        description: String = "",
        dataDirectory: URL? = nil,
        debug: Bool = false
    ) throws -> MCPCard {
        let rawBoard = try loadRawBoard(dataDirectory: dataDirectory, debug: debug)
        let boardURL = rawBoard.url
        var board = rawBoard.data
        guard var cards = board["cards"] as? [[String: Any]],
            let columns = board["columns"] as? [[String: Any]]
        else {
            throw WriteError.encodingFailed(
                NSError(
                    domain: "BoardWriter", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Invalid board format"
                    ]))
        }

        // Find target column (default to first column if not specified)
        let targetColumn: [String: Any]
        if let columnName = columnName {
            let columnNameLower = columnName.lowercased()
            guard
                let found = columns.first(where: {
                    ($0["name"] as? String)?.lowercased() == columnNameLower
                })
            else {
                throw WriteError.columnNotFound(name: columnName)
            }
            targetColumn = found
        } else {
            // Use first column sorted by orderIndex
            let sortedColumns = columns.sorted {
                ($0["orderIndex"] as? Int ?? 0) < ($1["orderIndex"] as? Int ?? 0)
            }
            guard let first = sortedColumns.first else {
                throw WriteError.columnNotFound(name: "default")
            }
            targetColumn = first
        }

        guard let targetColumnId = targetColumn["id"] as? String else {
            throw WriteError.columnNotFound(name: columnName ?? "default")
        }

        // Calculate orderIndex
        let cardsInTargetColumn = cards.filter { ($0["columnId"] as? String) == targetColumnId }
        let maxOrderIndex = cardsInTargetColumn.compactMap { $0["orderIndex"] as? Int }.max() ?? -1

        // Create new card
        let newCardId = UUID()
        let newCard: [String: Any] = [
            "id": newCardId.uuidString,
            "title": name,
            "description": description,
            "columnId": targetColumnId,
            "orderIndex": maxOrderIndex + 1,
            "workingDirectory": workingDirectory,
            "isFavourite": false,
            "badge": "",
            "llmPrompt": "",
            "llmNextAction": "",
            "tags": [[String: Any]](),
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]

        cards.append(newCard)
        board["cards"] = cards
        try saveRawBoard(board, to: boardURL)

        // Return the created card
        let updatedBoard = try BoardLoader.loadBoard(dataDirectory: dataDirectory, debug: debug)
        guard let createdCard = updatedBoard.findTerminal(identifier: newCardId.uuidString) else {
            throw WriteError.cardNotFound(identifier: newCardId.uuidString)
        }
        return createdCard
    }

    /// Find card index by identifier
    private static func findCardIndex(identifier: String, in cards: [[String: Any]]) throws -> Int {
        // Try as UUID
        if let _ = UUID(uuidString: identifier) {
            if let index = cards.firstIndex(where: {
                ($0["id"] as? String) == identifier && $0["deletedAt"] == nil
            }) {
                return index
            }
        }

        // Try as exact name (case-insensitive)
        let identifierLower = identifier.lowercased()
        if let index = cards.firstIndex(where: {
            ($0["title"] as? String)?.lowercased() == identifierLower && $0["deletedAt"] == nil
        }) {
            return index
        }

        // Try as partial name match
        if let index = cards.firstIndex(where: {
            ($0["title"] as? String)?.lowercased().contains(identifierLower) == true && $0["deletedAt"] == nil
        }) {
            return index
        }

        throw WriteError.cardNotFound(identifier: identifier)
    }
}

// MARK: - Terminal Matching

extension MCPBoard {
    /// Find a terminal by identifier (UUID, name, or path)
    func findTerminal(identifier: String) -> MCPCard? {
        // Try as UUID first
        if let uuid = UUID(uuidString: identifier) {
            if let card = activeCards.first(where: { $0.id == uuid }) {
                return card
            }
        }

        // Try as exact name (case-insensitive)
        let identifierLower = identifier.lowercased()
        if let card = activeCards.first(where: { $0.title.lowercased() == identifierLower }) {
            return card
        }

        // Try as path (exact match or ends with)
        let normalizedPath =
            identifier.hasSuffix("/")
            ? String(identifier.dropLast())
            : identifier
        if let card = activeCards.first(where: { card in
            card.workingDirectory == normalizedPath
                || card.workingDirectory == identifier
                || card.workingDirectory.hasSuffix("/\(normalizedPath)")
        }) {
            return card
        }

        // Try as partial name match
        if let card = activeCards.first(where: { $0.title.lowercased().contains(identifierLower) }) {
            return card
        }

        return nil
    }
}
