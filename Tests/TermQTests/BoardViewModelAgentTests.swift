import Foundation
import XCTest

@testable import TermQ
@testable import TermQCore

/// Verifies BoardViewModel.createAgentCard creates cards configured as agent
/// sessions and respects column-selection rules.
final class BoardViewModelAgentTests: XCTestCase {

    private var tempBoardURL: URL!
    private var viewModel: BoardViewModel?

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardViewModelAgentTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempBoardURL = tempDir.appendingPathComponent("board.json")
        let seedBoard =
            #"{"columns":[{"id":"00000000-0000-0000-0000-000000000001","name":"To Do","orderIndex":0}],"cards":[]}"#
        try? Data(seedBoard.utf8).write(to: tempBoardURL)
    }

    override func tearDown() {
        viewModel = nil
        if let tempDir = tempBoardURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    @MainActor func testCreateAgentCard_populatesAgentConfig() {
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        let card = viewModel?.createAgentCard(
            harnessId: "eyelock/x/coding-agent",
            title: "coding-agent",
            description: "Drives a build/lint/test loop"
        )

        XCTAssertNotNil(card)
        XCTAssertEqual(card?.title, "coding-agent")
        XCTAssertEqual(card?.description, "Drives a build/lint/test loop")
        XCTAssertNotNil(card?.agentConfig)
        XCTAssertEqual(card?.agentConfig?.harness, "eyelock/x/coding-agent")
        XCTAssertEqual(card?.agentConfig?.status, .idle)
        XCTAssertEqual(card?.agentConfig?.mode, .plan)
    }

    @MainActor func testCreateAgentCard_appendsToBoard() {
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        let initialCount = viewModel?.board.cards.count ?? 0

        _ = viewModel?.createAgentCard(harnessId: "x", title: "x")

        XCTAssertEqual(viewModel?.board.cards.count, initialCount + 1)
    }

    @MainActor func testCreateAgentCard_emptyDescriptionDefault() {
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        let card = viewModel?.createAgentCard(harnessId: "x", title: "y")
        XCTAssertEqual(card?.description, "")
    }

    @MainActor func testCreateAgentCard_returnsNilWhenNoColumns() {
        let emptyBoard = #"{"columns":[],"cards":[]}"#
        try? Data(emptyBoard.utf8).write(to: tempBoardURL)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))

        let card = viewModel?.createAgentCard(harnessId: "x", title: "y")
        XCTAssertNil(card)
    }
}
