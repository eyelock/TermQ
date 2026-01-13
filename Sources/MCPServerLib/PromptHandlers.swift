import Foundation
import MCP

// MARK: - Prompt Handler Implementations

extension TermQMCPServer {
    /// Handle prompt get requests
    func dispatchPromptGet(_ params: GetPrompt.Parameters) async throws -> GetPrompt.Result {
        switch params.name {
        case "session_start":
            return try await buildSessionStartPrompt()

        case "workflow_guide":
            return GetPrompt.Result(
                description: "TermQ Workflow Guide",
                messages: [
                    .user(.text(text: Self.contextDocumentation))
                ]
            )

        case "terminal_summary":
            let terminal = params.arguments?["terminal"] ?? "unknown"
            return try await buildTerminalSummaryPrompt(identifier: String(describing: terminal))

        default:
            throw MCPError.invalidRequest("Unknown prompt: \(params.name)")
        }
    }

    // MARK: - Prompt Builders

    private func buildSessionStartPrompt() async throws -> GetPrompt.Result {
        var content = "# TermQ Session Start\n\n"

        do {
            let board = try loadBoard()

            // Pending actions
            let pendingCards = board.activeCards.filter { !$0.llmNextAction.isEmpty }
            if pendingCards.isEmpty {
                content += "## Pending Actions\n\nNo pending actions.\n\n"
            } else {
                content += "## Pending Actions\n\n"
                for card in pendingCards {
                    content += "- **\(card.title)**: \(card.llmNextAction)\n"
                }
                content += "\n"
            }

            // Board overview
            content += "## Board Overview\n\n"
            for column in board.sortedColumns() {
                let count = board.activeCards.filter { $0.columnId == column.id }.count
                content += "- \(column.name): \(count) terminals\n"
            }
            content += "\n"

            // Recommended actions
            content += "## Recommended Actions\n\n"
            if !pendingCards.isEmpty {
                content += "1. Address pending actions above\n"
            }
            content += "2. Use `termq_pending` for detailed terminal view\n"
            content += "3. Use `termq_context` for workflow guide\n"

        } catch {
            content += "Error loading board: \(error.localizedDescription)\n\n"
            content += "Make sure TermQ has been run at least once to create the board file."
        }

        return GetPrompt.Result(
            description: "TermQ Session Start",
            messages: [.user(.text(text: content))]
        )
    }

    private func buildTerminalSummaryPrompt(identifier: String) async throws -> GetPrompt.Result {
        var content = "# Terminal Summary: \(identifier)\n\n"

        do {
            let board = try loadBoard()

            guard let card = board.findTerminal(identifier: identifier) else {
                content += "Terminal not found: \(identifier)"
                return GetPrompt.Result(
                    description: "Terminal Summary: \(identifier)",
                    messages: [.user(.text(text: content))]
                )
            }

            content += "## Details\n\n"
            content += "- **Name**: \(card.title)\n"
            content += "- **Column**: \(board.columnName(for: card.columnId))\n"
            content += "- **Path**: \(card.workingDirectory)\n"
            content += "- **ID**: \(card.id.uuidString)\n"

            if !card.description.isEmpty {
                content += "\n## Description\n\n\(card.description)\n"
            }

            if !card.llmPrompt.isEmpty {
                content += "\n## LLM Context\n\n\(card.llmPrompt)\n"
            }

            if !card.llmNextAction.isEmpty {
                content += "\n## Pending Action\n\n\(card.llmNextAction)\n"
            }

            if !card.tags.isEmpty {
                content += "\n## Tags\n\n"
                for tag in card.tags {
                    content += "- \(tag.key): \(tag.value)\n"
                }
            }

        } catch {
            content += "Error loading board: \(error.localizedDescription)"
        }

        return GetPrompt.Result(
            description: "Terminal Summary: \(identifier)",
            messages: [.user(.text(text: content))]
        )
    }
}

// MARK: - Context Documentation

extension TermQMCPServer {
    static let contextDocumentation = """
        # TermQ MCP Server - LLM Assistant Guide

        You are working with TermQ, a Kanban-style terminal manager that enables
        cross-session continuity for LLM assistants.

        ## SESSION START CHECKLIST (Do This First!)

        1. Use the `termq_pending` tool to see what needs attention:
           - Shows terminals with queued tasks (llmNextAction)
           - Shows staleness indicators

        2. Check the summary in the output:
           - `withNextAction`: Terminals with tasks queued for you
           - `stale`: Terminals that haven't been touched recently

        3. If there are pending actions, handle them or acknowledge to user.

        ## SESSION END CHECKLIST (Do This Before Ending!)

        1. **Queue next action** if work is incomplete:
           ```
           termq set "Terminal" --llm-next-action "Continue from: [specific point]"
           ```

        2. **Update staleness** to mark as recently worked:
           ```
           termq set "Terminal" --tag staleness=fresh
           ```

        3. **Update persistent context** if you learned something important:
           ```
           termq set "Terminal" --llm-prompt "Updated project context..."
           ```

        ## TAG SCHEMA (Cross-Session State Tracking)

        Use these tags to track state across sessions:

        | Tag | Values | Purpose |
        |-----|--------|---------|
        | `staleness` | fresh, ageing, stale | How recently worked on |
        | `status` | pending, active, blocked, review | Work state |
        | `project` | org/repo | Project identifier |
        | `worktree` | branch-name | Current git branch |
        | `priority` | high, medium, low | Importance |
        | `blocked-by` | ci, review, user | What's blocking |
        | `type` | feature, bugfix, chore, docs | Work category |

        ## AVAILABLE MCP TOOLS

        ### Read-Only Tools (Fully Implemented)
        - `termq_pending` - Check terminals needing attention (SESSION START)
        - `termq_context` - Get this documentation
        - `termq_list` - List all terminals or filter by column
        - `termq_find` - Search terminals by name, column, tag, etc.
        - `termq_open` - Get terminal details by name, UUID, or path

        ### Write Tools (Return CLI Commands)
        The MCP server is read-only for safety. These tools return CLI commands:
        - `termq_create` - Returns CLI command to create terminal
        - `termq_set` - Returns CLI command to modify terminal
        - `termq_move` - Returns CLI command to move terminal

        ## TERMINAL FIELDS

        Each terminal has:
        - **name**: Display name
        - **description**: What this terminal is for
        - **column**: Workflow stage (To Do, In Progress, Done)
        - **path**: Working directory
        - **tags**: Key-value metadata (use for state tracking!)
        - **llmPrompt**: Persistent context (never auto-cleared)
        - **llmNextAction**: One-time task (cleared after terminal opens)

        ## TIPS

        - ALWAYS use `termq_pending` at session start
        - ALWAYS set `llmNextAction` when parking incomplete work
        - Use `staleness` tag to track what needs attention
        - Use `project` tag to group related terminals
        - Keep `llmPrompt` updated with key project context
        - Move terminals through columns as work progresses
        """
}
