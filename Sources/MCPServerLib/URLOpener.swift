import Foundation

#if os(macOS)
    import AppKit
#endif

/// Opens URL schemes to communicate with the TermQ GUI application
///
/// This is used by the MCP server to delegate mutations to the GUI app,
/// ensuring the GUI is always the single source of truth for board state.
enum URLOpener {
    /// Parameters for building a termq://open URL
    struct OpenURLParams {
        let cardId: UUID
        let path: String
        var name: String?
        var description: String?
        var column: String?
        var tags: [(key: String, value: String)]?
        var llmPrompt: String?
        var llmNextAction: String?
        var initCommand: String?
    }

    /// Parameters for building a termq://update URL
    struct UpdateURLParams {
        let cardId: UUID
        var name: String?
        var description: String?
        var badge: String?
        var column: String?
        var llmPrompt: String?
        var llmNextAction: String?
        var initCommand: String?
        var favourite: Bool?
        var tags: [(key: String, value: String)]?
        var replaceTags: Bool?
    }
    enum OpenError: Error, LocalizedError {
        case failedToOpen(String)
        case invalidURL(String)

        var errorDescription: String? {
            switch self {
            case .failedToOpen(let url):
                return "Failed to open URL: \(url). Is TermQ running?"
            case .invalidURL(let url):
                return "Invalid URL: \(url)"
            }
        }
    }

    /// Open a termq:// URL scheme
    /// - Parameter urlString: The full URL string to open
    /// - Throws: OpenError if the URL couldn't be opened
    @MainActor
    static func open(_ urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            throw OpenError.invalidURL(urlString)
        }

        #if os(macOS)
            let opened = NSWorkspace.shared.open(url)
            if !opened {
                throw OpenError.failedToOpen(urlString)
            }
            // Brief delay to allow GUI to begin processing the URL
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        #else
            throw OpenError.failedToOpen("URL schemes only supported on macOS")
        #endif
    }

    /// Wait for a condition to become true with exponential backoff retry
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (default: 4)
    ///   - initialDelayMs: Initial delay in milliseconds (default: 100)
    ///   - condition: Closure that returns true when the condition is met
    /// - Returns: true if condition was met, false if all attempts exhausted
    static func waitForCondition(
        maxAttempts: Int = 4,
        initialDelayMs: UInt64 = 100,
        condition: () throws -> Bool
    ) async -> Bool {
        var delayMs = initialDelayMs

        for attempt in 1...maxAttempts {
            do {
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
                if try condition() {
                    return true
                }
            } catch {
                // Condition check failed, continue to next attempt
            }

            // Exponential backoff: 100ms, 200ms, 400ms, 800ms
            if attempt < maxAttempts {
                delayMs *= 2
            }
        }

        return false
    }

    /// Build a termq://open URL for creating a terminal
    static func buildOpenURL(params: OpenURLParams) -> String {
        var components = URLComponents()
        components.scheme = "termq"
        components.host = "open"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "id", value: params.cardId.uuidString),
            URLQueryItem(name: "path", value: params.path),
        ]

        if let name = params.name {
            queryItems.append(URLQueryItem(name: "name", value: name))
        }
        if let description = params.description, !description.isEmpty {
            queryItems.append(URLQueryItem(name: "description", value: description))
        }
        if let column = params.column {
            queryItems.append(URLQueryItem(name: "column", value: column))
        }
        if let tags = params.tags {
            for tag in tags {
                queryItems.append(URLQueryItem(name: "tag", value: "\(tag.key)=\(tag.value)"))
            }
        }
        if let llmPrompt = params.llmPrompt, !llmPrompt.isEmpty {
            queryItems.append(URLQueryItem(name: "llmPrompt", value: llmPrompt))
        }
        if let llmNextAction = params.llmNextAction, !llmNextAction.isEmpty {
            queryItems.append(URLQueryItem(name: "llmNextAction", value: llmNextAction))
        }
        if let initCommand = params.initCommand, !initCommand.isEmpty {
            queryItems.append(URLQueryItem(name: "initCommand", value: initCommand))
        }

        components.queryItems = queryItems
        return components.string ?? ""
    }

    /// Build a termq://update URL for updating a terminal
    static func buildUpdateURL(params: UpdateURLParams) -> String {
        var components = URLComponents()
        components.scheme = "termq"
        components.host = "update"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "id", value: params.cardId.uuidString)
        ]

        if let name = params.name {
            queryItems.append(URLQueryItem(name: "name", value: name))
        }
        if let description = params.description {
            queryItems.append(URLQueryItem(name: "description", value: description))
        }
        if let badge = params.badge {
            queryItems.append(URLQueryItem(name: "badge", value: badge))
        }
        if let column = params.column {
            queryItems.append(URLQueryItem(name: "column", value: column))
        }
        if let llmPrompt = params.llmPrompt {
            queryItems.append(URLQueryItem(name: "llmPrompt", value: llmPrompt))
        }
        if let llmNextAction = params.llmNextAction {
            queryItems.append(URLQueryItem(name: "llmNextAction", value: llmNextAction))
        }
        if let initCommand = params.initCommand {
            queryItems.append(URLQueryItem(name: "initCommand", value: initCommand))
        }
        if let favourite = params.favourite {
            queryItems.append(URLQueryItem(name: "favourite", value: favourite ? "true" : "false"))
        }
        if let replaceTags = params.replaceTags, replaceTags {
            queryItems.append(URLQueryItem(name: "replaceTags", value: "true"))
        }
        if let tags = params.tags {
            for tag in tags {
                queryItems.append(URLQueryItem(name: "tag", value: "\(tag.key)=\(tag.value)"))
            }
        }

        components.queryItems = queryItems
        return components.string ?? ""
    }

    /// Build a termq://move URL for moving a terminal
    static func buildMoveURL(cardId: UUID, column: String) -> String {
        var components = URLComponents()
        components.scheme = "termq"
        components.host = "move"
        components.queryItems = [
            URLQueryItem(name: "id", value: cardId.uuidString),
            URLQueryItem(name: "column", value: column),
        ]
        return components.string ?? ""
    }

    /// Build a termq://focus URL for focusing a terminal
    static func buildFocusURL(cardId: UUID) -> String {
        var components = URLComponents()
        components.scheme = "termq"
        components.host = "focus"
        components.queryItems = [
            URLQueryItem(name: "id", value: cardId.uuidString)
        ]
        return components.string ?? ""
    }

    /// Build a termq://delete URL for deleting a terminal
    static func buildDeleteURL(cardId: UUID, permanent: Bool = false) -> String {
        var components = URLComponents()
        components.scheme = "termq"
        components.host = "delete"
        components.queryItems = [
            URLQueryItem(name: "id", value: cardId.uuidString),
            URLQueryItem(name: "permanent", value: permanent ? "true" : "false"),
        ]
        return components.string ?? ""
    }
}
