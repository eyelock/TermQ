import Foundation

// MARK: - Git Errors

/// Errors from git operations (shared across CLI and MCP)
public enum GitError: Error, LocalizedError, Sendable {
    case gitNotFound
    case notAGitRepository(path: String)
    case commandFailed(command: String, exitCode: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "git is not installed or not found in expected locations."
        case .notAGitRepository(let path):
            return "Not a git repository: \(path)"
        case .commandFailed(let command, let exitCode, let output):
            return "git command failed (exit \(exitCode)): \(command)\n\(output)"
        }
    }
}

// MARK: - Git Service Shared

/// Sendable git operations for use from MCPServerLib and CLI (no SwiftUI dependency)
///
/// This is a pure command executor — it has no observable state. All methods are
/// static so the enum is used as a namespace.
public enum GitServiceShared {

    // MARK: - Porcelain Parsing

    /// Parse the output of `git worktree list --porcelain` into `[GitWorktree]`.
    ///
    /// Handles all known edge cases:
    /// - Paths with spaces
    /// - Detached HEAD (no `branch` line)
    /// - Bare repositories (`bare` line)
    /// - Locked worktrees (`locked` line)
    /// - Prunable worktrees (`prunable` line)
    /// - Main worktree identification (first entry)
    public static func parsePorcelainWorktrees(_ output: String) -> [GitWorktree] {
        // Split into per-worktree blocks separated by blank lines.
        // A trailing newline produces an empty last block — filter it out.
        let blocks =
            output
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var worktrees: [GitWorktree] = []

        for (index, block) in blocks.enumerated() {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }

            var path: String?
            var commitHash = ""
            var branch: String?
            var isLocked = false

            for line in lines {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    let fullHash = String(line.dropFirst("HEAD ".count))
                    commitHash = String(fullHash.prefix(8))
                } else if line.hasPrefix("branch ") {
                    let ref = String(line.dropFirst("branch ".count))
                    // Strip refs/heads/ prefix to get the full branch name (preserving slashes like feat/foo)
                    branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
                } else if line == "detached" {
                    branch = nil
                } else if line == "bare" {
                    branch = nil
                } else if line.hasPrefix("locked") {
                    isLocked = true
                }
                // "prunable" lines are parsed without error but not stored
            }

            guard let resolvedPath = path else { continue }

            worktrees.append(
                GitWorktree(
                    path: resolvedPath,
                    branch: branch,
                    commitHash: commitHash,
                    isMainWorktree: index == 0,
                    isLocked: isLocked
                )
            )
        }

        return worktrees
    }

    // MARK: - Command Execution

    /// Find the git binary in common installation locations
    public static func findGitPath() -> String? {
        let paths = [
            "/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/opt/local/bin/git",
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Execute a git command in a repository directory and return stdout.
    ///
    /// Throws `GitError.commandFailed` on non-zero exit.
    public static func runGitCommand(repoPath: String, args: [String]) async throws -> String {
        guard let gitPath = findGitPath() else {
            throw GitError.gitNotFound
        }
        return try await runCommand(gitPath, args: ["-C", repoPath] + args)
    }

    // MARK: - Repository Operations

    /// Check whether `path` is inside a git repository.
    public static func isGitRepo(path: String) async throws -> Bool {
        do {
            _ = try await runGitCommand(repoPath: path, args: ["rev-parse", "--git-dir"])
            return true
        } catch GitError.commandFailed {
            return false
        }
    }

    /// List all worktrees for the repository at `repoPath`.
    public static func listWorktrees(repoPath: String) async throws -> [GitWorktree] {
        let output = try await runGitCommand(repoPath: repoPath, args: ["worktree", "list", "--porcelain"])
        return parsePorcelainWorktrees(output)
    }

    /// Return `true` if the worktree at `worktreePath` has any uncommitted changes
    /// (staged, unstaged, or untracked tracked files). Runs `git status --porcelain`.
    public static func isWorktreeDirty(worktreePath: String) async -> Bool {
        guard
            let output = try? await runGitCommand(
                repoPath: worktreePath,
                args: ["status", "--porcelain"]
            )
        else { return false }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func checkoutBranchAsWorktree(
        repoPath: String,
        branch: String,
        worktreePath: String
    ) async throws {
        _ = try await runGitCommand(repoPath: repoPath, args: ["worktree", "add", worktreePath, branch])
    }

    /// Add a new worktree at `worktreePath` checked out to a new branch `branch`.
    /// Pass `baseBranch` to start from a specific branch instead of HEAD.
    public static func addWorktree(
        repoPath: String,
        branch: String,
        worktreePath: String,
        baseBranch: String? = nil
    ) async throws {
        var args = ["worktree", "add", worktreePath, "-b", branch]
        if let base = baseBranch {
            args.append(base)
        }
        _ = try await runGitCommand(repoPath: repoPath, args: args)
    }

    /// Remove the worktree at `worktreePath` (equivalent to `git worktree remove`).
    public static func removeWorktree(repoPath: String, worktreePath: String) async throws {
        _ = try await runGitCommand(repoPath: repoPath, args: ["worktree", "remove", worktreePath])
    }

    /// Get the currently checked-out branch name at `path`.
    ///
    /// Returns `nil` for detached HEAD.
    public static func getCurrentBranch(path: String) async throws -> String? {
        let output = try await runGitCommand(repoPath: path, args: ["rev-parse", "--abbrev-ref", "HEAD"])
        let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch == "HEAD" ? nil : branch
    }

    /// Get the `origin` remote URL for the repository at `path`.
    public static func getRemoteName(path: String) async throws -> String {
        let output = try await runGitCommand(repoPath: path, args: ["remote", "get-url", "origin"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private static func runCommand(_ executable: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            // Run on a global queue so `waitUntilExit()` does not block a cooperative thread.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        let command = ([executable] + args).joined(separator: " ")
                        continuation.resume(
                            throwing: GitError.commandFailed(
                                command: command,
                                exitCode: process.terminationStatus,
                                output: output
                            )
                        )
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
