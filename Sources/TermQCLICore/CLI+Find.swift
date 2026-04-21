import ArgumentParser
import Foundation
import MCPServerLib
import TermQShared

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

    @Option(help: .hidden)
    var dataDirectory: String?

    func run() throws {
        do {
            let dataDirURL = dataDirectory.map { URL(fileURLWithPath: $0) }
            let board = try BoardLoader.loadBoard(dataDirectory: dataDirURL, debug: shouldUseDebugMode(debug))

            var cards = board.activeCards
            var relevanceScores: [UUID: Int] = [:]

            if let queryStr = query, !queryStr.isEmpty {
                let queryWords = CardFilterEngine.normalizeToWords(queryStr)
                guard !queryWords.isEmpty else {
                    JSONHelper.printJSON([TerminalOutput]())
                    return
                }

                cards = cards.filter { card in
                    let score = CardFilterEngine.relevanceScore(card: card, queryWords: queryWords)
                    if score > 0 {
                        relevanceScores[card.id] = score
                        return true
                    }
                    return false
                }
            }

            if let idFilter = id {
                if let uuid = UUID(uuidString: idFilter) {
                    cards = cards.filter { $0.id == uuid }
                } else {
                    JSONHelper.printJSON([TerminalOutput]())
                    return
                }
            }

            if let nameFilter = name {
                let filterLower = nameFilter.lowercased()
                cards = cards.filter { $0.title.lowercased().contains(filterLower) }
            }

            // CLI uses .contains for tag value matching (partial match)
            cards = CardFilterEngine.filterByColumn(cards, column: column, columns: board.columns)
            cards = CardFilterEngine.filterByTag(cards, tagFilter: tag, valueMatch: .contains)
            cards = CardFilterEngine.filterByBadge(cards, badge: badge)
            if favourites { cards = CardFilterEngine.filterFavourites(cards) }

            if !relevanceScores.isEmpty {
                cards = CardFilterEngine.sortByRelevance(cards, scores: relevanceScores)
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
