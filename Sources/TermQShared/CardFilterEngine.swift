import Foundation

/// Pure, stateless filtering and sorting operations for Card collections.
/// Shared between MCP (ToolHandlers) and CLI (CLI+Find) to eliminate duplication.
public enum CardFilterEngine {

    // MARK: - Tag Filter Errors

    /// Errors that can surface from `filterByTag`. Surfaced to the user — CLI exits non-zero,
    /// MCP returns `isError: true`. Never silently fall back to literal match when the user
    /// asked for regex; that would mask a typo and return surprising results.
    public enum TagFilterError: Error, CustomStringConvertible, Sendable {
        case invalidRegex(pattern: String, message: String)

        public var description: String {
            switch self {
            case .invalidRegex(let pattern, let message):
                return "Invalid regex in tag filter '\(pattern)': \(message)"
            }
        }
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

    /// Filters cards by tag. Accepts:
    /// - `"key"`              — key-only literal match
    /// - `"key=value"`        — exact literal match on both key and value (case-insensitive)
    /// - `"key=re:pattern"`   — key matches literally; value matches regex pattern
    /// - `"re:pattern"`       — whole `key=value` string (or `key` alone) matches regex pattern
    ///
    /// Literal is the default to avoid the regex-metacharacter footgun (a tag like
    /// `project=v1.2` would otherwise also match `project=v1X2` because `.` is a metachar).
    /// Returns `cards` unchanged when `tagFilter` is nil. Throws `TagFilterError.invalidRegex`
    /// if a `re:`-prefixed pattern fails to compile.
    public static func filterByTag(
        _ cards: [Card],
        tagFilter: String?
    ) throws -> [Card] {
        guard let tagFilter else { return cards }

        // Whole-pattern regex: `re:...`
        if let pattern = dropPrefix("re:", from: tagFilter) {
            let regex = try compileRegex(pattern, original: tagFilter)
            return cards.filter { card in
                card.tags.contains { tag in
                    let fullTag = tag.value.isEmpty ? tag.key : "\(tag.key)=\(tag.value)"
                    return regex.matches(fullTag)
                }
            }
        }

        if tagFilter.contains("=") {
            let parts = tagFilter.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return cards }
            let key = String(parts[0]).lowercased()
            let rawValue = String(parts[1])

            // Value-position regex: `key=re:...`
            if let valuePattern = dropPrefix("re:", from: rawValue) {
                let regex = try compileRegex(valuePattern, original: tagFilter)
                return cards.filter { card in
                    card.tags.contains { tag in
                        tag.key.lowercased() == key && regex.matches(tag.value)
                    }
                }
            }

            // Literal exact match
            let value = rawValue.lowercased()
            return cards.filter { card in
                card.tags.contains { $0.key.lowercased() == key && $0.value.lowercased() == value }
            }
        } else {
            // Key-only literal match
            let key = tagFilter.lowercased()
            return cards.filter { card in
                card.tags.contains { $0.key.lowercased() == key }
            }
        }
    }

    // MARK: - Tag Filter Helpers

    private static func dropPrefix(_ prefix: String, from string: String) -> String? {
        string.hasPrefix(prefix) ? String(string.dropFirst(prefix.count)) : nil
    }

    private static func compileRegex(_ pattern: String, original: String) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            throw TagFilterError.invalidRegex(pattern: original, message: error.localizedDescription)
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

extension NSRegularExpression {
    fileprivate func matches(_ string: String) -> Bool {
        let range = NSRange(string.startIndex..., in: string)
        return firstMatch(in: string, options: [], range: range) != nil
    }
}
