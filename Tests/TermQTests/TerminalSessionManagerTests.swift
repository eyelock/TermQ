import Foundation
import XCTest

@testable import TermQ
@testable import TermQCore

// MARK: - Mock

/// Minimal `TmuxManagerProtocol` double — never spawns real tmux processes.
@MainActor
final class MockTmuxManager: TmuxManagerProtocol {

    // MARK: Configurable state

    var isAvailable: Bool = false
    var tmuxPath: String? = nil

    // MARK: Call tracking

    private(set) var killSessionCalls: [String] = []
    private(set) var syncMetadataCalls: [(sessionName: String, card: TerminalCardMetadata)] = []
    private(set) var updateMetadataCalls: [String] = []

    // MARK: Error injection

    var killSessionError: Error?

    // MARK: Protocol implementation

    func sessionName(for cardId: UUID) -> String {
        "termq-\(cardId.uuidString.prefix(8).lowercased())"
    }

    func killSession(name: String) async throws {
        killSessionCalls.append(name)
        if let error = killSessionError { throw error }
    }

    func syncMetadataToSession(sessionName: String, card: TerminalCardMetadata) async {
        syncMetadataCalls.append((sessionName: sessionName, card: card))
    }

    func updateSessionMetadata(
        sessionName: String,
        title: String?,
        description: String?,
        tags: [Tag]?,
        llmPrompt: String?,
        llmNextAction: String?,
        badge: String?,
        columnId: UUID?,
        isFavourite: Bool?
    ) async {
        updateMetadataCalls.append(sessionName)
    }
}

// MARK: - Tests

@MainActor
final class TerminalSessionManagerTests: XCTestCase {

    // MARK: - effectiveBackend — direct card

    func testEffectiveBackendDirectCardReturnsDirect() {
        let mock = MockTmuxManager()
        let manager = TerminalSessionManager(tmuxManager: mock)
        let card = TerminalCard(columnId: UUID(), backend: .direct)

        XCTAssertEqual(manager.effectiveBackend(for: card), .direct)
    }

    func testEffectiveBackendDirectCardReturnsDirect_WhenTmuxAvailable() {
        let mock = MockTmuxManager()
        mock.isAvailable = true
        let manager = TerminalSessionManager(tmuxManager: mock)
        let card = TerminalCard(columnId: UUID(), backend: .direct)

        XCTAssertEqual(manager.effectiveBackend(for: card), .direct)
    }

    // MARK: - effectiveBackend — tmux fallback

    func testEffectiveBackendTmuxAttachFallsBackToDirectWhenTmuxUnavailable() {
        let mock = MockTmuxManager()
        mock.isAvailable = false
        let manager = TerminalSessionManager(tmuxManager: mock)
        let card = TerminalCard(columnId: UUID(), backend: .tmuxAttach)

        XCTAssertEqual(manager.effectiveBackend(for: card), .direct)
    }

    func testEffectiveBackendTmuxControlFallsBackToDirectWhenTmuxUnavailable() {
        let mock = MockTmuxManager()
        mock.isAvailable = false
        let manager = TerminalSessionManager(tmuxManager: mock)
        let card = TerminalCard(columnId: UUID(), backend: .tmuxControl)

        XCTAssertEqual(manager.effectiveBackend(for: card), .direct)
    }

    func testEffectiveBackendTmuxAttachReturnsTmuxAttachWhenAvailable() {
        let mock = MockTmuxManager()
        mock.isAvailable = true
        let manager = TerminalSessionManager(tmuxManager: mock)
        let card = TerminalCard(columnId: UUID(), backend: .tmuxAttach)

        XCTAssertEqual(manager.effectiveBackend(for: card), .tmuxAttach)
    }

    func testEffectiveBackendTmuxControlReturnsTmuxControlWhenAvailable() {
        let mock = MockTmuxManager()
        mock.isAvailable = true
        let manager = TerminalSessionManager(tmuxManager: mock)
        let card = TerminalCard(columnId: UUID(), backend: .tmuxControl)

        XCTAssertEqual(manager.effectiveBackend(for: card), .tmuxControl)
    }

    // MARK: - Session state — hasActiveSession

    func testHasActiveSessionReturnsFalseForUnknownCard() {
        let manager = TerminalSessionManager(tmuxManager: MockTmuxManager())

        XCTAssertFalse(manager.hasActiveSession(for: UUID()))
    }

    // MARK: - Session state — sessionExists

    func testSessionExistsReturnsFalseForUnknownCard() {
        let manager = TerminalSessionManager(tmuxManager: MockTmuxManager())

        XCTAssertFalse(manager.sessionExists(for: UUID()))
    }

    // MARK: - Session state — hasPendingRestart

    func testHasPendingRestartReturnsFalseForUnknownCard() {
        let manager = TerminalSessionManager(tmuxManager: MockTmuxManager())

        XCTAssertFalse(manager.hasPendingRestart(for: UUID()))
    }

    // MARK: - isProcessing

    func testIsProcessingReturnsFalseForUnknownCard() {
        let manager = TerminalSessionManager(tmuxManager: MockTmuxManager())

        XCTAssertFalse(manager.isProcessing(cardId: UUID()))
    }

    // MARK: - processingCardIds

    func testProcessingCardIdsIsEmptyWithNoSessions() {
        let manager = TerminalSessionManager(tmuxManager: MockTmuxManager())

        XCTAssertTrue(manager.processingCardIds().isEmpty)
    }

    // MARK: - activeSessionCardIds

    func testActiveSessionCardIdsIsEmptyWithNoSessions() {
        let manager = TerminalSessionManager(tmuxManager: MockTmuxManager())

        XCTAssertTrue(manager.activeSessionCardIds().isEmpty)
    }

    // MARK: - getBackend

    func testGetBackendReturnsNilForUnknownCard() {
        let manager = TerminalSessionManager(tmuxManager: MockTmuxManager())

        XCTAssertNil(manager.getBackend(for: UUID()))
    }

    // MARK: - getCurrentDirectory

    func testGetCurrentDirectoryReturnsNilForUnknownCard() {
        let manager = TerminalSessionManager(tmuxManager: MockTmuxManager())

        XCTAssertNil(manager.getCurrentDirectory(for: UUID()))
    }

    // MARK: - getTerminalView

    func testGetTerminalViewReturnsNilForUnknownCard() {
        let manager = TerminalSessionManager(tmuxManager: MockTmuxManager())

        XCTAssertNil(manager.getTerminalView(for: UUID()))
    }

    // MARK: - DI — shared instance still works

    func testSharedInstanceIsReachable() {
        // Regression guard: the shared singleton must remain accessible.
        XCTAssertNotNil(TerminalSessionManager.shared)
    }

    // MARK: - Mock wiring

    func testMockSessionNameMatchesTmuxManagerFormat() {
        let mock = MockTmuxManager()
        let id = UUID()
        let expected = "termq-\(id.uuidString.prefix(8).lowercased())"

        XCTAssertEqual(mock.sessionName(for: id), expected)
    }
}
