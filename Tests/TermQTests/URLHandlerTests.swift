import Foundation
import XCTest

@testable import TermQ
@testable import TermQCore

// MARK: - MockBoardViewModel

@MainActor
final class MockBoardViewModel: BoardViewModelProtocol {

    // MARK: State

    var board: Board

    // MARK: Call tracking

    private(set) var cardLookups: [UUID] = []
    private(set) var moveCardCalls: [(card: TerminalCard, column: Column)] = []
    private(set) var updateCardCalls: [TerminalCard] = []
    private(set) var selectCardCalls: [TerminalCard] = []
    private(set) var deleteCardCalls: [TerminalCard] = []
    private(set) var permanentlyDeleteCardCalls: [TerminalCard] = []
    private(set) var toggleFavouriteCalls: [TerminalCard] = []

    // MARK: Stub configuration

    /// Cards returned by `card(for:)`. Key = card UUID.
    var stubbedCards: [UUID: TerminalCard] = [:]

    // MARK: Init

    init(board: Board = Board(columns: [], cards: [])) {
        self.board = board
    }

    // MARK: BoardViewModelProtocol

    func card(for id: UUID) -> TerminalCard? {
        cardLookups.append(id)
        return stubbedCards[id]
    }

    func moveCard(_ card: TerminalCard, to column: Column) {
        moveCardCalls.append((card, column))
    }

    func updateCard(_ card: TerminalCard) {
        updateCardCalls.append(card)
    }

    func selectCard(_ card: TerminalCard) {
        selectCardCalls.append(card)
    }

    func deleteCard(_ card: TerminalCard) {
        deleteCardCalls.append(card)
    }

    func permanentlyDeleteCard(_ card: TerminalCard) {
        permanentlyDeleteCardCalls.append(card)
    }

    func toggleFavourite(_ card: TerminalCard) {
        toggleFavouriteCalls.append(card)
    }
}

// MARK: - Helpers

extension URLHandlerTests {

    // Build a URL with the given host and query items.
    fileprivate func makeURL(host: String, items: [URLQueryItem] = []) -> URL {
        var components = URLComponents()
        components.scheme = "termq"
        components.host = host
        if !items.isEmpty {
            components.queryItems = items
        }
        return components.url!
    }

    fileprivate func qi(_ name: String, _ value: String) -> URLQueryItem {
        URLQueryItem(name: name, value: value)
    }

    // A Column with a known name for move/update tests.
    fileprivate func makeColumn(name: String = "Done") -> Column {
        Column(name: name, orderIndex: 0)
    }

    // A TerminalCard placed in a given column.
    fileprivate func makeCard(id: UUID = UUID(), columnId: UUID = UUID()) -> TerminalCard {
        TerminalCard(title: "Test Terminal", columnId: columnId)
    }
}

// MARK: - URLHandlerTests

@MainActor
final class URLHandlerTests: XCTestCase {

    // MARK: - handleURL — routing

    func testHandleURL_nonTermqScheme_isIgnored() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)

        handler.handleURL(URL(string: "https://example.com/open")!)

        XCTAssertTrue(mock.cardLookups.isEmpty, "Non-termq URLs must not reach the board")
    }

    func testHandleURL_unknownHost_isIgnored() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)

        handler.handleURL(URL(string: "termq://unknown")!)

        XCTAssertTrue(mock.cardLookups.isEmpty)
    }

    // MARK: - handleOpen

    func testHandleOpen_setsPathInPendingTerminal() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(host: "open", items: [qi("path", "/tmp/workspace")])

        handler.handleURL(url)

        XCTAssertEqual(handler.pendingTerminal?.path, "/tmp/workspace")
    }

    func testHandleOpen_optionalFieldsMissing_pendingTerminalHasNilOptionals() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(host: "open")

        handler.handleURL(url)

        XCTAssertNil(handler.pendingTerminal?.name)
        XCTAssertNil(handler.pendingTerminal?.description)
        XCTAssertNil(handler.pendingTerminal?.column)
        XCTAssertNil(handler.pendingTerminal?.llmPrompt)
        XCTAssertNil(handler.pendingTerminal?.llmNextAction)
        XCTAssertNil(handler.pendingTerminal?.initCommand)
    }

    func testHandleOpen_allOptionalFields_populatedInPendingTerminal() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "open",
            items: [
                qi("path", "/tmp/project"),
                qi("name", "My Terminal"),
                qi("description", "A description"),
                qi("column", "In Progress"),
                qi("llmPrompt", "You are a helpful assistant"),
                qi("llmNextAction", "run tests"),
                qi("initCommand", "zsh"),
            ])

        handler.handleURL(url)

        let pending = handler.pendingTerminal
        XCTAssertEqual(pending?.path, "/tmp/project")
        XCTAssertEqual(pending?.name, "My Terminal")
        XCTAssertEqual(pending?.description, "A description")
        XCTAssertEqual(pending?.column, "In Progress")
        XCTAssertEqual(pending?.llmPrompt, "You are a helpful assistant")
        XCTAssertEqual(pending?.llmNextAction, "run tests")
        XCTAssertEqual(pending?.initCommand, "zsh")
    }

    func testHandleOpen_tagsParsedCorrectly() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "open",
            items: [
                URLQueryItem(name: "tag", value: "env=prod"),
                URLQueryItem(name: "tag", value: "project=TermQ"),
            ])

        handler.handleURL(url)

        let tags = handler.pendingTerminal?.tags ?? []
        XCTAssertEqual(tags.count, 2)
        XCTAssertTrue(tags.contains { $0.key == "env" && $0.value == "prod" })
        XCTAssertTrue(tags.contains { $0.key == "project" && $0.value == "TermQ" })
    }

    func testHandleOpen_tagMissingEquals_isDropped() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "open",
            items: [
                URLQueryItem(name: "tag", value: "no-equals-sign")
            ])

        handler.handleURL(url)

        XCTAssertTrue(handler.pendingTerminal?.tags.isEmpty ?? false)
    }

    // MARK: - handleUpdate

    func testHandleUpdate_missingId_doesNothing() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(host: "update", items: [qi("name", "New Name")])

        handler.handleURL(url)

        XCTAssertTrue(mock.updateCardCalls.isEmpty)
    }

    func testHandleUpdate_unknownCardId_doesNothing() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let id = UUID()
        let url = makeURL(host: "update", items: [qi("id", id.uuidString), qi("name", "X")])

        handler.handleURL(url)

        XCTAssertTrue(mock.updateCardCalls.isEmpty)
    }

    func testHandleUpdate_knownCard_updatesTitle() {
        let mock = MockBoardViewModel()
        let card = makeCard()
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "update",
            items: [
                qi("id", card.id.uuidString),
                qi("name", "Renamed"),
            ])
        // Disable LLM confirmation guard so the update flows through
        UserDefaults.standard.set(false, forKey: "confirmExternalLLMModifications")
        defer { UserDefaults.standard.removeObject(forKey: "confirmExternalLLMModifications") }

        handler.handleURL(url)

        XCTAssertEqual(card.title, "Renamed")
        XCTAssertEqual(mock.updateCardCalls.count, 1)
    }

    func testHandleUpdate_knownCard_updatesDescription() {
        let mock = MockBoardViewModel()
        let card = makeCard()
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "update",
            items: [
                qi("id", card.id.uuidString),
                qi("description", "New desc"),
            ])
        UserDefaults.standard.set(false, forKey: "confirmExternalLLMModifications")
        defer { UserDefaults.standard.removeObject(forKey: "confirmExternalLLMModifications") }

        handler.handleURL(url)

        XCTAssertEqual(card.description, "New desc")
    }

    func testHandleUpdate_knownCard_updatesBadge() {
        let mock = MockBoardViewModel()
        let card = makeCard()
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "update",
            items: [
                qi("id", card.id.uuidString),
                qi("badge", "🔥"),
            ])
        UserDefaults.standard.set(false, forKey: "confirmExternalLLMModifications")
        defer { UserDefaults.standard.removeObject(forKey: "confirmExternalLLMModifications") }

        handler.handleURL(url)

        XCTAssertEqual(card.badge, "🔥")
    }

    func testHandleUpdate_toggleFavouriteOn_callsToggle() {
        let mock = MockBoardViewModel()
        let card = makeCard()
        card.isFavourite = false
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "update",
            items: [
                qi("id", card.id.uuidString),
                qi("favourite", "true"),
            ])
        UserDefaults.standard.set(false, forKey: "confirmExternalLLMModifications")
        defer { UserDefaults.standard.removeObject(forKey: "confirmExternalLLMModifications") }

        handler.handleURL(url)

        XCTAssertEqual(mock.toggleFavouriteCalls.count, 1)
    }

    func testHandleUpdate_favouriteAlreadyMatches_doesNotToggle() {
        let mock = MockBoardViewModel()
        let card = makeCard()
        card.isFavourite = true
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "update",
            items: [
                qi("id", card.id.uuidString),
                qi("favourite", "true"),  // Already true — no-op
            ])
        UserDefaults.standard.set(false, forKey: "confirmExternalLLMModifications")
        defer { UserDefaults.standard.removeObject(forKey: "confirmExternalLLMModifications") }

        handler.handleURL(url)

        XCTAssertTrue(mock.toggleFavouriteCalls.isEmpty)
    }

    func testHandleUpdate_moveToKnownColumn_callsMoveCard() {
        let column = makeColumn(name: "Done")
        let board = Board(columns: [column], cards: [])
        let mock = MockBoardViewModel(board: board)
        let card = makeCard()
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "update",
            items: [
                qi("id", card.id.uuidString),
                qi("column", "done"),  // Case-insensitive
            ])
        UserDefaults.standard.set(false, forKey: "confirmExternalLLMModifications")
        defer { UserDefaults.standard.removeObject(forKey: "confirmExternalLLMModifications") }

        handler.handleURL(url)

        XCTAssertEqual(mock.moveCardCalls.count, 1)
        XCTAssertEqual(mock.moveCardCalls.first?.column.id, column.id)
    }

    func testHandleUpdate_moveToUnknownColumn_doesNotCallMoveCard() {
        let board = Board(columns: [], cards: [])
        let mock = MockBoardViewModel(board: board)
        let card = makeCard()
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "update",
            items: [
                qi("id", card.id.uuidString),
                qi("column", "nonexistent"),
            ])
        UserDefaults.standard.set(false, forKey: "confirmExternalLLMModifications")
        defer { UserDefaults.standard.removeObject(forKey: "confirmExternalLLMModifications") }

        handler.handleURL(url)

        XCTAssertTrue(mock.moveCardCalls.isEmpty)
    }

    func testHandleUpdate_replaceTagsTrue_replacesTags() {
        let mock = MockBoardViewModel()
        let card = makeCard()
        card.tags = [Tag(key: "old", value: "value")]
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let items: [URLQueryItem] = [
            qi("id", card.id.uuidString),
            qi("replaceTags", "true"),
            URLQueryItem(name: "tag", value: "new=tag"),
        ]
        _ = items  // silence unused warning
        let url = makeURL(host: "update", items: items)
        UserDefaults.standard.set(false, forKey: "confirmExternalLLMModifications")
        defer { UserDefaults.standard.removeObject(forKey: "confirmExternalLLMModifications") }

        handler.handleURL(url)

        XCTAssertEqual(card.tags.count, 1)
        XCTAssertEqual(card.tags.first?.key, "new")
    }

    func testHandleUpdate_replaceTagsTrueNoNewTags_clearsTags() {
        let mock = MockBoardViewModel()
        let card = makeCard()
        card.tags = [Tag(key: "existing", value: "tag")]
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "update",
            items: [
                qi("id", card.id.uuidString),
                qi("replaceTags", "true"),
            ])
        UserDefaults.standard.set(false, forKey: "confirmExternalLLMModifications")
        defer { UserDefaults.standard.removeObject(forKey: "confirmExternalLLMModifications") }

        handler.handleURL(url)

        XCTAssertTrue(card.tags.isEmpty)
    }

    func testHandleUpdate_appendTags_appendsToExisting() {
        let mock = MockBoardViewModel()
        let card = makeCard()
        card.tags = [Tag(key: "existing", value: "yes")]
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "update",
            items: [
                qi("id", card.id.uuidString),
                URLQueryItem(name: "tag", value: "extra=tag"),
            ])
        UserDefaults.standard.set(false, forKey: "confirmExternalLLMModifications")
        defer { UserDefaults.standard.removeObject(forKey: "confirmExternalLLMModifications") }

        handler.handleURL(url)

        XCTAssertEqual(card.tags.count, 2)
    }

    // MARK: - handleMove

    func testHandleMove_missingId_doesNothing() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(host: "move", items: [qi("column", "Done")])

        handler.handleURL(url)

        XCTAssertTrue(mock.moveCardCalls.isEmpty)
    }

    func testHandleMove_missingColumn_doesNothing() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(host: "move", items: [qi("id", UUID().uuidString)])

        handler.handleURL(url)

        XCTAssertTrue(mock.moveCardCalls.isEmpty)
    }

    func testHandleMove_unknownCard_doesNothing() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "move",
            items: [
                qi("id", UUID().uuidString),
                qi("column", "Done"),
            ])

        handler.handleURL(url)

        XCTAssertTrue(mock.moveCardCalls.isEmpty)
    }

    func testHandleMove_knownCardAndColumn_callsMoveCard() {
        let column = makeColumn(name: "In Review")
        let board = Board(columns: [column], cards: [])
        let mock = MockBoardViewModel(board: board)
        let card = makeCard()
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "move",
            items: [
                qi("id", card.id.uuidString),
                qi("column", "In Review"),
            ])

        handler.handleURL(url)

        XCTAssertEqual(mock.moveCardCalls.count, 1)
        XCTAssertEqual(mock.moveCardCalls.first?.card.id, card.id)
        XCTAssertEqual(mock.moveCardCalls.first?.column.id, column.id)
    }

    func testHandleMove_columnNameCaseInsensitive() {
        let column = makeColumn(name: "Done")
        let board = Board(columns: [column], cards: [])
        let mock = MockBoardViewModel(board: board)
        let card = makeCard()
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "move",
            items: [
                qi("id", card.id.uuidString),
                qi("column", "DONE"),
            ])

        handler.handleURL(url)

        XCTAssertEqual(mock.moveCardCalls.count, 1)
    }

    func testHandleMove_unknownColumn_doesNotCallMoveCard() {
        let board = Board(columns: [], cards: [])
        let mock = MockBoardViewModel(board: board)
        let card = makeCard()
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "move",
            items: [
                qi("id", card.id.uuidString),
                qi("column", "nonexistent"),
            ])

        handler.handleURL(url)

        XCTAssertTrue(mock.moveCardCalls.isEmpty)
    }

    // MARK: - handleFocus

    func testHandleFocus_missingId_doesNothing() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(host: "focus")

        handler.handleURL(url)

        XCTAssertTrue(mock.selectCardCalls.isEmpty)
    }

    func testHandleFocus_unknownCard_doesNothing() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(host: "focus", items: [qi("id", UUID().uuidString)])

        handler.handleURL(url)

        XCTAssertTrue(mock.selectCardCalls.isEmpty)
    }

    func testHandleFocus_knownCard_callsSelectCard() {
        let mock = MockBoardViewModel()
        let card = makeCard()
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(host: "focus", items: [qi("id", card.id.uuidString)])

        handler.handleURL(url)

        XCTAssertEqual(mock.selectCardCalls.count, 1)
        XCTAssertEqual(mock.selectCardCalls.first?.id, card.id)
    }

    // MARK: - handleDelete

    func testHandleDelete_missingId_doesNothing() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(host: "delete")

        handler.handleURL(url)

        XCTAssertTrue(mock.deleteCardCalls.isEmpty)
        XCTAssertTrue(mock.permanentlyDeleteCardCalls.isEmpty)
    }

    func testHandleDelete_unknownCard_doesNothing() {
        let mock = MockBoardViewModel()
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(host: "delete", items: [qi("id", UUID().uuidString)])

        handler.handleURL(url)

        XCTAssertTrue(mock.deleteCardCalls.isEmpty)
        XCTAssertTrue(mock.permanentlyDeleteCardCalls.isEmpty)
    }

    func testHandleDelete_softDelete_callsDeleteCard() {
        let mock = MockBoardViewModel()
        let card = makeCard()
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(host: "delete", items: [qi("id", card.id.uuidString)])

        handler.handleURL(url)

        XCTAssertEqual(mock.deleteCardCalls.count, 1)
        XCTAssertTrue(mock.permanentlyDeleteCardCalls.isEmpty)
    }

    func testHandleDelete_permanentDelete_callsPermanentlyDeleteCard() {
        let mock = MockBoardViewModel()
        let card = makeCard()
        mock.stubbedCards[card.id] = card
        let handler = URLHandler(boardViewModel: mock)
        let url = makeURL(
            host: "delete",
            items: [
                qi("id", card.id.uuidString),
                qi("permanent", "true"),
            ])

        handler.handleURL(url)

        XCTAssertTrue(mock.deleteCardCalls.isEmpty)
        XCTAssertEqual(mock.permanentlyDeleteCardCalls.count, 1)
        XCTAssertEqual(mock.permanentlyDeleteCardCalls.first?.id, card.id)
    }
}
