import Foundation

// MARK: - Board Loader

/// Loads board data from disk (shared across CLI and MCP)
/// Uses NSFileCoordinator for safe concurrent access across processes
public enum BoardLoader {
    public enum LoadError: Error, LocalizedError, Sendable {
        case boardNotFound(path: String)
        case decodingFailed(String)
        case coordinationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .boardNotFound(let path):
                return "Board file not found at: \(path). Is TermQ installed and has been run at least once?"
            case .decodingFailed(let message):
                return "Failed to decode board: \(message)"
            case .coordinationFailed(let message):
                return "File coordination failed: \(message)"
            }
        }
    }

    /// Get the TermQ data directory path
    public static func getDataDirectoryPath(customDirectory: URL? = nil, debug: Bool = false) -> URL {
        if let custom = customDirectory {
            return custom
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dirName = debug ? "TermQ-Debug" : "TermQ"
        return appSupport.appendingPathComponent(dirName, isDirectory: true)
    }

    /// Load the board from disk with file coordination for safe concurrent access
    public static func loadBoard(dataDirectory: URL? = nil, debug: Bool = false) throws -> Board {
        let dataDir = getDataDirectoryPath(customDirectory: dataDirectory, debug: debug)
        let boardURL = dataDir.appendingPathComponent("board.json")

        guard FileManager.default.fileExists(atPath: boardURL.path) else {
            throw LoadError.boardNotFound(path: boardURL.path)
        }

        var coordinationError: NSError?
        var loadResult: Result<Board, Error>?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: boardURL, options: [], error: &coordinationError) { url in
            do {
                let data = try Data(contentsOf: url)
                let board = try JSONDecoder().decode(Board.self, from: data)
                loadResult = .success(board)
            } catch let error as DecodingError {
                loadResult = .failure(LoadError.decodingFailed(error.localizedDescription))
            } catch {
                loadResult = .failure(error)
            }
        }

        if let error = coordinationError {
            throw LoadError.coordinationFailed(error.localizedDescription)
        }

        guard let result = loadResult else {
            throw LoadError.coordinationFailed("File coordination completed without result")
        }

        return try result.get()
    }
}

// MARK: - Board Writer

/// Handles board modifications using raw JSON to preserve unknown fields (shared across CLI and MCP)
/// Uses NSFileCoordinator for safe concurrent access across processes
public enum BoardWriter {
    public enum WriteError: Error, LocalizedError, Sendable {
        case boardNotFound(path: String)
        case cardNotFound(identifier: String)
        case columnNotFound(name: String)
        case encodingFailed(String)
        case writeFailed(String)
        case coordinationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .boardNotFound(let path):
                return "Board file not found at: \(path)"
            case .cardNotFound(let identifier):
                return "Terminal not found: \(identifier)"
            case .columnNotFound(let name):
                return "Column not found: \(name)"
            case .encodingFailed(let message):
                return "Failed to encode board: \(message)"
            case .writeFailed(let message):
                return "Failed to write board: \(message)"
            case .coordinationFailed(let message):
                return "File coordination failed: \(message)"
            }
        }
    }

    /// Load board as raw JSON dictionary (preserves all fields)
    /// Uses file coordination for safe concurrent access
    public static func loadRawBoard(
        dataDirectory: URL? = nil, debug: Bool = false
    ) throws -> (url: URL, data: [String: Any]) {
        let dataDir = BoardLoader.getDataDirectoryPath(customDirectory: dataDirectory, debug: debug)
        let boardURL = dataDir.appendingPathComponent("board.json")

        guard FileManager.default.fileExists(atPath: boardURL.path) else {
            throw WriteError.boardNotFound(path: boardURL.path)
        }

        var coordinationError: NSError?
        var loadResult: Result<[String: Any], Error>?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: boardURL, options: [], error: &coordinationError) { url in
            do {
                let jsonData = try Data(contentsOf: url)
                guard let board = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    loadResult = .failure(WriteError.encodingFailed("Invalid board format"))
                    return
                }
                loadResult = .success(board)
            } catch {
                loadResult = .failure(error)
            }
        }

        if let error = coordinationError {
            throw WriteError.coordinationFailed(error.localizedDescription)
        }

        guard let result = loadResult else {
            throw WriteError.coordinationFailed("File coordination completed without result")
        }

        return (boardURL, try result.get())
    }

    /// Save raw board JSON to disk with file coordination for safe concurrent access
    public static func saveRawBoard(_ board: [String: Any], to url: URL) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: board, options: [.prettyPrinted, .sortedKeys])

        var coordinationError: NSError?
        var writeError: Error?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { writeURL in
            do {
                try jsonData.write(to: writeURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let error = coordinationError {
            throw WriteError.coordinationFailed(error.localizedDescription)
        }

        if let error = writeError {
            throw WriteError.writeFailed(error.localizedDescription)
        }
    }

    /// Update a card's fields
    public static func updateCard(
        identifier: String,
        updates: [String: Any],
        dataDirectory: URL? = nil,
        debug: Bool = false
    ) throws -> Card {
        let rawBoard = try loadRawBoard(dataDirectory: dataDirectory, debug: debug)
        let boardURL = rawBoard.url
        var board = rawBoard.data
        guard var cards = board["cards"] as? [[String: Any]] else {
            throw WriteError.encodingFailed("Invalid cards format")
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
    public static func moveCard(
        identifier: String,
        toColumn columnName: String,
        dataDirectory: URL? = nil,
        debug: Bool = false
    ) throws -> Card {
        let rawBoard = try loadRawBoard(dataDirectory: dataDirectory, debug: debug)
        let boardURL = rawBoard.url
        var board = rawBoard.data
        guard var cards = board["cards"] as? [[String: Any]],
            let columns = board["columns"] as? [[String: Any]]
        else {
            throw WriteError.encodingFailed("Invalid board format")
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
    public static func createCard(
        name: String,
        columnName: String?,
        workingDirectory: String,
        description: String = "",
        dataDirectory: URL? = nil,
        debug: Bool = false
    ) throws -> Card {
        let rawBoard = try loadRawBoard(dataDirectory: dataDirectory, debug: debug)
        let boardURL = rawBoard.url
        var board = rawBoard.data
        guard var cards = board["cards"] as? [[String: Any]],
            let columns = board["columns"] as? [[String: Any]]
        else {
            throw WriteError.encodingFailed("Invalid board format")
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
