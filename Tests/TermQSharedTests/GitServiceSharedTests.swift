import Foundation
import XCTest

@testable import TermQShared

final class GitServiceSharedTests: XCTestCase {

    // MARK: - GitError

    func testGitError_gitNotFound_description() {
        let error = GitError.gitNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("git"))
    }

    func testGitError_notAGitRepository_description() {
        let error = GitError.notAGitRepository(path: "/some/path")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("/some/path"))
    }

    func testGitError_commandFailed_description() {
        let error = GitError.commandFailed(
            command: "git status", exitCode: 128, output: "fatal: not a repo")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("128"))
        XCTAssertTrue(error.errorDescription!.contains("git status"))
        XCTAssertTrue(error.errorDescription!.contains("fatal"))
    }

    // MARK: - findGitPath

    func testFindGitPath_returnsExecutableOrNil() {
        let path = GitServiceShared.findGitPath()
        if let p = path {
            XCTAssertTrue(
                FileManager.default.isExecutableFile(atPath: p),
                "findGitPath returned \(p) but it is not executable")
        }
    }

    // MARK: - Async Git Operations

    func testIsGitRepo_returnsFalseForNonGitDirectory() async throws {
        guard GitServiceShared.findGitPath() != nil else {
            throw XCTSkip("git not available in this environment")
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await GitServiceShared.isGitRepo(path: tempDir.path)
        XCTAssertFalse(result)
    }

    func testIsGitRepo_returnsTrueForProjectRoot() async throws {
        guard GitServiceShared.findGitPath() != nil else {
            throw XCTSkip("git not available in this environment")
        }
        let projectRoot = FileManager.default.currentDirectoryPath
        // Guard: only run if cwd looks like a git repo
        guard
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: projectRoot).appendingPathComponent(".git").path)
        else {
            throw XCTSkip("Working directory is not a git repository")
        }

        let result = try await GitServiceShared.isGitRepo(path: projectRoot)
        XCTAssertTrue(result)
    }

    func testListWorktrees_returnsWorktreesForProjectRoot() async throws {
        guard GitServiceShared.findGitPath() != nil else {
            throw XCTSkip("git not available in this environment")
        }
        let projectRoot = FileManager.default.currentDirectoryPath
        guard
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: projectRoot).appendingPathComponent(".git").path)
        else {
            throw XCTSkip("Working directory is not a git repository")
        }

        let trees = try await GitServiceShared.listWorktrees(repoPath: projectRoot)
        XCTAssertFalse(trees.isEmpty, "Expected at least the main worktree")
        XCTAssertTrue(trees.contains { $0.isMainWorktree })
    }

    func testGetCurrentBranch_worksForProjectRoot() async throws {
        guard GitServiceShared.findGitPath() != nil else {
            throw XCTSkip("git not available in this environment")
        }
        let projectRoot = FileManager.default.currentDirectoryPath
        guard
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: projectRoot).appendingPathComponent(".git").path)
        else {
            throw XCTSkip("Working directory is not a git repository")
        }

        // Should not throw; may return nil for detached HEAD
        _ = try await GitServiceShared.getCurrentBranch(path: projectRoot)
    }

    func testIsWorktreeDirty_returnsBoolWithoutThrowing() async throws {
        guard GitServiceShared.findGitPath() != nil else {
            throw XCTSkip("git not available in this environment")
        }
        let projectRoot = FileManager.default.currentDirectoryPath
        guard
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: projectRoot).appendingPathComponent(".git").path)
        else {
            throw XCTSkip("Working directory is not a git repository")
        }

        // Never throws, returns false on error — just exercise the code path
        _ = await GitServiceShared.isWorktreeDirty(worktreePath: projectRoot)
    }

    func testIsWorktreeDirty_returnsFalseForNonRepo() async throws {
        guard GitServiceShared.findGitPath() != nil else {
            throw XCTSkip("git not available in this environment")
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = await GitServiceShared.isWorktreeDirty(worktreePath: tempDir.path)
        XCTAssertFalse(result, "Non-git directory should be reported as not dirty")
    }

    func testRunGitCommand_throwsCommandFailedForBadPath() async throws {
        guard GitServiceShared.findGitPath() != nil else {
            throw XCTSkip("git not available in this environment")
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            _ = try await GitServiceShared.runGitCommand(
                repoPath: tempDir.path, args: ["rev-parse", "--git-dir"])
            XCTFail("Expected commandFailed for non-repo path")
        } catch GitError.commandFailed {
            // expected
        } catch {
            XCTFail("Expected commandFailed, got: \(error)")
        }
    }
}
