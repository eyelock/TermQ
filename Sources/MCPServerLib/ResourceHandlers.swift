import Foundation
import MCP
import TermQShared

// MARK: - Resource Handler Implementations

extension TermQMCPServer {
    /// Handle resource read requests. Supports both static URIs and the templated forms
    /// declared in `availableResourceTemplates` (`termq://terminal/{id}`,
    /// `termq://terminal-by-name/{name}`, `termq://column/{name}`).
    ///
    /// Templates are matched after static URIs: a static URI takes precedence if both
    /// match (none currently overlap, but the order makes the precedence explicit).
    func dispatchResourceRead(_ params: ReadResource.Parameters) async throws -> ReadResource.Result {
        let uri = params.uri

        switch uri {
        case "termq://terminals":
            return try await handleTerminalsResource(uri: uri)
        case "termq://columns":
            return try await handleColumnsResource(uri: uri)
        case "termq://pending":
            return try await handlePendingResource(uri: uri)
        case "termq://context":
            return ReadResource.Result(contents: [.text(Self.contextDocumentation, uri: uri)])
        case "termq://repos":
            return try await handleReposResource(uri: uri)
        case "termq://worktrees":
            return try await handleWorktreesResource(uri: uri)
        case "termq://harnesses":
            return try await handleHarnessesResource(uri: uri)
        default:
            return try await dispatchTemplatedResource(uri: uri)
        }
    }

    // MARK: - Tier 3 resource handlers — repos, worktrees, harnesses

    /// All registered git repositories.
    private func handleReposResource(uri: String) async throws -> ReadResource.Result {
        let config = (try? RepoConfigLoader.load()) ?? RepoConfig()
        let payload = config.repositories.map { repo -> [String: Any] in
            [
                "id": repo.id.uuidString,
                "name": repo.name,
                "path": repo.path,
                "worktreeBasePath": repo.worktreeBasePath as Any,
                "protectedBranches": repo.protectedBranches as Any,
                "addedAt": ISO8601DateFormatter().string(from: repo.addedAt),
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let json = String(data: data, encoding: .utf8) ?? "[]"
        return ReadResource.Result(contents: [.text(json, uri: uri)])
    }

    /// Worktrees enumerated from every registered repository.
    /// Skips repos whose `git worktree list` fails — those errors don't kill the whole
    /// listing, but each failure is mirrored to `notifications/message` for diagnostics.
    private func handleWorktreesResource(uri: String) async throws -> ReadResource.Result {
        let config = (try? RepoConfigLoader.load()) ?? RepoConfig()
        var rows: [[String: Any]] = []
        for repo in config.repositories {
            do {
                let trees = try await GitServiceShared.listWorktrees(repoPath: repo.path)
                for tree in trees {
                    rows.append([
                        "repoId": repo.id.uuidString,
                        "repoName": repo.name,
                        "path": tree.path,
                        "branch": tree.branch as Any,
                        "commitHash": tree.commitHash,
                        "isMainWorktree": tree.isMainWorktree,
                        "isLocked": tree.isLocked,
                    ])
                }
            } catch {
                await emitLog(
                    .warning,
                    "listWorktrees failed for repo \(repo.name): \(error.localizedDescription)",
                    logger: "termq.worktrees"
                )
            }
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        let json = String(data: data, encoding: .utf8) ?? "[]"
        return ReadResource.Result(contents: [.text(json, uri: uri)])
    }

    /// Installed harnesses — listed via the `ynh` CLI when available. Empty array when
    /// ynh isn't on PATH or returns a non-zero exit; logged at info level so operators
    /// can see why.
    private func handleHarnessesResource(uri: String) async throws -> ReadResource.Result {
        let json = await runYnhCommand(arguments: ["ls", "--format", "json"]) ?? "[]"
        return ReadResource.Result(contents: [.text(json, uri: uri)])
    }

    /// Run an arbitrary `ynh` subcommand, capturing stdout as String. Returns nil when
    /// ynh is unavailable or the command fails. The MCP server runs headless and
    /// inherits the user's PATH — if `ynh` isn't there, the surface degrades gracefully
    /// rather than failing the whole resource.
    private func runYnhCommand(arguments: [String]) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ynh"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                await emitLog(
                    .info,
                    "ynh \(arguments.joined(separator: " ")) exited \(process.terminationStatus)",
                    logger: "termq.ynh"
                )
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            await emitLog(
                .info,
                "ynh not available: \(error.localizedDescription)",
                logger: "termq.ynh"
            )
            return nil
        }
    }

    /// Match a URI against the declared resource templates and dispatch to the right reader.
    /// Pure reads — no mutation, no handshake side-effects (use the `record_handshake`
    /// tool for that).
    private func dispatchTemplatedResource(uri: String) async throws -> ReadResource.Result {
        if let id = parseTemplatePath(uri: uri, prefix: "termq://terminal/") {
            return try await handleTerminalByIdResource(uri: uri, id: id)
        }
        if let name = parseTemplatePath(uri: uri, prefix: "termq://terminal-by-name/") {
            return try await handleTerminalByNameResource(uri: uri, name: name)
        }
        if let name = parseTemplatePath(uri: uri, prefix: "termq://column/") {
            return try await handleColumnByNameResource(uri: uri, name: name)
        }
        throw MCPError.invalidRequest("Unknown resource: \(uri)")
    }

    /// Extract the path segment after `prefix`. Returns nil if the URI doesn't match the
    /// prefix or has nothing after it. Decodes percent-escapes so callers can pass spaces
    /// in column / terminal names.
    private func parseTemplatePath(uri: String, prefix: String) -> String? {
        guard uri.hasPrefix(prefix) else { return nil }
        let raw = String(uri.dropFirst(prefix.count))
        guard !raw.isEmpty else { return nil }
        return raw.removingPercentEncoding ?? raw
    }

    private func handleTerminalByIdResource(uri: String, id: String) async throws -> ReadResource.Result {
        let board = try loadBoard()
        guard let uuid = UUID(uuidString: id),
            let card = board.activeCards.first(where: { $0.id == uuid })
        else {
            throw MCPError.invalidRequest("Terminal not found for UUID: \(id)")
        }
        let output = TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
        let json = try JSONHelper.encode(output)
        return ReadResource.Result(contents: [.text(json, uri: uri)])
    }

    private func handleTerminalByNameResource(uri: String, name: String) async throws -> ReadResource.Result {
        let board = try loadBoard()
        let nameLower = name.lowercased()
        guard let card = board.activeCards.first(where: { $0.title.lowercased() == nameLower }) else {
            throw MCPError.invalidRequest("Terminal not found for name: \(name)")
        }
        let output = TerminalOutput(from: card, columnName: board.columnName(for: card.columnId))
        let json = try JSONHelper.encode(output)
        return ReadResource.Result(contents: [.text(json, uri: uri)])
    }

    private func handleColumnByNameResource(uri: String, name: String) async throws -> ReadResource.Result {
        let board = try loadBoard()
        let nameLower = name.lowercased()
        guard let column = board.columns.first(where: { $0.name.lowercased() == nameLower }) else {
            throw MCPError.invalidRequest("Column not found: \(name)")
        }
        let cards = board.activeCards.filter { $0.columnId == column.id }
        let output = cards.map { TerminalOutput(from: $0, columnName: column.name) }
        let json = try JSONHelper.encode(output)
        return ReadResource.Result(contents: [.text(json, uri: uri)])
    }

    // MARK: - Resource Implementations

    private func handleTerminalsResource(uri: String) async throws -> ReadResource.Result {
        // Load errors are surfaced to the client via MCPError, not masked as empty arrays.
        // An empty board is `[]` legitimately; a missing/corrupt board is a real failure the
        // caller needs to see — otherwise a debug-vs-production data-directory mismatch
        // (the original bug this work fixes) silently returns nothing.
        let board = try loadBoard()
        let output = board.activeCards.map {
            TerminalOutput(from: $0, columnName: board.columnName(for: $0.columnId))
        }
        let json = try JSONHelper.encode(output)
        return ReadResource.Result(contents: [.text(json, uri: uri)])
    }

    private func handleColumnsResource(uri: String) async throws -> ReadResource.Result {
        let board = try loadBoard()
        let columns = board.sortedColumns().map { column in
            ColumnOutput(
                from: column,
                terminalCount: board.activeCards.filter { $0.columnId == column.id }.count
            )
        }
        let json = try JSONHelper.encode(columns)
        return ReadResource.Result(contents: [.text(json, uri: uri)])
    }

    private func handlePendingResource(uri: String) async throws -> ReadResource.Result {
        let board = try loadBoard()
        var cards = board.activeCards

        // Sort: pending actions first, then by staleness
        cards.sort { card1, card2 in
            let has1 = !card1.llmNextAction.isEmpty
            let has2 = !card2.llmNextAction.isEmpty
            if has1 != has2 { return has1 }
            return card1.stalenessRank > card2.stalenessRank
        }

        var terminals: [PendingTerminalOutput] = []
        var withNextAction = 0
        var staleCount = 0
        var freshCount = 0

        for card in cards {
            let staleness = card.staleness
            if !card.llmNextAction.isEmpty { withNextAction += 1 }
            switch staleness {
            case "stale", "old": staleCount += 1
            case "fresh": freshCount += 1
            default: break
            }
            terminals.append(
                PendingTerminalOutput(
                    from: card,
                    columnName: board.columnName(for: card.columnId),
                    staleness: staleness
                ))
        }

        let output = PendingOutput(
            terminals: terminals,
            summary: PendingSummary(
                total: terminals.count,
                withNextAction: withNextAction,
                stale: staleCount,
                fresh: freshCount
            )
        )
        let json = try JSONHelper.encode(output)
        return ReadResource.Result(contents: [.text(json, uri: uri)])
    }
}
