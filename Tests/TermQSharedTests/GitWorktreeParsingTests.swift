import Foundation
import XCTest

@testable import TermQShared

final class GitWorktreeParsingTests: XCTestCase {

    // MARK: - Helpers

    private func parse(_ porcelain: String) -> [GitWorktree] {
        GitServiceShared.parsePorcelainWorktrees(porcelain)
    }

    // MARK: - Basic Parsing

    func testSingleMainWorktree() {
        let input = """
            worktree /Users/user/project
            HEAD abc1234567890123456789012345678901234567890
            branch refs/heads/main

            """
        let result = parse(input)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "/Users/user/project")
        XCTAssertEqual(result[0].branch, "main")
        XCTAssertEqual(result[0].commitHash, "abc12345")
        XCTAssertTrue(result[0].isMainWorktree)
        XCTAssertFalse(result[0].isLocked)
    }

    func testMultipleWorktrees() {
        let input = """
            worktree /Users/user/project
            HEAD aaaa111122223333444455556666777788889999aaaa
            branch refs/heads/main

            worktree /Users/user/project-wt/feat-sidebar
            HEAD bbbb111122223333444455556666777788889999bbbb
            branch refs/heads/feat-sidebar

            worktree /Users/user/project-wt/fix-bug-123
            HEAD cccc111122223333444455556666777788889999cccc
            branch refs/heads/fix-bug-123

            """
        let result = parse(input)
        XCTAssertEqual(result.count, 3)

        XCTAssertEqual(result[0].path, "/Users/user/project")
        XCTAssertTrue(result[0].isMainWorktree)

        XCTAssertEqual(result[1].path, "/Users/user/project-wt/feat-sidebar")
        XCTAssertEqual(result[1].branch, "feat-sidebar")
        XCTAssertFalse(result[1].isMainWorktree)

        XCTAssertEqual(result[2].path, "/Users/user/project-wt/fix-bug-123")
        XCTAssertEqual(result[2].branch, "fix-bug-123")
        XCTAssertFalse(result[2].isMainWorktree)
    }

    // MARK: - Main Worktree Identification

    func testFirstWorktreeIsMain() {
        let input = """
            worktree /main/path
            HEAD 1111111111111111111111111111111111111111
            branch refs/heads/main

            worktree /linked/path
            HEAD 2222222222222222222222222222222222222222
            branch refs/heads/other

            """
        let result = parse(input)
        XCTAssertTrue(result[0].isMainWorktree)
        XCTAssertFalse(result[1].isMainWorktree)
    }

    // MARK: - Detached HEAD

    func testDetachedHead() {
        let input = """
            worktree /Users/user/project
            HEAD abc1234567890123456789012345678901234567890
            branch refs/heads/main

            worktree /Users/user/project-wt/detached
            HEAD def4567890123456789012345678901234567890ab
            detached

            """
        let result = parse(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertNil(result[1].branch)
        XCTAssertEqual(result[1].commitHash, "def45678")
        XCTAssertFalse(result[1].isMainWorktree)
    }

    // MARK: - Bare Repositories

    func testBareRepository() {
        let input = """
            worktree /Users/user/project.git
            HEAD abc1234567890123456789012345678901234567890
            bare

            """
        let result = parse(input)
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].branch)
        XCTAssertTrue(result[0].isMainWorktree)
        XCTAssertFalse(result[0].isLocked)
    }

    // MARK: - Locked Worktrees

    func testLockedWorktreeWithReason() {
        let input = """
            worktree /Users/user/project
            HEAD abc1234567890123456789012345678901234567890
            branch refs/heads/main

            worktree /Users/user/project-wt/locked-feature
            HEAD def4567890123456789012345678901234567890ab
            branch refs/heads/locked-feature
            locked agent is working here

            """
        let result = parse(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result[0].isLocked)
        XCTAssertTrue(result[1].isLocked)
        XCTAssertEqual(result[1].branch, "locked-feature")
    }

    func testLockedWorktreeWithoutReason() {
        let input = """
            worktree /Users/user/project
            HEAD abc1234567890123456789012345678901234567890
            branch refs/heads/main

            worktree /Users/user/project-wt/locked-wt
            HEAD ghi7890123456789012345678901234567890abcde
            branch refs/heads/some-branch
            locked

            """
        let result = parse(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[1].isLocked)
    }

    // MARK: - Paths With Spaces

    func testPathWithSpaces() {
        let input = """
            worktree /Users/my user/my project name
            HEAD abc1234567890123456789012345678901234567890
            branch refs/heads/main

            worktree /Users/my user/project worktrees/feat sidebar
            HEAD def4567890123456789012345678901234567890ab
            branch refs/heads/feat-sidebar

            """
        let result = parse(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].path, "/Users/my user/my project name")
        XCTAssertEqual(result[1].path, "/Users/my user/project worktrees/feat sidebar")
    }

    // MARK: - Prunable Worktrees

    func testPrunableWorktreeIsParsedWithoutCrash() {
        let input = """
            worktree /Users/user/project
            HEAD abc1234567890123456789012345678901234567890
            branch refs/heads/main

            worktree /Users/user/project-wt/old-feature
            HEAD def4567890123456789012345678901234567890ab
            branch refs/heads/old-feature
            prunable gitdir file points to non-existent location

            """
        let result = parse(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1].branch, "old-feature")
        XCTAssertFalse(result[1].isLocked)
    }

    // MARK: - Commit Hash

    func testCommitHashIsTruncatedToEightChars() {
        let input = """
            worktree /Users/user/project
            HEAD abcdef1234567890abcdef1234567890abcdef12
            branch refs/heads/main

            """
        let result = parse(input)
        XCTAssertEqual(result[0].commitHash, "abcdef12")
    }

    func testShortCommitHashPreserved() {
        // Some repos (e.g., with shallow clones) may have abbreviated hashes
        let input = """
            worktree /Users/user/project
            HEAD abc123
            branch refs/heads/main

            """
        let result = parse(input)
        XCTAssertEqual(result[0].commitHash, "abc123")
    }

    // MARK: - Branch Name Extraction

    func testBranchNameExtractedFromFullRef() {
        let input = """
            worktree /Users/user/project
            HEAD abc1234567890123456789012345678901234567890
            branch refs/heads/feat/nested-feature

            """
        let result = parse(input)
        // Strips refs/heads/ prefix and preserves the full name including slashes
        XCTAssertEqual(result[0].branch, "feat/nested-feature")
    }

    // MARK: - Edge Cases

    func testEmptyOutputReturnsEmptyArray() {
        XCTAssertEqual(parse("").count, 0)
        XCTAssertEqual(parse("\n\n").count, 0)
    }

    func testMalformedBlockWithoutWorktreeLineIsSkipped() {
        let input = """
            HEAD abc1234567890123456789012345678901234567890
            branch refs/heads/main

            worktree /good/path
            HEAD def4567890123456789012345678901234567890ab
            branch refs/heads/other

            """
        let result = parse(input)
        // First block has no "worktree " line — should be skipped
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "/good/path")
    }

    func testCombinedLockedAndDetachedWorktree() {
        let input = """
            worktree /Users/user/project
            HEAD abc1234567890123456789012345678901234567890
            branch refs/heads/main

            worktree /Users/user/project-wt/detached-locked
            HEAD def4567890123456789012345678901234567890ab
            detached
            locked temporarily pinned

            """
        let result = parse(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertNil(result[1].branch)
        XCTAssertTrue(result[1].isLocked)
    }

    // MARK: - Identifiable

    func testIdentifiableIdEqualsPath() {
        let worktree = GitWorktree(
            path: "/some/path",
            branch: "main",
            commitHash: "abc12345",
            isMainWorktree: true,
            isLocked: false
        )
        XCTAssertEqual(worktree.id, "/some/path")
    }
}
