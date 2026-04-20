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

            if let columnFilter = column {
                let filterLower = columnFilter.lowercased()
                let matchingColumnIds = board.columns
                    .filter { $0.name.lowercased().contains(filterLower) }
                    .map { $0.id }
                cards = cards.filter { matchingColumnIds.contains($0.columnId) }
            }

            if let tagFilter = tag {
                if tagFilter.contains("=") {
                    let parts = tagFilter.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        let key = String(parts[0]).lowercased()
                        let value = String(parts[1]).lowercased()
                        cards = cards.filter { card in
                            card.tags.contains { $0.key.lowercased() == key && $0.value.lowercased().contains(value) }
                        }
                    }
                } else {
                    let key = tagFilter.lowercased()
                    cards = cards.filter { card in
                        card.tags.contains { $0.key.lowercased() == key }
                    }
                }
            }

            if let badgeFilter = badge {
                let filterLower = badgeFilter.lowercased()
                cards = cards.filter { card in
                    card.badge.lowercased().contains(filterLower)
                }
            }

            if favourites {
                cards = cards.filter { $0.isFavourite }
            }

            if !relevanceScores.isEmpty {
                cards.sort { card1, card2 in
                    let score1 = relevanceScores[card1.id] ?? 0
                    let score2 = relevanceScores[card2.id] ?? 0
                    return score1 > score2
                }
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

    // MARK: - Smart Search Helpers

    func normalizeToWords(_ text: String) -> Swift.Set<String> {
        let normalized =
            text
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ".", with: " ")

        let words =
            normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }

        return Swift.Set(words)
    }

    func calculateRelevanceScore(card: Card, queryWords: Swift.Set<String>) -> Int {
        var score = 0

        let titleWords = normalizeToWords(card.title)
        let descriptionWords = normalizeToWords(card.description)
        let pathWords = normalizeToWords(card.workingDirectory)
        var tagWords = Swift.Set<String>()
        for tag in card.tags {
            tagWords.formUnion(normalizeToWords(tag.key))
            tagWords.formUnion(normalizeToWords(tag.value))
        }

        for queryWord in queryWords {
            if titleWords.contains(queryWord) { score += 10 }
            if descriptionWords.contains(queryWord) { score += 5 }
            if pathWords.contains(queryWord) { score += 3 }
            if tagWords.contains(queryWord) { score += 7 }

            if titleWords.contains(where: { $0.hasPrefix(queryWord) || queryWord.hasPrefix($0) }) { score += 4 }
            if descriptionWords.contains(where: { $0.hasPrefix(queryWord) || queryWord.hasPrefix($0) }) { score += 2 }
            if pathWords.contains(where: { $0.hasPrefix(queryWord) || queryWord.hasPrefix($0) }) { score += 1 }
            if tagWords.contains(where: { $0.hasPrefix(queryWord) || queryWord.hasPrefix($0) }) { score += 3 }
        }

        return score
    }
}
