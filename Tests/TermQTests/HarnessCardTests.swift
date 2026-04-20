import Foundation
import XCTest

@testable import TermQCore

final class HarnessCardTests: XCTestCase {

    // MARK: - Harness tag matching (mirrors launchHarness dedup predicate)

    private func makeHarnessCard(
        harnessName: String,
        workingDirectory: String,
        columnId: UUID = UUID()
    ) -> TerminalCard {
        let card = TerminalCard(
            title: harnessName,
            tags: [
                Tag(key: "source", value: "harness"),
                Tag(key: "harness", value: harnessName),
            ],
            columnId: columnId,
            workingDirectory: workingDirectory
        )
        return card
    }

    private func matchesHarness(_ card: TerminalCard, name: String, workingDirectory: String) -> Bool {
        card.workingDirectory == workingDirectory
            && card.tags.contains(where: { $0.key == "harness" && $0.value == name })
    }

    func testMatchesWhenHarnessNameAndDirectoryMatch() {
        let card = makeHarnessCard(harnessName: "termq-dev", workingDirectory: "/projects/termq")
        XCTAssertTrue(matchesHarness(card, name: "termq-dev", workingDirectory: "/projects/termq"))
    }

    func testNoMatchWhenDirectoryDiffers() {
        let card = makeHarnessCard(harnessName: "termq-dev", workingDirectory: "/projects/termq")
        XCTAssertFalse(matchesHarness(card, name: "termq-dev", workingDirectory: "/projects/other"))
    }

    func testNoMatchWhenHarnessNameDiffers() {
        let card = makeHarnessCard(harnessName: "termq-dev", workingDirectory: "/projects/termq")
        XCTAssertFalse(matchesHarness(card, name: "other-harness", workingDirectory: "/projects/termq"))
    }

    func testNoMatchWhenNoHarnessTag() {
        let card = TerminalCard(
            title: "plain",
            tags: [Tag(key: "source", value: "harness")],
            columnId: UUID(),
            workingDirectory: "/projects/termq"
        )
        XCTAssertFalse(matchesHarness(card, name: "termq-dev", workingDirectory: "/projects/termq"))
    }

    func testNoMatchForTransientQuickTerminal() {
        let card = TerminalCard(title: "quick", tags: [], columnId: UUID(), workingDirectory: "/projects/termq")
        card.isTransient = true
        XCTAssertFalse(matchesHarness(card, name: "termq-dev", workingDirectory: "/projects/termq"))
    }

    // MARK: - Harness card is not transient (board-persisted)

    func testHarnessCardIsNotTransientByDefault() {
        let card = makeHarnessCard(harnessName: "termq-dev", workingDirectory: "/projects/termq")
        XCTAssertFalse(card.isTransient)
    }

    func testHarnessCardAppearsInBoardCards() {
        let column = Column(name: "Work", orderIndex: 0)
        let card = makeHarnessCard(harnessName: "termq-dev", workingDirectory: "/projects/termq", columnId: column.id)
        let board = Board(columns: [column], cards: [card])

        XCTAssertEqual(board.cards.count, 1)
        XCTAssertEqual(board.cards.first?.tags.first(where: { $0.key == "harness" })?.value, "termq-dev")
    }
}
