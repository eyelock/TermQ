import Foundation
import MCP

// Type alias for cleaner schema building
private typealias Schema = SchemaBuilder

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
                inputSchema: Schema.objectSchema([
                    Schema.bool("actionsOnly", "Only show terminals with llmNextAction set")
                ])
            ),
            Tool(
                name: "termq_context",
                description: """
                    Output comprehensive documentation for LLM/AI assistants.
                    Includes session start/end checklists, tag schema, command reference,
                    and workflow examples for cross-session continuity.
                    """,
                inputSchema: Schema.emptySchema()
            ),
            Tool(
                name: "termq_list",
                description: "List all terminals or filter by column. Supports listing columns only.",
                inputSchema: Schema.objectSchema([
                    Schema.string("column", "Filter by column name"),
                    Schema.bool("columnsOnly", "Return only column names"),
                ])
            ),
            Tool(
                name: "termq_find",
                description: """
                    Search for terminals by various criteria. Use 'query' for smart multi-word search
                    across name, description, path, and tags. All filters are AND-combined.
                    Returns matching terminals as JSON array sorted by relevance.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string(
                        "query",
                        "Smart search: matches ANY word across name, description, path, tags. Best for natural language queries."
                    ),
                    Schema.string("name", "Filter by name (word-based matching)"),
                    Schema.string("column", "Filter by column name"),
                    Schema.string("tag", "Filter by tag (format: key or key=value)"),
                    Schema.string("id", "Filter by UUID"),
                    Schema.string("badge", "Filter by badge"),
                    Schema.bool("favourites", "Only show favourites"),
                ])
            ),
            Tool(
                name: "termq_open",
                description: """
                    Open an existing terminal by name, UUID, or path. Returns terminal details
                    including llmPrompt (persistent context) and llmNextAction (one-time task).
                    Use partial name matching for convenience.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string("identifier", "Terminal name, UUID, or path (partial match supported)", required: true)
                ])
            ),
            Tool(
                name: "termq_create",
                description: """
                    Create a new terminal in TermQ. Optionally specify name, description, column,
                    path, tags, LLM context, and initialization command.
                    Returns the created terminal's details including its UUID.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string("name", "Terminal name"),
                    Schema.string("description", "Terminal description"),
                    Schema.string("column", "Column name (e.g., 'In Progress')"),
                    Schema.string("path", "Working directory path"),
                    Schema.stringArray("tags", "Tags in key=value format (e.g., ['project=myapp', 'type=dev'])"),
                    Schema.string("llmPrompt", "Persistent LLM context"),
                    Schema.string("llmNextAction", "One-time action for next session"),
                    Schema.string("initCommand", "Command to run when terminal opens"),
                ])
            ),
            Tool(
                name: "termq_set",
                description: """
                    Update terminal properties. Identify terminal by name or UUID.
                    Can set name, description, column, badges, LLM fields, tags, init command, and favourite status.
                    Tags are additive by default - use replaceTags=true to replace all existing tags.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string("identifier", "Terminal name or UUID", required: true),
                    Schema.string("name", "New name"),
                    Schema.string("description", "New description"),
                    Schema.string("column", "Move to column"),
                    Schema.string(
                        "badge",
                        "Badge text (comma-separated for multiple, e.g. 'WIP,urgent'). Replaces existing badges."),
                    Schema.stringArray("tags", "Tags in key=value format (e.g., ['status=reviewed'])"),
                    Schema.bool("replaceTags", "If true, replaces all tags; if false (default), adds to existing"),
                    Schema.string("llmPrompt", "Set persistent LLM context"),
                    Schema.string("llmNextAction", "Set one-time action"),
                    Schema.string("initCommand", "Command to run when terminal opens"),
                    Schema.bool("favourite", "Set favourite status"),
                ])
            ),
            Tool(
                name: "termq_move",
                description: "Move a terminal to a different column (workflow stage).",
                inputSchema: Schema.objectSchema([
                    Schema.string("identifier", "Terminal name or UUID", required: true),
                    Schema.string("column", "Target column name", required: true),
                ])
            ),
            Tool(
                name: "termq_get",
                description: """
                    Get terminal context by ID. Use with TERMQ_TERMINAL_ID environment variable
                    to get context for the terminal you're currently running in.
                    Returns full terminal details including tags, llmPrompt, and llmNextAction.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string("id", "Terminal UUID (use $TERMQ_TERMINAL_ID from your environment)", required: true)
                ])
            ),
            Tool(
                name: "termq_delete",
                description: """
                    Delete a terminal. By default, moves to bin (soft delete).
                    Use permanent=true to permanently delete without bin recovery option.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string("identifier", "Terminal name or UUID", required: true),
                    Schema.bool("permanent", "Permanently delete (skip bin, cannot be recovered)"),
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
