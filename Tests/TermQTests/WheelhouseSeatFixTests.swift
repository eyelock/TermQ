import Foundation
import TermQCore
import TermQShared
import XCTest

@testable import TermQ

/// The "action required" fix panel's text, and noticing failed launches.
@MainActor
final class WheelhouseSeatFixTests: XCTestCase {
    func testNamesAreTheDelegatesLastComponents() {
        XCTAssertEqual(WheelhouseSeatFixSheet.names(["harnesses/io", "harnesses/titan"]), "io, titan")
    }

    func testCommitCommandCommitsOnlyTheDelegatesAndQuotesEverything() {
        XCTAssertEqual(
            WheelhouseSeatFixSheet.commitCommand(root: "/w/my wheelhouse", paths: ["harnesses/io"]),
            "git -C '/w/my wheelhouse' add -- 'harnesses/io' && "
                + "git -C '/w/my wheelhouse' commit -m 'Add io' -- 'harnesses/io'")
        let tricky = WheelhouseSeatFixSheet.commitCommand(root: "/w/it's", paths: ["-x/o'k"])
        XCTAssertTrue(tricky.hasPrefix("git -C '/w/it'\\''s' add -- '-x/o'\\''k'"), tricky)
        XCTAssertTrue(tricky.contains("commit -m 'Add o'\\''k' --"), tricky)
    }

    func testTooltipListsEachIssueThenHowToFix() {
        let seat = WheelhouseSeat(name: "Capcom", group: .desk, command: "capcom")
        let tooltip = WheelhouseSeatFixSheet.tooltip(
            for: [.notInstalled, .delegatesNotCommitted(["harnesses/io"])], seat: seat)
        let lines = tooltip.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines.last, Strings.Wheelhouse.actionRequiredHelp)
    }

    // MARK: - Failed launches

    func testAnExitedHarnessRecordsYnhsErrorARunningOneClearsAndUnknownLeavesIt() {
        let lines = { ["Resolving…", "Error: harness \"local/io\": harness not found", "➜ b2be"] }
        XCTAssertEqual(
            WheelhouseStore.launchCheck(running: false, lines: lines),
            .record("harness \"local/io\": harness not found"))
        XCTAssertEqual(WheelhouseStore.launchCheck(running: true, lines: lines), .record(nil))
        XCTAssertEqual(WheelhouseStore.launchCheck(running: nil, lines: lines), .unknown)
        XCTAssertEqual(
            WheelhouseStore.launchCheck(running: false) { ["➜ b2be"] }, .record(nil),
            "a shell idle without an error is no failure")
    }

    func testRecordingAndClearingALaunchFailure() {
        let store = WheelhouseStore()
        let wheelhouse = Wheelhouse(root: "/w/b2be", roster: WheelhouseRoster(seats: []))
        let seat = WheelhouseSeat(name: "Io", group: .workers, command: "io")
        store.recordLaunchFailure("harness not found", for: seat, in: wheelhouse)
        XCTAssertEqual(store.issues(for: seat, in: wheelhouse, installed: true), [.launchFailed("harness not found")])
        store.recordLaunchFailure(nil, for: seat, in: wheelhouse)
        XCTAssertEqual(store.issues(for: seat, in: wheelhouse, installed: true), [])
    }

    // MARK: - Checking launches

    private final class FakeProbe: TerminalForegroundProbing {
        var starts: [UUID: Date] = [:]
        var running: Bool?
        var onProbe: (() -> Void)?
        func sessionStart(for cardId: UUID) -> Date? { starts[cardId] }
        func isForegroundProgramRunning(for card: TerminalCard) async -> Bool? {
            onProbe?()
            return running
        }
    }

    private let b2be = Wheelhouse(
        root: "/w/b2be", roster: WheelhouseRoster(seats: [WheelhouseSeat(name: "Io", group: .workers, command: "io")]))
    private var io: WheelhouseSeat { b2be.seats[0] }

    private func ioCard() -> TerminalCard {
        TerminalCard(
            title: "Io",
            tags: WheelhouseCardMatcher.tags(wheelhouseRoot: "/w/b2be", seatCommand: "io").map {
                Tag(key: $0.key, value: $0.value)
            },
            columnId: UUID(), workingDirectory: "/w/b2be")
    }

    private let failed = ["Error: harness \"local/io\": harness not found"]

    func testAYoungSessionWithoutItsHarnessRecordsTheError() async {
        let store = WheelhouseStore(wheelhouses: [b2be])
        let card = ioCard()
        let probe = FakeProbe()
        probe.starts[card.id] = Date().addingTimeInterval(-20)
        probe.running = false
        await store.checkLaunches(cards: [card], probe: probe) { _ in self.failed }
        XCTAssertEqual(
            store.issues(for: io, in: b2be, installed: true), [.launchFailed("harness \"local/io\": harness not found")]
        )

        probe.running = true
        await store.checkLaunches(cards: [card], probe: probe) { _ in self.failed }
        XCTAssertEqual(store.issues(for: io, in: b2be, installed: true), [], "a running harness clears it")
    }

    func testAnOldSessionsScrollbackIsNotJudged() async {
        let store = WheelhouseStore(wheelhouses: [b2be])
        let card = ioCard()
        let probe = FakeProbe()
        probe.starts[card.id] = Date().addingTimeInterval(-WheelhouseStore.launchWindow - 5)
        probe.running = false
        await store.checkLaunches(cards: [card], probe: probe) { _ in self.failed }
        XCTAssertEqual(store.issues(for: io, in: b2be, installed: true), [])
    }

    func testAFailureEndsWithItsTerminal() async {
        let store = WheelhouseStore(wheelhouses: [b2be])
        store.recordLaunchFailure("boom", for: io, in: b2be)
        await store.checkLaunches(cards: [], probe: FakeProbe())
        XCTAssertEqual(store.issues(for: io, in: b2be, installed: true), [])
    }

    func testASessionReplacedDuringTheProbeIsNotJudged() async {
        let store = WheelhouseStore(wheelhouses: [b2be])
        let card = ioCard()
        let probe = FakeProbe()
        probe.starts[card.id] = Date().addingTimeInterval(-20)
        probe.running = false
        probe.onProbe = { probe.starts[card.id] = Date() }
        await store.checkLaunches(cards: [card], probe: probe) { _ in self.failed }
        XCTAssertEqual(store.issues(for: io, in: b2be, installed: true), [])
    }

    func testLongErrorsAreCut() {
        let long = "Error: " + String(repeating: "x", count: 500)
        XCTAssertEqual(
            WheelhouseSeatHealth.launchError(fromLines: [long])?.count, WheelhouseSeatHealth.maxErrorLength + 1)
    }
}
