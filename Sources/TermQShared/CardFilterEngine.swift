import Foundation

/// Pure, stateless filtering and sorting operations for Card collections.
/// Shared between MCP (ToolHandlers) and CLI (CLI+Find) to eliminate duplication.
public enum CardFilterEngine {

    // MARK: - Tag Value Matching

    /// Controls how tag values are matched. MCP uses exact match; CLI uses partial.
    public enum TagValueMatch: Sendable {
        case exact
        case contains
    }

    // MARK: - Filtering

    /// Filters cards to those in columns whose name contains `column` (case-insensitive).
    /// Returns `cards` unchanged when `column` is nil.
    public static func filterByColumn(
        _ cards: [Card],
        column: String?,
        columns: [Column]
    ) -> [Card] {
        guard let column else { return cards }
        let filterLower = column.lowercased()
        let matchingIds =
            columns
            .filter { $0.name.lowercased().contains(filterLower) }
            .map { $0.id }
        return cards.filter { matchingIds.contains($0.columnId) }
    }

    /// Filters cards by tag. Accepts `"key"` or `"key=value"` format.
    /// Returns `cards` unchanged when `tagFilter` is nil.
    public static func filterByTag(
        _ cards: [Card],
        tagFilter: String?,
        valueMatch: TagValueMatch = .exact
    ) -> [Card] {
        guard let tagFilter else { return cards }
        if tagFilter.contains("=") {
            let parts = tagFilter.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return cards }
            let key = String(parts[0]).lowercased()
            let value = String(parts[1]).lowercased()
            return cards.filter { card in
                card.tags.contains { tag in
                    let keyMatch = tag.key.lowercased() == key
                    switch valueMatch {
                    case .exact: return keyMatch && tag.value.lowercased() == value
                    case .contains: return keyMatch && tag.value.lowercased().contains(value)
                    }
                }
            }
        } else {
            let key = tagFilter.lowercased()
            return cards.filter { card in
                card.tags.contains { $0.key.lowercased() == key }
            }
        }
    }

    /// Filters cards whose badge contains `badge` (case-insensitive, partial match).
    /// Returns `cards` unchanged when `badge` is nil.
    public static func filterByBadge(_ cards: [Card], badge: String?) -> [Card] {
        guard let badge else { return cards }
        let filterLower = badge.lowercased()
        return cards.filter { $0.badge.lowercased().contains(filterLower) }
    }

    /// Filters cards to favourites only.
    public static func filterFavourites(_ cards: [Card]) -> [Card] {
        cards.filter { $0.isFavourite }
    }

    // MARK: - Sorting

    /// Sorts cards by column orderIndex, then by card orderIndex within each column.
    public static func sortByColumnThenOrder(_ cards: [Card], columns: [Column]) -> [Card] {
        cards.sorted { lhs, rhs in
            let lhsColOrder = columns.first { $0.id == lhs.columnId }?.orderIndex ?? 0
            let rhsColOrder = columns.first { $0.id == rhs.columnId }?.orderIndex ?? 0
            if lhsColOrder != rhsColOrder { return lhsColOrder < rhsColOrder }
            return lhs.orderIndex < rhs.orderIndex
        }
    }

    /// Sorts cards by pre-computed relevance scores (highest first).
    /// Cards absent from `scores` sort last.
    public static func sortByRelevance(_ cards: [Card], scores: [UUID: Int]) -> [Card] {
        cards.sorted { (scores[$0.id] ?? 0) > (scores[$1.id] ?? 0) }
    }

    // MARK: - Smart Search

    /// Normalises text to a set of searchable words: lowercase, splits on separators,
    /// removes words shorter than 2 characters.
    public static func normalizeToWords(_ text: String) -> Set<String> {
        let separators: [(String, String)] = [
            ("-", " "), ("_", " "), (":", " "), ("/", " "), (".", " "),
        ]
        let normalized = separators.reduce(text.lowercased()) { str, pair in
            str.replacingOccurrences(of: pair.0, with: pair.1)
        }
        return Set(
            normalized
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count >= 2 }
        )
    }

    /// Scores a card's relevance to a set of query words.
    /// Returns 0 when no words match (card should be excluded from results).
    public static func relevanceScore(card: Card, queryWords: Set<String>) -> Int {
        var score = 0
        let titleWords = normalizeToWords(card.title)
        let descriptionWords = normalizeToWords(card.description)
        let pathWords = normalizeToWords(card.workingDirectory)
        var tagWords = Set<String>()
        for tag in card.tags {
            tagWords.formUnion(normalizeToWords(tag.key))
            tagWords.formUnion(normalizeToWords(tag.value))
        }

        for word in queryWords {
            if titleWords.contains(word) { score += 10 }
            if descriptionWords.contains(word) { score += 5 }
            if pathWords.contains(word) { score += 3 }
            if tagWords.contains(word) { score += 7 }

            if titleWords.contains(where: { $0.hasPrefix(word) || word.hasPrefix($0) }) { score += 4 }
            if descriptionWords.contains(where: { $0.hasPrefix(word) || word.hasPrefix($0) }) { score += 2 }
            if pathWords.contains(where: { $0.hasPrefix(word) || word.hasPrefix($0) }) { score += 1 }
            if tagWords.contains(where: { $0.hasPrefix(word) || word.hasPrefix($0) }) { score += 3 }
        }

        return score
    }
}
