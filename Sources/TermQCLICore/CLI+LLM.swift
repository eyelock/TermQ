import ArgumentParser
import Foundation
import MCPServerLib
import TermQShared

// MARK: - Pending Command (LLM Session Start)

struct Pending: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show terminals needing attention (LLM session start)",
        discussion: """
            Run this at the START of every LLM session. Shows terminals with:
            - Pending llmNextAction (queued tasks for you)
            - Staleness indicators based on tags

            This is your entry point for cross-session continuity.
            """
    )

    @Flag(name: .long, help: "Use debug data directory (TermQ-Debug)")
    var debug: Bool = false

    @Flag(name: .long, help: "Only show terminals with llmNextAction set")
    var actionsOnly: Bool = false

    @Option(name: [.customLong("data-dir"), .customLong("data-directory")], help: .hidden)
    var dataDirectory: String?

    func run() throws {
        do {
            let dataDirURL = dataDirectory.map { URL(fileURLWithPath: $0) }
            let board = try BoardLoader.loadBoard(
                dataDirectory: dataDirURL, profile: resolveProfile(debug))
            let cards = getFilteredAndSortedCards(from: board)
            let output = buildPendingOutput(cards: cards, board: board)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(output)
            if let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        } catch {
            JSONHelper.printErrorJSON("Failed to load board: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    func getFilteredAndSortedCards(from board: Board) -> [Card] {
        var cards = board.activeCards

        if actionsOnly {
            cards = cards.filter { !$0.llmNextAction.isEmpty }
        }

        cards.sort { card1, card2 in
            let has1 = !card1.llmNextAction.isEmpty
            let has2 = !card2.llmNextAction.isEmpty
            if has1 != has2 { return has1 }

            let staleness1 = card1.stalenessRank
            let staleness2 = card2.stalenessRank
            if staleness1 != staleness2 { return staleness1 > staleness2 }

            return card1.title < card2.title
        }
        return cards
    }

    func buildPendingOutput(cards: [Card], board: Board) -> PendingOutput {
        var pendingTerminals: [PendingTerminalOutput] = []
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

            pendingTerminals.append(
                PendingTerminalOutput(
                    from: card,
                    columnName: board.columnName(for: card.columnId),
                    staleness: staleness
                )
            )
        }

        return PendingOutput(
            terminals: pendingTerminals,
            summary: PendingSummary(
                total: pendingTerminals.count,
                withNextAction: withNextAction,
                stale: staleCount,
                fresh: freshCount
            )
        )
    }
}

// MARK: - Context Command (LLM Discovery)

struct Context: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show LLM-friendly context and usage guide",
        discussion: "Outputs comprehensive documentation for AI assistants including cross-session workflows."
    )

    func run() throws {
        let context = """
            # TermQ CLI - LLM Assistant Guide

            You are working with TermQ, a Kanban-style terminal manager that enables
            cross-session continuity for LLM assistants.

            ## ⚡ SESSION START CHECKLIST (Do This First!)

            1. Run `termq pending` to see what needs attention:
               ```bash
               termq pending
               ```
               This shows terminals with queued tasks (llmNextAction) and staleness.

            2. Check the summary in the output:
               - `withNextAction`: Terminals with tasks queued for you
               - `stale`: Terminals that haven't been touched recently

            3. If there are pending actions, handle them or acknowledge to user.

            ## 🛑 SESSION END CHECKLIST (Do This Before Ending!)

            1. **Queue next action** if work is incomplete:
               ```bash
               termq set "Terminal" --llm-next-action "Continue from: [specific point]"
               ```

            2. **Update staleness** to mark as recently worked:
               ```bash
               termq set "Terminal" --tag staleness=fresh
               ```

            3. **Update persistent context** if you learned something important:
               ```bash
               termq set "Terminal" --llm-prompt "Updated project context..."
               ```

            ## 📋 TAG SCHEMA (Cross-Session State Tracking)

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

            Set tags with:
            ```bash
            termq set "Terminal" --tag staleness=fresh --tag status=active
            ```

            ## 🔧 COMMAND REFERENCE

            ### Essential Commands
            ```bash
            termq pending                    # SESSION START - see what needs attention
            termq open "Name"                # Open terminal, get context
            termq set "Name" --llm-next-action "..."  # Queue task for next session
            termq set "Name" --llm-prompt "..."       # Update persistent context
            termq set "Name" --tag key=value          # Update state tags
            ```

            ### Discovery Commands
            ```bash
            termq list                       # All terminals as JSON
            termq find --tag staleness=stale # Find stale terminals
            termq find --column "In Progress" # Find by workflow stage
            termq find --tag project=org/repo # Find by project
            ```

            ### Workflow Commands
            ```bash
            termq move "Name" "Done"         # Move to column
            termq create --name "New" --column "To Do"  # New terminal
            ```

            ## 📊 TERMINAL FIELDS

            Each terminal has:
            - **name**: Display name
            - **description**: What this terminal is for
            - **column**: Workflow stage (To Do, In Progress, Done)
            - **path**: Working directory
            - **tags**: Key-value metadata (use for state tracking!)
            - **llmPrompt**: Persistent context (never auto-cleared)
            - **llmNextAction**: One-time task (cleared after terminal opens)

            ## 🔄 CROSS-SESSION WORKFLOW EXAMPLE

            ```bash
            # Session 1: Starting work
            termq pending  # Check what needs attention
            termq open "API Project"  # Get context
            # ... do work ...
            termq set "API Project" --llm-next-action "Implement auth middleware"
            termq set "API Project" --tag staleness=fresh --tag status=active

            # Session 2: Resuming
            termq pending  # Shows "API Project" with pending action
            # You see: "Implement auth middleware"
            termq open "API Project"  # Get full context
            # ... continue work ...
            termq set "API Project" --llm-next-action ""  # Clear if done
            termq set "API Project" --tag status=review
            termq move "API Project" "Review"
            ```

            ## 💡 TIPS

            - ALWAYS run `termq pending` at session start
            - ALWAYS set `llmNextAction` when parking incomplete work
            - Use `staleness` tag to track what needs attention
            - Use `project` tag to group related terminals
            - Keep `llmPrompt` updated with key project context
            - Move terminals through columns as work progresses
            """
        print(context)
    }
}
