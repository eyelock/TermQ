import XCTest

@testable import TermQShared

final class CardFilterEngineTests: XCTestCase {

    // MARK: - Test Data Helpers

    private let colA = Column(id: UUID(), name: "To Do", orderIndex: 0)
    private let colB = Column(id: UUID(), name: "In Progress", orderIndex: 1)
    private let colC = Column(id: UUID(), name: "Done", orderIndex: 2)

    private func makeCard(
        title: String = "Card",
        description: String = "",
        tags: [Tag] = [],
        columnId: UUID,
        orderIndex: Int = 0,
        workingDirectory: String = "",
        isFavourite: Bool = false,
        badge: String = ""
    ) -> Card {
        Card(
            title: title,
            description: description,
            tags: tags,
            columnId: columnId,
            orderIndex: orderIndex,
            workingDirectory: workingDirectory,
            isFavourite: isFavourite,
            badge: badge
        )
    }

    // MARK: - filterByColumn

    func testFilterByColumnNilPassesAll() {
        let cards = [makeCard(columnId: colA.id), makeCard(columnId: colB.id)]
        let result = CardFilterEngine.filterByColumn(cards, column: nil, columns: [colA, colB])
        XCTAssertEqual(result.count, 2)
    }

    func testFilterByColumnExactMatch() {
        let cards = [makeCard(columnId: colA.id), makeCard(columnId: colB.id)]
        let result = CardFilterEngine.filterByColumn(cards, column: "To Do", columns: [colA, colB])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].columnId, colA.id)
    }

    func testFilterByColumnCaseInsensitive() {
        let cards = [makeCard(columnId: colA.id), makeCard(columnId: colB.id)]
        let result = CardFilterEngine.filterByColumn(cards, column: "to do", columns: [colA, colB])
        XCTAssertEqual(result.count, 1)
    }

    func testFilterByColumnPartialMatch() {
        let cards = [makeCard(columnId: colA.id), makeCard(columnId: colB.id)]
        let result = CardFilterEngine.filterByColumn(cards, column: "Progress", columns: [colA, colB])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].columnId, colB.id)
    }

    func testFilterByColumnNoMatch() {
        let cards = [makeCard(columnId: colA.id)]
        let result = CardFilterEngine.filterByColumn(cards, column: "Backlog", columns: [colA])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - filterByTag — literal-by-default, opt-in `re:` regex

    func testFilterByTagNilPassesAll() throws {
        let cards = [makeCard(tags: [Tag(key: "env", value: "prod")], columnId: colA.id)]
        let result = try CardFilterEngine.filterByTag(cards, tagFilter: nil)
        XCTAssertEqual(result.count, 1)
    }

    /// T7.5 — Key-only match returns any card with that tag key.
    func testFilterByTagKeyOnly() throws {
        let matching = makeCard(tags: [Tag(key: "env", value: "prod")], columnId: colA.id)
        let nonMatching = makeCard(tags: [Tag(key: "team", value: "platform")], columnId: colA.id)
        let result = try CardFilterEngine.filterByTag([matching, nonMatching], tagFilter: "env")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].tags.first?.key, "env")
    }

    func testFilterByTagKeyOnlyCaseInsensitive() throws {
        let card = makeCard(tags: [Tag(key: "ENV", value: "prod")], columnId: colA.id)
        let result = try CardFilterEngine.filterByTag([card], tagFilter: "env")
        XCTAssertEqual(result.count, 1)
    }

    func testFilterByTagKeyNoMatch() throws {
        let card = makeCard(tags: [Tag(key: "team", value: "platform")], columnId: colA.id)
        let result = try CardFilterEngine.filterByTag([card], tagFilter: "env")
        XCTAssertTrue(result.isEmpty)
    }

    /// Literal key=value match (default) — case-insensitive exact comparison.
    func testFilterByTagKeyValueLiteralMatch() throws {
        let matching = makeCard(tags: [Tag(key: "env", value: "prod")], columnId: colA.id)
        let wrong = makeCard(tags: [Tag(key: "env", value: "staging")], columnId: colA.id)
        let result = try CardFilterEngine.filterByTag([matching, wrong], tagFilter: "env=prod")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].tags.first?.value, "prod")
    }

    /// Literal value does NOT do partial match — `env=prod` must not match `env=production`.
    func testFilterByTagKeyValueLiteralRejectsPartial() throws {
        let card = makeCard(tags: [Tag(key: "env", value: "production")], columnId: colA.id)
        let result = try CardFilterEngine.filterByTag([card], tagFilter: "env=prod")
        XCTAssertTrue(result.isEmpty)
    }

    /// T7.4 — Regression test for the rejected regex-by-default design.
    /// `project=v1.2` matches ONLY the v1.2 card, NOT a v1X2 card (where `.` would be a regex wildcard).
    func testFilterByTagLiteralDotIsNotWildcard() throws {
        let exact = makeCard(tags: [Tag(key: "project", value: "v1.2")], columnId: colA.id)
        let wouldMatchUnderRegex = makeCard(tags: [Tag(key: "project", value: "v1X2")], columnId: colA.id)
        let result = try CardFilterEngine.filterByTag([exact, wouldMatchUnderRegex], tagFilter: "project=v1.2")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].tags.first?.value, "v1.2")
    }

    /// T7.6 — Opt-in regex via `re:` prefix on value.
    func testFilterByTagValueRegex() throws {
        let stale = makeCard(tags: [Tag(key: "staleness", value: "stale")], columnId: colA.id)
        let ageing = makeCard(tags: [Tag(key: "staleness", value: "ageing")], columnId: colA.id)
        let fresh = makeCard(tags: [Tag(key: "staleness", value: "fresh")], columnId: colA.id)
        let result = try CardFilterEngine.filterByTag([stale, ageing, fresh], tagFilter: "staleness=re:(stale|ageing)")
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains { $0.tags.first?.value == "fresh" })
    }

    /// T7.7 — Opt-in regex via `re:` prefix on the whole pattern (matches full `key=value`).
    func testFilterByTagWholePatternRegex() throws {
        let a = makeCard(tags: [Tag(key: "project", value: "org/repo-a")], columnId: colA.id)
        let b = makeCard(tags: [Tag(key: "project", value: "org/repo-b")], columnId: colA.id)
        let other = makeCard(tags: [Tag(key: "project", value: "external/x")], columnId: colA.id)
        let result = try CardFilterEngine.filterByTag([a, b, other], tagFilter: "re:project=org/.+")
        XCTAssertEqual(result.count, 2)
    }

    /// T7.8 — Invalid regex inside `re:` prefix surfaces an error (not silent literal fallback).
    func testFilterByTagInvalidRegexThrows() {
        let card = makeCard(tags: [Tag(key: "staleness", value: "stale")], columnId: colA.id)
        XCTAssertThrowsError(try CardFilterEngine.filterByTag([card], tagFilter: "staleness=re:[invalid")) { error in
            guard case CardFilterEngine.TagFilterError.invalidRegex = error else {
                XCTFail("Expected TagFilterError.invalidRegex, got \(error)")
                return
            }
        }
    }

    // MARK: - filterByBadge

    func testFilterByBadgeNilPassesAll() {
        let cards = [makeCard(columnId: colA.id, badge: "urgent")]
        let result = CardFilterEngine.filterByBadge(cards, badge: nil)
        XCTAssertEqual(result.count, 1)
    }

    func testFilterByBadgePartialMatch() {
        let matching = makeCard(columnId: colA.id, badge: "urgent,important")
        let nonMatching = makeCard(columnId: colA.id, badge: "low-priority")
        let result = CardFilterEngine.filterByBadge([matching, nonMatching], badge: "urgent")
        XCTAssertEqual(result.count, 1)
    }

    func testFilterByBadgeCaseInsensitive() {
        let card = makeCard(columnId: colA.id, badge: "URGENT")
        let result = CardFilterEngine.filterByBadge([card], badge: "urgent")
        XCTAssertEqual(result.count, 1)
    }

    func testFilterByBadgeNoMatch() {
        let card = makeCard(columnId: colA.id, badge: "low")
        let result = CardFilterEngine.filterByBadge([card], badge: "urgent")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - filterFavourites

    func testFilterFavouritesKeepsOnlyFavourites() {
        let fav = makeCard(columnId: colA.id, isFavourite: true)
        let notFav = makeCard(columnId: colA.id, isFavourite: false)
        let result = CardFilterEngine.filterFavourites([fav, notFav])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isFavourite)
    }

    // MARK: - sortByColumnThenOrder

    func testSortByColumnThenOrderColumnFirst() {
        let cardInC = makeCard(title: "C", columnId: colC.id, orderIndex: 0)
        let cardInA = makeCard(title: "A", columnId: colA.id, orderIndex: 0)
        let cardInB = makeCard(title: "B", columnId: colB.id, orderIndex: 0)
        let sorted = CardFilterEngine.sortByColumnThenOrder(
            [cardInC, cardInA, cardInB], columns: [colA, colB, colC])
        XCTAssertEqual(sorted[0].title, "A")
        XCTAssertEqual(sorted[1].title, "B")
        XCTAssertEqual(sorted[2].title, "C")
    }

    func testSortByColumnThenOrderWithinColumn() {
        let card1 = makeCard(title: "Second", columnId: colA.id, orderIndex: 1)
        let card0 = makeCard(title: "First", columnId: colA.id, orderIndex: 0)
        let sorted = CardFilterEngine.sortByColumnThenOrder([card1, card0], columns: [colA])
        XCTAssertEqual(sorted[0].title, "First")
        XCTAssertEqual(sorted[1].title, "Second")
    }

    // MARK: - sortByRelevance

    func testSortByRelevanceHighestFirst() {
        let id1 = UUID()
        let id2 = UUID()
        let card1 = Card(id: id1, title: "Low", columnId: colA.id)
        let card2 = Card(id: id2, title: "High", columnId: colA.id)
        let scores = [id1: 3, id2: 10]
        let sorted = CardFilterEngine.sortByRelevance([card1, card2], scores: scores)
        XCTAssertEqual(sorted[0].title, "High")
        XCTAssertEqual(sorted[1].title, "Low")
    }

    func testSortByRelevanceMissingScoreLast() {
        let id1 = UUID()
        let id2 = UUID()
        let scored = Card(id: id1, title: "Scored", columnId: colA.id)
        let unscored = Card(id: id2, title: "Unscored", columnId: colA.id)
        let scores = [id1: 5]
        let sorted = CardFilterEngine.sortByRelevance([unscored, scored], scores: scores)
        XCTAssertEqual(sorted[0].title, "Scored")
    }

    // MARK: - normalizeToWords

    func testNormalizeToWordsLowercases() {
        let words = CardFilterEngine.normalizeToWords("Hello World")
        XCTAssertTrue(words.contains("hello"))
        XCTAssertTrue(words.contains("world"))
    }

    func testNormalizeToWordsSplitsOnSeparators() {
        let words = CardFilterEngine.normalizeToWords("my-project/src_file:tag")
        XCTAssertTrue(words.contains("my"))
        XCTAssertTrue(words.contains("project"))
        XCTAssertTrue(words.contains("src"))
        XCTAssertTrue(words.contains("file"))
        XCTAssertTrue(words.contains("tag"))
    }

    func testNormalizeToWordsFiltersShortWords() {
        let words = CardFilterEngine.normalizeToWords("a be cat")
        XCTAssertFalse(words.contains("a"))  // 1 char — filtered out
        XCTAssertTrue(words.contains("be"))  // 2 chars — kept (minimum length is 2)
        XCTAssertTrue(words.contains("cat"))
    }

    func testNormalizeToWordsEmptyStringReturnsEmpty() {
        let words = CardFilterEngine.normalizeToWords("")
        XCTAssertTrue(words.isEmpty)
    }

    // MARK: - relevanceScore

    func testRelevanceScoreTitleMatchHighest() {
        let card = makeCard(
            title: "termq project", description: "some tool", columnId: colA.id)
        let query = CardFilterEngine.normalizeToWords("termq")
        let score = CardFilterEngine.relevanceScore(card: card, queryWords: query)
        XCTAssertGreaterThan(score, 0)
    }

    func testRelevanceScoreNoMatchReturnsZero() {
        let card = makeCard(title: "Something Else", columnId: colA.id)
        let query = CardFilterEngine.normalizeToWords("termq")
        let score = CardFilterEngine.relevanceScore(card: card, queryWords: query)
        XCTAssertEqual(score, 0)
    }

    func testRelevanceScoreTitleOutranksDescription() {
        let titleCard = makeCard(title: "termq tool", columnId: colA.id)
        let descCard = makeCard(title: "Other", description: "uses termq", columnId: colA.id)
        let query = CardFilterEngine.normalizeToWords("termq")
        let titleScore = CardFilterEngine.relevanceScore(card: titleCard, queryWords: query)
        let descScore = CardFilterEngine.relevanceScore(card: descCard, queryWords: query)
        XCTAssertGreaterThan(titleScore, descScore)
    }
}
