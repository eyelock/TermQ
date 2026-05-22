import Foundation
import MCP
import TermQShared

// MARK: - Tier 3 handlers — worktrees, harnesses

extension TermQMCPServer {
    /// Look up a registered repository by UUID. Returns the GitRepository or throws a
    /// CLI-flavoured error if not found / config can't be loaded.
    private func loadRepo(repoId: String) throws -> GitRepository {
        let config = try RepoConfigLoader.load()
        guard let uuid = UUID(uuidString: repoId),
            let repo = config.repositories.first(where: { $0.id == uuid })
        else {
            throw MCPError.invalidParams("Unknown repository: \(repoId)")
        }
        return repo
    }

    func handleCreateWorktree(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let repoId: String
        let branch: String
        do {
            repoId = try InputValidator.requireString("repoId", from: arguments, tool: "create_worktree")
            branch = try InputValidator.requireString("branch", from: arguments, tool: "create_worktree")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
        let createBranch = InputValidator.optionalBool("createBranch", from: arguments)
        do {
            let repo = try loadRepo(repoId: repoId)
            let basePath = repo.worktreeBasePath ?? URL(fileURLWithPath: repo.path).deletingLastPathComponent().path
            let worktreePath = "\(basePath)/\(branch)"
            // GitServiceShared.addWorktree always creates a branch (`-b <branch>`); the
            // `createBranch` flag here is informational — passing false won't suppress
            // the -b flag. Threaded onto the wire surface for future expansion.
            _ = createBranch
            try await GitServiceShared.addWorktree(
                repoPath: repo.path,
                branch: branch,
                worktreePath: worktreePath
            )
            return CallTool.Result(
                content: [
                    .text(
                        text:
                            "{\"ok\": true, \"path\": \"\(worktreePath)\", \"branch\": \"\(branch)\"}",
                        annotations: nil, _meta: nil)
                ])
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    func handleRemoveWorktree(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let repoId: String
        let path: String
        do {
            repoId = try InputValidator.requireString("repoId", from: arguments, tool: "remove_worktree")
            path = try InputValidator.requireString("path", from: arguments, tool: "remove_worktree")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
        // `force` is currently informational — GitServiceShared.removeWorktree doesn't
        // take a force flag in the public API yet. Threaded here so the wire surface is
        // stable; future revision can plumb it through.
        _ = InputValidator.optionalBool("force", from: arguments)
        do {
            let repo = try loadRepo(repoId: repoId)
            try await GitServiceShared.removeWorktree(repoPath: repo.path, worktreePath: path)
            return CallTool.Result(
                content: [
                    .text(text: "{\"ok\": true, \"removed\": \"\(path)\"}", annotations: nil, _meta: nil)
                ])
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    /// Launch a harness via `ynh run <harness>`. The most consequential write tool —
    /// permissioned clients should treat the `destructiveHint` as a strong prompt for
    /// user confirmation (full `elicitation/create` integration is a follow-up).
    func handleHarnessLaunch(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let harness: String
        let workingDirectory: String
        do {
            harness = try InputValidator.requireString("harness", from: arguments, tool: "harness_launch")
            workingDirectory = try InputValidator.requireString(
                "workingDirectory", from: arguments, tool: "harness_launch")
        } catch let error as InputValidator.ValidationError {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
        let prompt = InputValidator.optionalString("prompt", from: arguments)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = ["ynh", "run", harness]
        if let prompt, !prompt.isEmpty {
            args.append(contentsOf: ["--prompt", prompt])
        }
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let status = process.terminationStatus
            // Truncate excessive output so the MCP frame stays bounded.
            let snippet = output.count > 4096 ? String(output.suffix(4096)) : output
            let body: [String: Any] = [
                "ok": status == 0,
                "exitCode": status,
                "output": snippet,
            ]
            let json = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted])
            return CallTool.Result(
                content: [
                    .text(text: String(data: json, encoding: .utf8) ?? "{}", annotations: nil, _meta: nil)
                ],
                isError: status != 0)
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }
}
