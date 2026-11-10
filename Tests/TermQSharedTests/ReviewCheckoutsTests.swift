import XCTest

@testable import TermQShared

final class ReviewCheckoutsTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/Users/me/.termq/focus-worktrees")

    func testDirectoryNameKeepsTheExistingFormat() {
        XCTAssertEqual(
            ReviewCheckouts.directoryName(
                repoKey: "github.com--eyelock--termq", headRefName: "Feat/Some_Thing", prNumber: 81),
            "termq-focus--github.com--eyelock--termq--feat-some-thing--81")
    }

    func testPRNumberIsReadFromTheFolderName() {
        XCTAssertEqual(ReviewCheckouts.prNumber(fromDirectoryName: "termq-focus--github.com--o--r--feat--81"), 81)
        XCTAssertNil(ReviewCheckouts.prNumber(fromDirectoryName: "termq-focus--github.com--o--r--feat"))
        XCTAssertNil(ReviewCheckouts.prNumber(fromDirectoryName: "pr-81"))
    }

    func testBelongsMatchesTheWholeRepoKey() {
        XCTAssertTrue(ReviewCheckouts.belongs(directoryName: "termq-focus--gh--o--r--b--1", toRepoKey: "gh--o--r"))
        XCTAssertFalse(ReviewCheckouts.belongs(directoryName: "termq-focus--gh--o--rx--b--1", toRepoKey: "gh--o--r"))
    }

    func testOnlyReviewFoldersDirectlyInTheBaseAreManaged() {
        XCTAssertTrue(ReviewCheckouts.isManaged(path: base.path + "/termq-focus--a--1", base: base))
        XCTAssertFalse(ReviewCheckouts.isManaged(path: base.path + "/other", base: base))
        XCTAssertFalse(ReviewCheckouts.isManaged(path: base.path + "/termq-focus--a--1/sub", base: base))
        XCTAssertFalse(ReviewCheckouts.isManaged(path: base.path + "/../termq-focus--a--1", base: base))
        XCTAssertFalse(ReviewCheckouts.isManaged(path: base.path, base: base))
    }

    func testRepoKeyFromSSHAndHTTPS() {
        XCTAssertEqual(
            ReviewCheckouts.repoKey(fromRemoteURL: "git@github.com:eyelock/TermQ.git"), "github.com--eyelock--TermQ")
        XCTAssertEqual(
            ReviewCheckouts.repoKey(fromRemoteURL: "https://github.com/eyelock/TermQ/"), "github.com--eyelock--TermQ")
        XCTAssertNil(ReviewCheckouts.repoKey(fromRemoteURL: ""))
    }

    func testAMissingPRIsClosedOnlyWhenTheListIsComplete() {
        XCTAssertEqual(ReviewCheckouts.state(of: 1, openNumbers: [1], listIsComplete: false), .open)
        XCTAssertEqual(ReviewCheckouts.state(of: 2, openNumbers: [1], listIsComplete: true), .closed)
        XCTAssertEqual(ReviewCheckouts.state(of: 2, openNumbers: [1], listIsComplete: false), .unknown)
        XCTAssertEqual(ReviewCheckouts.state(of: nil, openNumbers: [1], listIsComplete: true), .unknown)
    }

    func testOpenTerminalMatchesTheFolderAndBelowButNotSiblings() {
        let path = base.path + "/termq-focus--a--1"
        XCTAssertTrue(ReviewCheckouts.hasOpenTerminal(at: path, cardDirectories: [path]))
        XCTAssertTrue(ReviewCheckouts.hasOpenTerminal(at: path, cardDirectories: [path + "/Sources"]))
        XCTAssertFalse(ReviewCheckouts.hasOpenTerminal(at: path, cardDirectories: [path + "0"]))
    }

    func testAutoPruneNeedsClosedUnusedAndClean() {
        let closed = FocusWorktreeCandidate(path: "p", prState: .closed)
        XCTAssertTrue(ReviewCheckouts.canAutoPrune(closed))
        XCTAssertFalse(ReviewCheckouts.canAutoPrune(FocusWorktreeCandidate(path: "p", prState: .open)))
        XCTAssertFalse(ReviewCheckouts.canAutoPrune(FocusWorktreeCandidate(path: "p", prState: .unknown)))
        XCTAssertFalse(
            ReviewCheckouts.canAutoPrune(FocusWorktreeCandidate(path: "p", prState: .closed, hasOpenTerminal: true)))
        XCTAssertFalse(ReviewCheckouts.canAutoPrune(FocusWorktreeCandidate(path: "p", prState: .closed, isDirty: true)))
        XCTAssertFalse(
            ReviewCheckouts.canAutoPrune(FocusWorktreeCandidate(path: "p", prState: .closed, isOrphan: true)))
    }

    func testOrphansAreThisRepositorysUnlistedFolders() {
        let names = ["termq-focus--k--a--1", "termq-focus--k--b--2", "termq-focus--other--c--3", "notes.txt"]
        let orphans = ReviewCheckouts.orphans(
            directoryNames: names, repoKey: "k", registeredPaths: [base.path + "/termq-focus--k--a--1"], base: base)
        XCTAssertEqual(orphans, [base.path + "/termq-focus--k--b--2"])
    }

    func testLiveWorktreeIsAFolderWhoseGitdirStillExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let gitdir = root.appendingPathComponent("repo/.git/worktrees/x")
        let live = root.appendingPathComponent("live")
        let dead = root.appendingPathComponent("dead")
        let bare = root.appendingPathComponent("bare")
        for dir in [gitdir, live, dead, bare] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data("gitdir: \(gitdir.path)\n".utf8).write(to: live.appendingPathComponent(".git"))
        try Data("gitdir: \(root.path)/gone\n".utf8).write(to: dead.appendingPathComponent(".git"))

        XCTAssertTrue(ReviewCheckouts.isLiveWorktree(at: live.path))
        XCTAssertFalse(ReviewCheckouts.isLiveWorktree(at: dead.path))
        XCTAssertFalse(ReviewCheckouts.isLiveWorktree(at: bare.path))
    }
}
