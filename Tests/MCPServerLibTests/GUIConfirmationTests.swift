import Foundation
import TermQShared
import XCTest

@testable import MCPServerLib

final class GUIConfirmationTests: XCTestCase {

    // MARK: - Fixtures

    private let todo = Column(id: UUID(), name: "To Do", orderIndex: 0)
    private let inProgress = Column(id: UUID(), name: "In Progress", orderIndex: 1)
    private let done = Column(id: UUID(), name: "Done", orderIndex: 2)

    private func board(cards: [Card]) -> Board {
        Board(columns: [todo, inProgress, done], cards: cards)
    }

    private func card(
        id: UUID = UUID(),
        title: String = "Card",
        in column: Column,
        tags: [Tag] = [],
        isFavourite: Bool = false,
        badge: String = "",
        description: String = "",
        llmPrompt: String = "",
        llmNextAction: String = "",
        deletedAt: Date? = nil
    ) -> Card {
        Card(
            id: id,
            title: title,
            description: description,
            tags: tags,
            columnId: column.id,
            isFavourite: isFavourite,
            badge: badge,
            llmPrompt: llmPrompt,
            llmNextAction: llmNextAction,
            deletedAt: deletedAt
        )
    }

    // MARK: - Column Resolution

    func testColumnResolvesByExactName() {
        let resolved = GUIConfirmation.column(named: "In Progress", in: board(cards: []))
        XCTAssertEqual(resolved?.id, inProgress.id)
    }

    func testColumnResolutionIsCaseInsensitive() {
        let resolved = GUIConfirmation.column(named: "in progress", in: board(cards: []))
        XCTAssertEqual(resolved?.id, inProgress.id)
    }

    func testColumnUnknownNameResolvesToNil() {
        XCTAssertNil(GUIConfirmation.column(named: "Archived", in: board(cards: [])))
    }

    /// `BoardWriter.moveCard` and the app's URL handler both match on name only. Accepting an id
    /// here would let a request succeed on one path and fail on the other — the exact divergence
    /// this helper exists to close.
    func testColumnDoesNotResolveById() {
        XCTAssertNil(GUIConfirmation.column(named: inProgress.id.uuidString, in: board(cards: [])))
    }

    func testColumnNamesAreReturnedInBoardOrder() {
        let scrambled = Board(columns: [done, todo, inProgress], cards: [])
        XCTAssertEqual(GUIConfirmation.columnNames(in: scrambled), ["To Do", "In Progress", "Done"])
    }

    // MARK: - cardIsInColumn

    func testCardIsInColumnWhenPresent() {
        let subject = card(in: inProgress)
        XCTAssertTrue(
            GUIConfirmation.cardIsInColumn(
                board(cards: [subject]), cardId: subject.id.uuidString, column: "In Progress"))
    }

    func testCardIsInColumnIsCaseInsensitive() {
        let subject = card(in: inProgress)
        XCTAssertTrue(
            GUIConfirmation.cardIsInColumn(
                board(cards: [subject]), cardId: subject.id.uuidString, column: "IN PROGRESS"))
    }

    func testCardIsInColumnFalseForDifferentColumn() {
        let subject = card(in: todo)
        XCTAssertFalse(
            GUIConfirmation.cardIsInColumn(
                board(cards: [subject]), cardId: subject.id.uuidString, column: "Done"))
    }

    func testCardIsInColumnFalseWhenCardMissing() {
        XCTAssertFalse(
            GUIConfirmation.cardIsInColumn(
                board(cards: []), cardId: UUID().uuidString, column: "To Do"))
    }

    /// A binned card is not in any column, however the move was reported.
    func testCardIsInColumnFalseWhenCardIsBinned() {
        let subject = card(in: todo, deletedAt: Date())
        XCTAssertFalse(
            GUIConfirmation.cardIsInColumn(
                board(cards: [subject]), cardId: subject.id.uuidString, column: "To Do"))
    }

    // MARK: - cardIsAbsent

    func testCardIsAbsentFalseWhenCardIsOnBoard() {
        let subject = card(in: todo)
        XCTAssertFalse(
            GUIConfirmation.cardIsAbsent(board(cards: [subject]), cardId: subject.id.uuidString))
    }

    /// A soft delete counts as gone — `delete` without `permanent` only bins the card.
    func testCardIsAbsentTrueWhenCardIsBinned() {
        let subject = card(in: todo, deletedAt: Date())
        XCTAssertTrue(
            GUIConfirmation.cardIsAbsent(board(cards: [subject]), cardId: subject.id.uuidString))
    }

    func testCardIsAbsentTrueWhenCardNeverExisted() {
        XCTAssertTrue(GUIConfirmation.cardIsAbsent(board(cards: []), cardId: UUID().uuidString))
    }

    // MARK: - cardMatches

    func testCardMatchesIgnoresUnrequestedFields() {
        let subject = card(title: "Untouched", in: todo)
        XCTAssertTrue(
            GUIConfirmation.cardMatches(
                board(cards: [subject]), cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate()))
    }

    func testCardMatchesFalseWhenCardMissing() {
        XCTAssertFalse(
            GUIConfirmation.cardMatches(
                board(cards: []), cardId: UUID().uuidString,
                expected: GUIConfirmation.ExpectedUpdate()))
    }

    func testCardMatchesTitle() {
        let subject = card(title: "Renamed", in: todo)
        let boardValue = board(cards: [subject])
        XCTAssertTrue(
            GUIConfirmation.cardMatches(
                boardValue, cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(title: "Renamed")))
        XCTAssertFalse(
            GUIConfirmation.cardMatches(
                boardValue, cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(title: "Something Else")))
    }

    func testCardMatchesScalarFields() {
        let subject = card(
            in: todo, isFavourite: true, badge: "wip", description: "desc",
            llmPrompt: "prompt", llmNextAction: "next")
        let boardValue = board(cards: [subject])
        let expected = GUIConfirmation.ExpectedUpdate(
            description: "desc", badge: "wip", llmPrompt: "prompt",
            llmNextAction: "next", isFavourite: true)
        XCTAssertTrue(
            GUIConfirmation.cardMatches(boardValue, cardId: subject.id.uuidString, expected: expected))
    }

    /// The case that made a denied confirmation prompt look like a successful update.
    func testCardMatchesFalseWhenLLMFieldNeverApplied() {
        let subject = card(in: todo, llmNextAction: "")
        XCTAssertFalse(
            GUIConfirmation.cardMatches(
                board(cards: [subject]), cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(llmNextAction: "run the tests")))
    }

    func testCardMatchesFalseWhenFavouriteUnchanged() {
        let subject = card(in: todo, isFavourite: false)
        XCTAssertFalse(
            GUIConfirmation.cardMatches(
                board(cards: [subject]), cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(isFavourite: true)))
    }

    func testCardMatchesColumn() {
        let subject = card(in: done)
        let boardValue = board(cards: [subject])
        XCTAssertTrue(
            GUIConfirmation.cardMatches(
                boardValue, cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(column: "done")))
        XCTAssertFalse(
            GUIConfirmation.cardMatches(
                boardValue, cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(column: "To Do")))
    }

    // MARK: - cardMatches: Tags

    /// Tags mint a fresh `id` per instance, so a tag that did land must still compare equal to the
    /// one that was asked for.
    func testRequiredTagsCompareByKeyAndValueNotIdentity() {
        let subject = card(in: todo, tags: [Tag(key: "vendor", value: "claude")])
        XCTAssertTrue(
            GUIConfirmation.cardMatches(
                board(cards: [subject]), cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(
                    requiredTags: [Tag(key: "vendor", value: "claude")])))
    }

    func testRequiredTagsAllowAdditionalTagsOnCard() {
        let subject = card(
            in: todo, tags: [Tag(key: "vendor", value: "claude"), Tag(key: "shell", value: "zsh")])
        XCTAssertTrue(
            GUIConfirmation.cardMatches(
                board(cards: [subject]), cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(
                    requiredTags: [Tag(key: "vendor", value: "claude")])))
    }

    func testRequiredTagsFalseWhenTagNeverLanded() {
        let subject = card(in: todo, tags: [Tag(key: "shell", value: "zsh")])
        XCTAssertFalse(
            GUIConfirmation.cardMatches(
                board(cards: [subject]), cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(
                    requiredTags: [Tag(key: "vendor", value: "claude")])))
    }

    func testRequiredTagsFalseWhenValueDiffers() {
        let subject = card(in: todo, tags: [Tag(key: "vendor", value: "codex")])
        XCTAssertFalse(
            GUIConfirmation.cardMatches(
                board(cards: [subject]), cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(
                    requiredTags: [Tag(key: "vendor", value: "claude")])))
    }

    func testExactTagsRejectLeftoverTags() {
        let subject = card(
            in: todo, tags: [Tag(key: "vendor", value: "claude"), Tag(key: "shell", value: "zsh")])
        XCTAssertFalse(
            GUIConfirmation.cardMatches(
                board(cards: [subject]), cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(
                    exactTags: [Tag(key: "vendor", value: "claude")])))
    }

    func testExactTagsMatchWhenListIsIdentical() {
        let subject = card(
            in: todo, tags: [Tag(key: "vendor", value: "claude"), Tag(key: "shell", value: "zsh")])
        XCTAssertTrue(
            GUIConfirmation.cardMatches(
                board(cards: [subject]), cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(
                    exactTags: [Tag(key: "shell", value: "zsh"), Tag(key: "vendor", value: "claude")])))
    }

    /// `--replace-tags` with no tags clears the list; confirmation must hold out for the clear.
    func testExactTagsEmptyRequiresClearedList() {
        let subject = card(in: todo, tags: [Tag(key: "vendor", value: "claude")])
        XCTAssertFalse(
            GUIConfirmation.cardMatches(
                board(cards: [subject]), cardId: subject.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(exactTags: [])))

        let cleared = card(id: subject.id, in: todo, tags: [])
        XCTAssertTrue(
            GUIConfirmation.cardMatches(
                board(cards: [cleared]), cardId: cleared.id.uuidString,
                expected: GUIConfirmation.ExpectedUpdate(exactTags: [])))
    }

    // MARK: - hasObservableFields

    func testHasObservableFieldsFalseForEmptyUpdate() {
        XCTAssertFalse(GUIConfirmation.ExpectedUpdate().hasObservableFields)
    }

    func testHasObservableFieldsTrueForEachField() {
        XCTAssertTrue(GUIConfirmation.ExpectedUpdate(title: "x").hasObservableFields)
        XCTAssertTrue(GUIConfirmation.ExpectedUpdate(description: "x").hasObservableFields)
        XCTAssertTrue(GUIConfirmation.ExpectedUpdate(badge: "x").hasObservableFields)
        XCTAssertTrue(GUIConfirmation.ExpectedUpdate(llmPrompt: "x").hasObservableFields)
        XCTAssertTrue(GUIConfirmation.ExpectedUpdate(llmNextAction: "x").hasObservableFields)
        XCTAssertTrue(GUIConfirmation.ExpectedUpdate(isFavourite: false).hasObservableFields)
        XCTAssertTrue(GUIConfirmation.ExpectedUpdate(column: "x").hasObservableFields)
        XCTAssertTrue(GUIConfirmation.ExpectedUpdate(requiredTags: []).hasObservableFields)
        XCTAssertTrue(GUIConfirmation.ExpectedUpdate(exactTags: []).hasObservableFields)
    }
}
