import Foundation
import TermQCore
import XCTest

@testable import TermQ

/// Closing a stage terminal never kills a harness that still runs; a seat
/// whose harness has exited is closed out and launches afresh next time.
@MainActor
final class WheelhouseSmartCloseTests: XCTestCase {
    func testOnlyAnExitedHarnessIsClosedOut() {
        XCTAssertEqual(WheelhouseStage.closeDecision(harnessRunning: false), .closeOut)
        XCTAssertEqual(WheelhouseStage.closeDecision(harnessRunning: true), .takeOffStage)
        XCTAssertEqual(
            WheelhouseStage.closeDecision(harnessRunning: nil), .takeOffStage, "unknown is treated as running")
    }

    func testShellNamesIncludingLoginShells() {
        for shell in ["zsh", "-zsh", "bash", "-bash", "fish", "sh"] {
            XCTAssertTrue(TerminalSessionManager.isShell(shell), shell)
        }
        for program in ["claude", "node", "ynh", "codex", "vim", ""] {
            XCTAssertFalse(TerminalSessionManager.isShell(program), program)
        }
    }

    func testForegroundGroupAgainstTheShell() {
        XCTAssertEqual(TerminalSessionManager.foregroundIsNotShell(foregroundGroup: 100, shellPid: 100), false)
        XCTAssertEqual(TerminalSessionManager.foregroundIsNotShell(foregroundGroup: 250, shellPid: 100), true)
        XCTAssertNil(TerminalSessionManager.foregroundIsNotShell(foregroundGroup: -1, shellPid: 100))
        XCTAssertNil(TerminalSessionManager.foregroundIsNotShell(foregroundGroup: 100, shellPid: 0))
    }

    func testAnyPaneRunningAProgramCounts() {
        XCTAssertEqual(TerminalSessionManager.panesRunProgram(["zsh"], shellName: "zsh"), false)
        XCTAssertEqual(TerminalSessionManager.panesRunProgram(["zsh", "claude"], shellName: "zsh"), true)
        XCTAssertEqual(TerminalSessionManager.panesRunProgram(["-zsh"], shellName: "zsh"), false)
        XCTAssertEqual(
            TerminalSessionManager.panesRunProgram(["bash"], shellName: "zsh"), true, "a bash wrapper from zsh runs")
        XCTAssertEqual(TerminalSessionManager.panesRunProgram(["bash"], shellName: nil), false)
        XCTAssertNil(TerminalSessionManager.panesRunProgram([], shellName: "zsh"))
    }

    // MARK: - The close-out flow

    private final class FakeProbe: TerminalForegroundProbing {
        var start: Date? = Date()
        var answer: Bool?
        var onProbe: (() -> Void)?
        func sessionStart(for cardId: UUID) -> Date? { start }
        func isForegroundProgramRunning(for card: TerminalCard) async -> Bool? {
            onProbe?()
            return answer
        }
    }

    private func makeStage() throws -> WheelhouseStage {
        WheelhouseStage(
            defaults: try XCTUnwrap(UserDefaults(suiteName: "WheelhouseSmartCloseTests-\(UUID().uuidString)")))
    }

    private func card() -> TerminalCard {
        TerminalCard(title: "Eno", columnId: UUID(), workingDirectory: "/w/ynw")
    }

    func testOnlyTheShellLeftIsClosedOut() async throws {
        let stage = try makeStage()
        let probe = FakeProbe()
        probe.answer = false
        var closed: [UUID] = []
        let target = card()
        let result = await stage.closeOutIfIdle(target, probe: probe) { closed.append($0.id) }
        XCTAssertTrue(result)
        XCTAssertEqual(closed, [target.id])
    }

    func testRunningOrUnknownIsLeftAlone() async throws {
        let stage = try makeStage()
        for answer in [true, nil] as [Bool?] {
            let probe = FakeProbe()
            probe.answer = answer
            var closed = false
            let result = await stage.closeOutIfIdle(card(), probe: probe) { _ in closed = true }
            XCTAssertFalse(result)
            XCTAssertFalse(closed)
        }
    }

    func testASessionReplacedDuringTheProbeIsNotKilled() async throws {
        let stage = try makeStage()
        let probe = FakeProbe()
        probe.answer = false
        probe.onProbe = { probe.start = Date().addingTimeInterval(5) }
        var closed = false
        let result = await stage.closeOutIfIdle(card(), probe: probe) { _ in closed = true }
        XCTAssertFalse(result)
        XCTAssertFalse(closed)
    }

    func testABinnedCardIsNotClosedOutAgain() async throws {
        let stage = try makeStage()
        let probe = FakeProbe()
        probe.answer = false
        let binned = card()
        probe.onProbe = { binned.deletedAt = Date() }
        var closed = false
        let result = await stage.closeOutIfIdle(binned, probe: probe) { _ in closed = true }
        XCTAssertFalse(result)
        XCTAssertFalse(closed)
    }

    func testTmuxProbeTargetsTheCardsSession() {
        let target = card()
        XCTAssertEqual(target.tmuxSessionName, "termq-\(target.id.uuidString.prefix(8).lowercased())")
    }
}
