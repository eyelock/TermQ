import Foundation
import MCP

// Type alias for cleaner schema building
private typealias Schema = SchemaBuilder

// MARK: - Tool Definitions

extension TermQMCPServer {
    static var availableTools: [Tool] {
        [
            Tool(
                name: "pending",
                title: "List pending terminals",
                description: """
                    Check terminals needing attention. Run this at the START of every LLM session.
                    Returns terminals with pending actions (llmNextAction) and staleness indicators.
                    Terminals are sorted: pending actions first, then by staleness (stale → ageing → fresh).
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.bool("actionsOnly", "Only show terminals with llmNextAction set")
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: true, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "context",
                title: "Workflow documentation",
                description: """
                    Output comprehensive documentation for LLM/AI assistants.
                    Includes session start/end checklists, tag schema, command reference,
                    and workflow examples for cross-session continuity.
                    """,
                inputSchema: Schema.emptySchema(),
                annotations: Tool.Annotations(
                    readOnlyHint: true, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "list",
                title: "List terminals",
                description: "List all terminals or filter by column. Supports listing columns only.",
                inputSchema: Schema.objectSchema([
                    Schema.string("column", "Filter by column name"),
                    Schema.bool("columnsOnly", "Return only column names"),
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: true, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "find",
                title: "Search terminals",
                description: """
                    Search for terminals by various criteria. Use 'query' for smart multi-word search
                    across name, description, path, and tags. All filters are AND-combined.
                    Returns matching terminals as JSON array sorted by relevance.
                    Tag filter is literal exact-match by default; prefix with `re:` for regex
                    (e.g. `staleness=re:(stale|ageing)` or `re:project=org/.+`).
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string(
                        "query",
                        "Smart search: matches ANY word across name, description, path, tags."
                            + " Best for natural language queries."
                    ),
                    Schema.string("name", "Filter by name (word-based matching)"),
                    Schema.string("column", "Filter by column name"),
                    Schema.string(
                        "tag",
                        "Filter by tag. Literal match by default: `key`, `key=value`."
                            + " Opt-in regex: `key=re:pattern` or `re:full-pattern`."),
                    Schema.string("id", "Filter by UUID"),
                    Schema.string("badge", "Filter by badge"),
                    Schema.bool("favourites", "Only show favourites"),
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: true, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "open",
                title: "Open terminal",
                description: """
                    Open an existing terminal by name, UUID, or path. Returns terminal details
                    including llmPrompt (persistent context) and llmNextAction (one-time task).
                    Note: partial-name matching returns the first hit — prefer exact names or
                    UUIDs to avoid ambiguity.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string(
                        "identifier",
                        "Terminal name, UUID, or path (partial match supported)", required: true)
                ]),
                // `open` focuses a terminal in the GUI when one is running — a visible side
                // effect that is neither destructive nor strictly idempotent.
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: false,
                    idempotentHint: false, openWorldHint: false)
            ),
            Tool(
                name: "create",
                title: "Create terminal",
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
                    Schema.stringArray(
                        "tags", "Tags in key=value format (e.g., ['project=myapp', 'type=dev'])"),
                    Schema.string("llmPrompt", "Persistent LLM context"),
                    Schema.string("llmNextAction", "One-time action for next session"),
                    Schema.string("initCommand", "Command to run when terminal opens"),
                ]),
                // Adds rows — repeated calls create more terminals, so not idempotent.
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: false,
                    idempotentHint: false, openWorldHint: false)
            ),
            Tool(
                name: "set",
                title: "Update terminal",
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
                        "Badge text (comma-separated for multiple, e.g. 'WIP,urgent')."
                            + " Replaces existing badges."),
                    Schema.string("tag", "A single tag in key=value format (e.g., 'project=my/repo')"),
                    Schema.stringArray(
                        "tags", "Tags in key=value format (e.g., ['status=reviewed'])"),
                    Schema.bool(
                        "replaceTags", "If true, replaces all tags; if false (default), adds to existing"),
                    Schema.string("llmPrompt", "Set persistent LLM context"),
                    Schema.string("llmNextAction", "Set one-time action"),
                    Schema.string("initCommand", "Command to run when terminal opens"),
                    Schema.bool("favourite", "Set favourite status"),
                ]),
                // Mutating but idempotent — same args produce the same end state.
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: false,
                    idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "move",
                title: "Move terminal to column",
                description: "Move a terminal to a different column (workflow stage).",
                inputSchema: Schema.objectSchema([
                    Schema.string("identifier", "Terminal name or UUID", required: true),
                    Schema.string("column", "Target column name", required: true),
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: false,
                    idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "get",
                title: "Get terminal by UUID",
                description: """
                    Get terminal context by ID. Use with TERMQ_TERMINAL_ID environment variable
                    to get context for the terminal you're currently running in.
                    Returns full terminal details including tags, llmPrompt, and llmNextAction.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string(
                        "id", "Terminal UUID (use $TERMQ_TERMINAL_ID from your environment)",
                        required: true)
                ]),
                // `get` records a `lastLLMGet` handshake timestamp as a side effect; not
                // strictly read-only. Tier 1b will split this into a pure resource-read plus
                // an explicit `record_handshake` tool — see audit §3.1.
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: false,
                    idempotentHint: false, openWorldHint: false)
            ),
            Tool(
                name: "delete",
                title: "Delete terminal",
                description: """
                    Delete a terminal. By default, moves to bin (soft delete) — recoverable from the GUI.
                    Use permanent=true to permanently delete without bin recovery option.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string("identifier", "Terminal name or UUID", required: true),
                    Schema.bool("permanent", "Permanently delete (skip bin, cannot be recovered)"),
                ]),
                // Soft-delete is reversible; permanent=true is destructive. Mark destructive
                // conservatively so permissioned clients prompt the user.
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: true,
                    idempotentHint: true, openWorldHint: false)
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
                title: "All terminals on the board",
                description: "Complete list of all terminals in the board",
                mimeType: "application/json"
            ),
            Resource(
                name: "Board Columns",
                uri: "termq://columns",
                title: "Board columns",
                description: "List of all columns in the Kanban board",
                mimeType: "application/json"
            ),
            Resource(
                name: "Pending Work",
                uri: "termq://pending",
                title: "Terminals needing attention",
                description: "Terminals with pending actions and staleness indicators",
                mimeType: "application/json"
            ),
            Resource(
                name: "LLM Workflow Guide",
                uri: "termq://context",
                title: "Workflow guide (markdown)",
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
                title: "Start a TermQ session",
                description: """
                    Initialize an LLM session with TermQ. Returns pending work,
                    board overview, and recommended first actions.
                    """,
                arguments: []
            ),
            Prompt(
                name: "workflow_guide",
                title: "Cross-session workflow guide",
                description: "Comprehensive guide for maintaining continuity across LLM sessions",
                arguments: []
            ),
            Prompt(
                name: "terminal_summary",
                title: "Summarise a terminal",
                description: "Get context and status for a specific terminal",
                arguments: [
                    Prompt.Argument(
                        name: "terminal",
                        title: "Terminal name or UUID",
                        description: "Terminal name or UUID — argument completion suggests existing terminal names",
                        required: true
                    )
                ]
            ),
        ]
    }
}
