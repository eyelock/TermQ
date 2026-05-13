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

    /// Get the TermQ data directory path.
    ///
    /// - Parameters:
    ///   - customDirectory: Optional override (typically for tests). When non-nil, ignores `profile`.
    ///   - profile: Which app profile's data directory to resolve. Defaults to `.current` —
    ///     resolves to `.debug` in `TERMQ_DEBUG_BUILD` builds and `.production` otherwise.
    public static func getDataDirectoryPath(
        customDirectory: URL? = nil,
        profile: AppProfile.Variant = .current
    ) -> URL {
        if let custom = customDirectory {
            return custom
        }
        let dirName = profile.dataDirectoryName
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            // Fallback to home directory if Application Support not available
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            return homeDir.appendingPathComponent(".termq", isDirectory: true).appendingPathComponent(
                dirName, isDirectory: true)
        }
        return appSupport.appendingPathComponent(dirName, isDirectory: true)
    }

    /// Load the board from disk with file coordination for safe concurrent access.
    ///
    /// - Parameters:
    ///   - dataDirectory: Optional explicit data directory (tests use a temp dir).
    ///   - profile: Which app profile to resolve when `dataDirectory` is nil. Defaults to `.current`.
    public static func loadBoard(
        dataDirectory: URL? = nil,
        profile: AppProfile.Variant = .current
    ) throws -> Board {
        let dataDir = getDataDirectoryPath(customDirectory: dataDirectory, profile: profile)
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
        dataDirectory: URL? = nil, profile: AppProfile.Variant = .current
    ) throws -> (url: URL, data: [String: Any]) {
        let dataDir = BoardLoader.getDataDirectoryPath(customDirectory: dataDirectory, profile: profile)
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

    /// Save raw board JSON to disk with file coordination for safe concurrent access.
    ///
    /// **Avoid for new code.** This is a half-claim (write only). Pairing a separate
    /// `loadRawBoard` read claim with a `saveRawBoard` write claim opens a lost-update
    /// race: two processes can both finish their reads before either writes, and the
    /// second write silently clobbers the first. Use `atomicUpdate(...)` instead for any
    /// read-modify-write — it holds a single exclusive claim across both halves.
    /// Retained here only for callers that are genuinely write-only (constructing a
    /// fresh board from scratch).
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

    /// Atomic read-modify-write under a single `NSFileCoordinator` writing claim.
    ///
    /// The closure receives the parsed board JSON. It may mutate the board however it
    /// likes (and may compute and return any value from it). The mutated board is written
    /// back inside the same exclusive claim, so no other process can read or write the
    /// file while this call is in flight.
    ///
    /// Closes the lost-update race that a split `loadRawBoard` + `saveRawBoard` pattern
    /// otherwise allows: two processes both finishing their reads before either writes,
    /// and the second write silently clobbering the first. Same fix also resolves the
    /// `orderIndex` collision (two concurrent appends computing the same `max + 1`).
    @discardableResult
    public static func atomicUpdate<T>(
        dataDirectory: URL? = nil,
        profile: AppProfile.Variant = .current,
        body: (inout [String: Any]) throws -> T
    ) throws -> T {
        let dataDir = BoardLoader.getDataDirectoryPath(customDirectory: dataDirectory, profile: profile)
        let boardURL = dataDir.appendingPathComponent("board.json")

        guard FileManager.default.fileExists(atPath: boardURL.path) else {
            throw WriteError.boardNotFound(path: boardURL.path)
        }

        var coordinationError: NSError?
        var result: Result<T, Error>?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: boardURL, options: [], error: &coordinationError) { writeURL in
            do {
                let data = try Data(contentsOf: writeURL)
                guard var board = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw WriteError.encodingFailed("Invalid board format")
                }
                let value = try body(&board)
                let newData = try JSONSerialization.data(
                    withJSONObject: board, options: [.prettyPrinted, .sortedKeys])
                try newData.write(to: writeURL, options: .atomic)
                result = .success(value)
            } catch {
                result = .failure(error)
            }
        }

        if let error = coordinationError {
            throw WriteError.coordinationFailed(error.localizedDescription)
        }
        guard let result else {
            throw WriteError.coordinationFailed("File coordination completed without result")
        }
        return try result.get()
    }

    /// Update a card's fields atomically.
    ///
    /// Read, mutation, and write happen under a single `NSFileCoordinator` writing claim
    /// — no other process can interleave, so the lost-update race is closed.
    public static func updateCard(
        identifier: String,
        updates: [String: Any],
        dataDirectory: URL? = nil,
        profile: AppProfile.Variant = .current
    ) throws -> Card {
        return try atomicUpdate(dataDirectory: dataDirectory, profile: profile) { board in
            guard var cards = board["cards"] as? [[String: Any]] else {
                throw WriteError.encodingFailed("Invalid cards format")
            }

            // Find the card to update (include deleted cards so we can update after soft-delete)
            let cardIndex = try findCardIndex(identifier: identifier, in: cards, includeDeleted: true)

            // Capture the stable UUID before applying updates — the caller may be renaming
            // the card (updating `title`), which would break a post-mutation name lookup.
            let cardUUID = (cards[cardIndex]["id"] as? String).flatMap(UUID.init(uuidString:))

            for (key, value) in updates {
                cards[cardIndex][key] = value
            }
            board["cards"] = cards

            // Decode the post-mutation card from the in-memory dict so we return a result
            // that matches what's about to be persisted (and don't have to re-read from disk
            // outside the claim, which would re-open the race).
            let decoded = try decodeCard(at: cardIndex, in: cards, identifier: identifier, capturedUUID: cardUUID)
            return decoded
        }
    }

    /// Decode the card at `cardIndex` from a raw cards array.
    /// Helper used by `updateCard` to return a typed `Card` from the mutated state without
    /// leaving the atomic claim.
    private static func decodeCard(
        at cardIndex: Int,
        in cards: [[String: Any]],
        identifier: String,
        capturedUUID: UUID?
    ) throws -> Card {
        let cardData = try JSONSerialization.data(withJSONObject: cards[cardIndex])
        do {
            return try JSONDecoder().decode(Card.self, from: cardData)
        } catch {
            // If decoding the specific row fails for any reason, surface card-not-found
            // with the original identifier so callers see a useful error.
            _ = capturedUUID
            throw WriteError.cardNotFound(identifier: identifier)
        }
    }

    /// Move a card to a different column atomically. See `updateCard` for race-fix details.
    public static func moveCard(
        identifier: String,
        toColumn columnName: String,
        dataDirectory: URL? = nil,
        profile: AppProfile.Variant = .current
    ) throws -> Card {
        return try atomicUpdate(dataDirectory: dataDirectory, profile: profile) { board in
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

            let cardIndex = try findCardIndex(identifier: identifier, in: cards)

            // Calculate new orderIndex inside the claim — concurrent appends can no longer
            // both compute the same `max + 1`.
            let cardsInTargetColumn = cards.filter { ($0["columnId"] as? String) == targetColumnId }
            let maxOrderIndex = cardsInTargetColumn.compactMap { $0["orderIndex"] as? Int }.max() ?? -1

            cards[cardIndex]["columnId"] = targetColumnId
            cards[cardIndex]["orderIndex"] = maxOrderIndex + 1
            board["cards"] = cards

            let cardUUID = (cards[cardIndex]["id"] as? String).flatMap(UUID.init(uuidString:))
            return try decodeCard(at: cardIndex, in: cards, identifier: identifier, capturedUUID: cardUUID)
        }
    }

    /// Create a new card atomically. See `updateCard` for race-fix details.
    /// The `orderIndex` calculation now runs inside the exclusive claim, so two
    /// concurrent appends to the same column produce distinct `orderIndex` values.
    public static func createCard(
        name: String,
        columnName: String?,
        workingDirectory: String,
        description: String = "",
        dataDirectory: URL? = nil,
        profile: AppProfile.Variant = .current
    ) throws -> Card {
        return try atomicUpdate(dataDirectory: dataDirectory, profile: profile) { board in
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

            let cardsInTargetColumn = cards.filter { ($0["columnId"] as? String) == targetColumnId }
            let maxOrderIndex = cardsInTargetColumn.compactMap { $0["orderIndex"] as? Int }.max() ?? -1

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

            // Decode the just-appended card from the in-claim state.
            let newIndex = cards.count - 1
            return try decodeCard(
                at: newIndex, in: cards, identifier: newCardId.uuidString, capturedUUID: newCardId)
        }
    }

    // MARK: - Column CRUD

    /// Create a new column. Throws if a column with the same name (case-insensitive)
    /// already exists.
    public static func createColumn(
        name: String,
        description: String = "",
        color: String = "#6B7280",
        dataDirectory: URL? = nil,
        profile: AppProfile.Variant = .current
    ) throws -> Column {
        return try atomicUpdate(dataDirectory: dataDirectory, profile: profile) { board in
            guard var columns = board["columns"] as? [[String: Any]] else {
                throw WriteError.encodingFailed("Invalid columns format")
            }
            let nameLower = name.lowercased()
            if columns.contains(where: { ($0["name"] as? String)?.lowercased() == nameLower }) {
                throw WriteError.encodingFailed("Column already exists: \(name)")
            }
            let maxOrder = columns.compactMap { $0["orderIndex"] as? Int }.max() ?? -1
            let newId = UUID()
            let newColumn: [String: Any] = [
                "id": newId.uuidString,
                "name": name,
                "description": description,
                "orderIndex": maxOrder + 1,
                "color": color,
            ]
            columns.append(newColumn)
            board["columns"] = columns
            let data = try JSONSerialization.data(withJSONObject: newColumn)
            return try JSONDecoder().decode(Column.self, from: data)
        }
    }

    /// Rename an existing column. Card membership is unchanged.
    @discardableResult
    public static func renameColumn(
        identifier: String,
        newName: String,
        dataDirectory: URL? = nil,
        profile: AppProfile.Variant = .current
    ) throws -> Column {
        return try atomicUpdate(dataDirectory: dataDirectory, profile: profile) { board in
            guard var columns = board["columns"] as? [[String: Any]] else {
                throw WriteError.encodingFailed("Invalid columns format")
            }
            let identifierLower = identifier.lowercased()
            guard let idx = columns.firstIndex(where: {
                ($0["name"] as? String)?.lowercased() == identifierLower
                    || ($0["id"] as? String) == identifier
            }) else {
                throw WriteError.columnNotFound(name: identifier)
            }
            // Reject duplicates (other than the renamed column itself).
            let newNameLower = newName.lowercased()
            if columns.enumerated().contains(where: { i, c in
                i != idx && (c["name"] as? String)?.lowercased() == newNameLower
            }) {
                throw WriteError.encodingFailed("Column already exists: \(newName)")
            }
            columns[idx]["name"] = newName
            board["columns"] = columns
            let data = try JSONSerialization.data(withJSONObject: columns[idx])
            return try JSONDecoder().decode(Column.self, from: data)
        }
    }

    /// Delete a column.
    ///
    /// - Throws `columnNotFound` if the column doesn't exist.
    /// - When `force == false` (default): throws `encodingFailed` if any active cards
    ///   remain in the column — callers must move or delete them first.
    /// - When `force == true`: soft-deletes all cards in the column (sets `deletedAt`).
    ///   The column is removed from the columns array regardless. Soft-deleted cards
    ///   can be individually restored via `restoreCard`.
    public static func deleteColumn(
        identifier: String,
        force: Bool = false,
        dataDirectory: URL? = nil,
        profile: AppProfile.Variant = .current
    ) throws {
        try atomicUpdate(dataDirectory: dataDirectory, profile: profile) { board in
            guard var columns = board["columns"] as? [[String: Any]],
                var cards = board["cards"] as? [[String: Any]]
            else {
                throw WriteError.encodingFailed("Invalid board format")
            }
            let identifierLower = identifier.lowercased()
            guard let idx = columns.firstIndex(where: {
                ($0["name"] as? String)?.lowercased() == identifierLower
                    || ($0["id"] as? String) == identifier
            }) else {
                throw WriteError.columnNotFound(name: identifier)
            }
            guard let columnId = columns[idx]["id"] as? String else {
                throw WriteError.columnNotFound(name: identifier)
            }

            let activeInColumn = cards.filter {
                ($0["columnId"] as? String) == columnId && $0["deletedAt"] == nil
            }
            if !activeInColumn.isEmpty && !force {
                throw WriteError.encodingFailed(
                    "Column '\(identifier)' has \(activeInColumn.count) active card(s)."
                        + " Move them or pass force: true to soft-delete them.")
            }

            if force {
                let nowString = ISO8601DateFormatter().string(from: Date())
                for i in cards.indices where (cards[i]["columnId"] as? String) == columnId
                    && cards[i]["deletedAt"] == nil {
                    cards[i]["deletedAt"] = nowString
                }
                board["cards"] = cards
            }
            columns.remove(at: idx)
            board["columns"] = columns
            return ()
        }
    }

    /// Restore a soft-deleted card by clearing its `deletedAt` timestamp.
    @discardableResult
    public static func restoreCard(
        identifier: String,
        dataDirectory: URL? = nil,
        profile: AppProfile.Variant = .current
    ) throws -> Card {
        return try atomicUpdate(dataDirectory: dataDirectory, profile: profile) { board in
            guard var cards = board["cards"] as? [[String: Any]] else {
                throw WriteError.encodingFailed("Invalid cards format")
            }
            // Find among deleted cards specifically — restoring something not in the bin
            // is a no-op the caller should know about.
            let identifierLower = identifier.lowercased()
            guard let idx = cards.firstIndex(where: {
                let isDeleted = $0["deletedAt"] != nil
                let matches =
                    ($0["id"] as? String) == identifier
                    || ($0["title"] as? String)?.lowercased() == identifierLower
                return isDeleted && matches
            }) else {
                throw WriteError.cardNotFound(identifier: identifier)
            }
            cards[idx]["deletedAt"] = nil
            // Remove the deletedAt key entirely rather than leaving an NSNull entry.
            cards[idx].removeValue(forKey: "deletedAt")
            board["cards"] = cards
            let cardUUID = (cards[idx]["id"] as? String).flatMap(UUID.init(uuidString:))
            return try decodeCard(
                at: idx, in: cards, identifier: identifier, capturedUUID: cardUUID)
        }
    }

    /// Find card index by identifier
    private static func findCardIndex(
        identifier: String,
        in cards: [[String: Any]],
        includeDeleted: Bool = false
    ) throws -> Int {
        // Try as UUID
        if UUID(uuidString: identifier) != nil {
            if let index = cards.firstIndex(where: {
                let matchesId = ($0["id"] as? String) == identifier
                let isNotDeleted = $0["deletedAt"] == nil
                return includeDeleted ? matchesId : (matchesId && isNotDeleted)
            }) {
                return index
            }
        }

        // Try as exact name (case-insensitive)
        let identifierLower = identifier.lowercased()
        if let index = cards.firstIndex(where: {
            let matchesName = ($0["title"] as? String)?.lowercased() == identifierLower
            let isNotDeleted = $0["deletedAt"] == nil
            return includeDeleted ? matchesName : (matchesName && isNotDeleted)
        }) {
            return index
        }

        // Try as partial name match
        if let index = cards.firstIndex(where: {
            let matchesPartialName = ($0["title"] as? String)?.lowercased().contains(identifierLower) == true
            let isNotDeleted = $0["deletedAt"] == nil
            return includeDeleted ? matchesPartialName : (matchesPartialName && isNotDeleted)
        }) {
            return index
        }

        throw WriteError.cardNotFound(identifier: identifier)
    }
}
