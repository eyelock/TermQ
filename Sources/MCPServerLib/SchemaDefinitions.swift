import Foundation
import MCP

// Type alias for cleaner schema building
private typealias S = SchemaBuilder

// MARK: - Tool Definitions

extension TermQMCPServer {
    static var availableTools: [Tool] {
        [
            Tool(
                name: "termq_pending",
                description: """
                    Check terminals needing attention. Run this at the START of every LLM session.
                    Returns terminals with pending actions (llmNextAction) and staleness indicators.
                    Terminals are sorted: pending actions first, then by staleness (stale → ageing → fresh).
                    """,
                inputSchema: S.objectSchema([
                    S.bool("actionsOnly", "Only show terminals with llmNextAction set")
                ])
            ),
            Tool(
                name: "termq_context",
                description: """
                    Output comprehensive documentation for LLM/AI assistants.
                    Includes session start/end checklists, tag schema, command reference,
                    and workflow examples for cross-session continuity.
                    """,
                inputSchema: S.emptySchema()
            ),
            Tool(
                name: "termq_list",
                description: "List all terminals or filter by column. Supports listing columns only.",
                inputSchema: S.objectSchema([
                    S.string("column", "Filter by column name"),
                    S.bool("columnsOnly", "Return only column names"),
                ])
            ),
            Tool(
                name: "termq_find",
                description: """
                    Search for terminals by various criteria. Use 'query' for smart multi-word search
                    across name, description, path, and tags. All filters are AND-combined.
                    Returns matching terminals as JSON array sorted by relevance.
                    """,
                inputSchema: S.objectSchema([
                    S.string(
                        "query",
                        "Smart search: matches ANY word across name, description, path, tags. Best for natural language queries."
                    ),
                    S.string("name", "Filter by name (word-based matching)"),
                    S.string("column", "Filter by column name"),
                    S.string("tag", "Filter by tag (format: key or key=value)"),
                    S.string("id", "Filter by UUID"),
                    S.string("badge", "Filter by badge"),
                    S.bool("favourites", "Only show favourites"),
                ])
            ),
            Tool(
                name: "termq_open",
                description: """
                    Open an existing terminal by name, UUID, or path. Returns terminal details
                    including llmPrompt (persistent context) and llmNextAction (one-time task).
                    Use partial name matching for convenience.
                    """,
                inputSchema: S.objectSchema([
                    S.string("identifier", "Terminal name, UUID, or path (partial match supported)", required: true)
                ])
            ),
            Tool(
                name: "termq_create",
                description: """
                    Create a new terminal in TermQ. Optionally specify name, description, column,
                    path, tags, LLM context, and initialization command.
                    Returns the created terminal's details including its UUID.
                    """,
                inputSchema: S.objectSchema([
                    S.string("name", "Terminal name"),
                    S.string("description", "Terminal description"),
                    S.string("column", "Column name (e.g., 'In Progress')"),
                    S.string("path", "Working directory path"),
                    S.stringArray("tags", "Tags in key=value format (e.g., ['project=myapp', 'type=dev'])"),
                    S.string("llmPrompt", "Persistent LLM context"),
                    S.string("llmNextAction", "One-time action for next session"),
                    S.string("initCommand", "Command to run when terminal opens"),
                ])
            ),
            Tool(
                name: "termq_set",
                description: """
                    Update terminal properties. Identify terminal by name or UUID.
                    Can set name, description, column, badges, LLM fields, tags, init command, and favourite status.
                    Tags are additive by default - use replaceTags=true to replace all existing tags.
                    """,
                inputSchema: S.objectSchema([
                    S.string("identifier", "Terminal name or UUID", required: true),
                    S.string("name", "New name"),
                    S.string("description", "New description"),
                    S.string("column", "Move to column"),
                    S.string(
                        "badge",
                        "Badge text (comma-separated for multiple, e.g. 'WIP,urgent'). Replaces existing badges."),
                    S.stringArray("tags", "Tags in key=value format (e.g., ['status=reviewed'])"),
                    S.bool("replaceTags", "If true, replaces all tags; if false (default), adds to existing"),
                    S.string("llmPrompt", "Set persistent LLM context"),
                    S.string("llmNextAction", "Set one-time action"),
                    S.string("initCommand", "Command to run when terminal opens"),
                    S.bool("favourite", "Set favourite status"),
                ])
            ),
            Tool(
                name: "termq_move",
                description: "Move a terminal to a different column (workflow stage).",
                inputSchema: S.objectSchema([
                    S.string("identifier", "Terminal name or UUID", required: true),
                    S.string("column", "Target column name", required: true),
                ])
            ),
            Tool(
                name: "termq_get",
                description: """
                    Get terminal context by ID. Use with TERMQ_TERMINAL_ID environment variable
                    to get context for the terminal you're currently running in.
                    Returns full terminal details including tags, llmPrompt, and llmNextAction.
                    """,
                inputSchema: S.objectSchema([
                    S.string("id", "Terminal UUID (use $TERMQ_TERMINAL_ID from your environment)", required: true)
                ])
            ),
            Tool(
                name: "termq_delete",
                description: """
                    Delete a terminal. By default, moves to bin (soft delete).
                    Use permanent=true to permanently delete without bin recovery option.
                    """,
                inputSchema: S.objectSchema([
                    S.string("identifier", "Terminal name or UUID", required: true),
                    S.bool("permanent", "Permanently delete (skip bin, cannot be recovered)"),
                ])
            ),
        ]
    }
}

// MARK: - Resource Definitions

extension TermQMCPServer {
    static var availableResources: [Resource] {
        [
            Resource(
                name: "All Terminals",
                uri: "termq://terminals",
                description: "Complete list of all terminals in the board",
                mimeType: "application/json"
            ),
            Resource(
                name: "Board Columns",
                uri: "termq://columns",
                description: "List of all columns in the Kanban board",
                mimeType: "application/json"
            ),
            Resource(
                name: "Pending Work",
                uri: "termq://pending",
                description: "Terminals with pending actions and staleness indicators",
                mimeType: "application/json"
            ),
            Resource(
                name: "LLM Workflow Guide",
                uri: "termq://context",
                description: "Comprehensive documentation for cross-session workflows",
                mimeType: "text/markdown"
            ),
        ]
    }
}

// MARK: - Prompt Definitions

extension TermQMCPServer {
    static var availablePrompts: [Prompt] {
        [
            Prompt(
                name: "session_start",
                description: """
                    Initialize an LLM session with TermQ. Returns pending work,
                    board overview, and recommended first actions.
                    """,
                arguments: []
            ),
            Prompt(
                name: "workflow_guide",
                description: "Comprehensive guide for maintaining continuity across LLM sessions",
                arguments: []
            ),
            Prompt(
                name: "terminal_summary",
                description: "Get context and status for a specific terminal",
                arguments: [
                    Prompt.Argument(
                        name: "terminal",
                        description: "Terminal name or UUID",
                        required: true
                    )
                ]
            ),
        ]
    }
}
