import Foundation
import MCP
import TermQShared

// MARK: - Stacked-PR tool handlers

/// The four stack tools go through the same `StackProviderRegistry` in TermQShared the
/// app uses, so app and MCP share one implementation and tool responses serialize the
/// neutral `StackGraph` — a provider swap is invisible to MCP clients.
///
/// Probing is headless: `GitSpiceStackProvider` detection is filesystem + subprocess
/// only (no Keychain, no UI); `gs` reads its own auth. Provider absence and an
/// uninitialized repo are reported as normal states, not errors — an agent can branch
/// on them without try/catch gymnastics.
extension TermQMCPServer {
    private func loadStackRepo(repoId: String) throws -> GitRepository {
        let config = try RepoConfigLoader.load()
        guard let uuid = UUID(uuidString: repoId),
            let repo = config.repositories.first(where: { $0.id == uuid })
        else {
            throw MCPError.invalidParams("Unknown repository: \(repoId)")
        }
        return repo
    }

    private func errorResult(_ message: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: "Error: \(message)", annotations: nil, _meta: nil)],
            isError: true)
    }

    private func jsonResult(_ object: [String: Any], isError: Bool = false) -> CallTool.Result {
        let text: String
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        {
            text = string
        } else {
            text = "{}"
        }
        return CallTool.Result(
            content: [.text(text: text, annotations: nil, _meta: nil)], isError: isError)
    }

    /// Resolve the active provider, or `nil` when none is installed/usable.
    private func resolveStackProvider() async -> (any StackProvider)? {
        await StackProviderRegistry.shared.resolveProvider()?.0
    }

    func handleStackStatus(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let repoId: String
        do {
            repoId = try InputValidator.requireString("repoId", from: arguments, tool: "stack_status")
        } catch let error as InputValidator.ValidationError {
            return errorResult(error.localizedDescription)
        }
        do {
            let repo = try loadStackRepo(repoId: repoId)
            guard let provider = await resolveStackProvider() else {
                return jsonResult(["available": false, "reason": "no stacked-PR provider installed"])
            }
            guard await provider.isInitialized(repo: repo.path) else {
                return jsonResult(["available": true, "initialized": false])
            }
            let graph = try await provider.graph(repo: repo.path)
            let graphData = try JSONEncoder().encode(graph)
            let graphObject = try JSONSerialization.jsonObject(with: graphData)
            return jsonResult([
                "available": true,
                "initialized": true,
                "graph": graphObject,
            ])
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    func handleStackCreateBranch(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let repoId: String
        let worktreePath: String
        let name: String
        let target: String
        do {
            repoId = try InputValidator.requireString("repoId", from: arguments, tool: "stack_create_branch")
            worktreePath = try InputValidator.requireString(
                "worktreePath", from: arguments, tool: "stack_create_branch")
            name = try InputValidator.requireString("name", from: arguments, tool: "stack_create_branch")
            // Required (unlike the UI's own picker-driven calls into the same provider
            // method): an agent has no pinned context the way a human clicking "New
            // Stacked Branch After X" does, so an omitted target would silently fall
            // back to whatever happens to be checked out in `worktreePath` — that
            // fallback is how a stray call bifurcates into an unrelated new stack
            // instead of extending the intended one.
            target = try InputValidator.requireString("target", from: arguments, tool: "stack_create_branch")
        } catch let error as InputValidator.ValidationError {
            return errorResult(error.localizedDescription)
        }
        do {
            _ = try loadStackRepo(repoId: repoId)
            guard let provider = await resolveStackProvider() else {
                return errorResult("no stacked-PR provider installed")
            }
            try await provider.createBranch(name: name, target: target, in: worktreePath)
            return jsonResult(["ok": true, "branch": name])
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    func handleStackSubmit(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let repoId: String
        let worktreePath: String
        do {
            repoId = try InputValidator.requireString("repoId", from: arguments, tool: "stack_submit")
            worktreePath = try InputValidator.requireString(
                "worktreePath", from: arguments, tool: "stack_submit")
        } catch let error as InputValidator.ValidationError {
            return errorResult(error.localizedDescription)
        }
        let draft = InputValidator.optionalBool("draft", from: arguments)
        let updateOnly = InputValidator.optionalBool("updateOnly", from: arguments)
        do {
            _ = try loadStackRepo(repoId: repoId)
            guard let provider = await resolveStackProvider() else {
                return errorResult("no stacked-PR provider installed")
            }
            try await provider.submit(
                scope: .stack,
                options: StackSubmitOptions(draft: draft, updateOnly: updateOnly),
                in: worktreePath)
            return jsonResult(["ok": true])
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    func handleStackRestack(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        let repoId: String
        let worktreePath: String
        do {
            repoId = try InputValidator.requireString("repoId", from: arguments, tool: "stack_restack")
            worktreePath = try InputValidator.requireString(
                "worktreePath", from: arguments, tool: "stack_restack")
        } catch let error as InputValidator.ValidationError {
            return errorResult(error.localizedDescription)
        }
        do {
            let repo = try loadStackRepo(repoId: repoId)
            guard let provider = await resolveStackProvider() else {
                return errorResult("no stacked-PR provider installed")
            }
            do {
                try await provider.restack(scope: .stack, in: worktreePath)
                return jsonResult(["ok": true])
            } catch {
                // A conflict pause is a resolvable state, not a hard failure — report it
                // structurally so agents can guide the user (or resolve and continue).
                if let paused = await provider.pausedOperation(repo: repo.path) {
                    return jsonResult(
                        [
                            "ok": false,
                            "paused": true,
                            "conflictedFiles": paused.conflictedFiles,
                        ],
                        isError: false)
                }
                throw error
            }
        } catch {
            return errorResult(error.localizedDescription)
        }
    }
}
