import Foundation
import XCTest

@testable import TermQShared

/// What stops a Wheelhouse seat from running: not installed, delegates ynh
/// can't read from git, or a failed launch.
final class WheelhouseSeatHealthTests: XCTestCase {
    func testOwnRepoDelegatesAreTheRelativeGitOnesWithAPath() throws {
        let manifest = try JSONSerialization.data(withJSONObject: [
            "name": "capcom",
            "delegates_to": [
                ["git": ".", "path": "harnesses/io"],
                ["git": "./sub", "path": "harnesses/titan"],
                ["git": "../other", "path": "./harnesses/luna"],
                ["git": "github.com/x/y", "path": "harnesses/remote"],
                ["git": "."],
            ],
        ])
        XCTAssertEqual(
            WheelhouseSeatHealth.ownRepoDelegatePaths(manifest: manifest),
            ["harnesses/io", "harnesses/titan", "./harnesses/luna"])
        XCTAssertEqual(WheelhouseSeatHealth.ownRepoDelegatePaths(manifest: Data("{}".utf8)), [])
    }

    func testDelegatesSortIntoNotCommittedAndMissing() {
        let issues = WheelhouseSeatHealth.delegateIssues(
            paths: ["harnesses/io", "harnesses/titan", "harnesses/luna"],
            committed: { $0 == "harnesses/luna" },
            onDisk: { $0 == "harnesses/io" })
        XCTAssertEqual(issues, [.delegatesNotCommitted(["harnesses/io"]), .delegatesMissing(["harnesses/titan"])])
        XCTAssertEqual(WheelhouseSeatHealth.blockingDelegates(in: issues), ["io", "titan"])
    }

    func testOnlyDelegateIssuesBlockAndTheyAreNamedByTheirLastComponent() {
        let issues: [WheelhouseSeatIssue] = [
            .notInstalled, .delegatesNotCommitted(["harnesses/io", "./harnesses/titan/"]),
            .delegatesMissing(["luna"]), .launchFailed("boom"),
        ]
        XCTAssertEqual(WheelhouseSeatHealth.blockingDelegates(in: issues), ["io", "titan", "luna"])
        XCTAssertEqual(WheelhouseSeatHealth.blockingDelegates(in: [.notInstalled, .launchFailed("x")]), [])
    }

    func testLaunchErrorIsTheLastErrorLine() {
        let lines = [
            "Resolving 5 include(s)...",
            "Error: first",
            "  Error: assembling delegates: delegate: path \"harnesses/io\" not found in .",
            "➜  wheelhouse git:(main) ✗",
        ]
        XCTAssertEqual(
            WheelhouseSeatHealth.launchError(fromLines: lines),
            "assembling delegates: delegate: path \"harnesses/io\" not found in .")
        XCTAssertNil(WheelhouseSeatHealth.launchError(fromLines: ["all good"]))
    }

    func testHarnessDirectoryFallsBackToTheConvention() {
        XCTAssertEqual(
            WheelhouseSeatHealth.harnessDirectory(
                root: "/w/b2be", seat: WheelhouseSeat(name: "Io", group: .workers, command: "io")),
            "/w/b2be/harnesses/io")
        XCTAssertEqual(
            WheelhouseSeatHealth.harnessDirectory(
                root: "/w/b2be",
                seat: WheelhouseSeat(name: "Io", group: .workers, command: "io", harness: "seats/io")),
            "/w/b2be/seats/io")
    }

    /// The Capcom case: the desk delegates to a worker that is on disk but not
    /// committed, so ynh can't read it.
    func testAnUncommittedDelegateIsFoundInARealRepository() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-SeatHealth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let manifestDir = root.appendingPathComponent("harnesses/capcom/.agents/harness")
        try FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
        let manifest = try JSONSerialization.data(withJSONObject: [
            "name": "capcom",
            "delegates_to": [
                ["git": ".", "path": "harnesses/io"], ["git": ".", "path": "harnesses/gone"],
            ],
        ])
        try manifest.write(to: manifestDir.appendingPathComponent("plugin.json"))
        try git(["init", "-q"], in: root)
        try git(["add", "."], in: root)
        try git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "desk"], in: root)
        let worker = root.appendingPathComponent("harnesses/io")
        try FileManager.default.createDirectory(at: worker, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: worker.appendingPathComponent("plugin.json"))

        let seat = WheelhouseSeat(name: "Capcom", group: .desk, command: "capcom")
        let issues = await WheelhouseSeatHealth.delegateIssues(root: root.path, seat: seat)
        XCTAssertEqual(issues, [.delegatesNotCommitted(["harnesses/io"]), .delegatesMissing(["harnesses/gone"])])

        try git(["add", "."], in: root)
        try git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "io"], in: root)
        let after = await WheelhouseSeatHealth.delegateIssues(root: root.path, seat: seat)
        XCTAssertEqual(after, [.delegatesMissing(["harnesses/gone"])])
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // A stray GIT_DIR or GIT_INDEX_FILE must not redirect the test repo.
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "))
    }
}
