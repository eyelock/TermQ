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
