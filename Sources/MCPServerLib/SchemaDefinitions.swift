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
                    readOnlyHint: true, idempotentHint: true, openWorldHint: false),
                outputSchema: Schema.pendingOutputSchema
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
                description: """
                    List all terminals or filter by column. Supports listing columns only and
                    optional pagination via `cursor` / `limit`. Pass `includeDeleted: true` to
                    include soft-deleted (binned) cards in the result.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string("column", "Filter by column name"),
                    Schema.bool("columnsOnly", "Return only column names"),
                    Schema.bool(
                        "includeDeleted",
                        "If true, include soft-deleted cards (default: false — only active cards)"),
                    Schema.string("cursor", "Opaque pagination cursor returned by a previous call"),
                    Schema.int("limit", "Maximum number of results (default: no limit)"),
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: true, idempotentHint: true, openWorldHint: false),
                // outputSchema describes the cards-listing shape; when `columnsOnly` is true,
                // the result is an array of strings instead — clients must check the shape
                // at runtime. Documented in the tool description; no formal union schema.
                outputSchema: Schema.terminalListSchema
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
                    Schema.string("cursor", "Opaque pagination cursor returned by a previous call"),
                    Schema.int("limit", "Maximum number of results (default: no limit)"),
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: true, idempotentHint: true, openWorldHint: false),
                outputSchema: Schema.terminalListSchema
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
                    idempotentHint: false, openWorldHint: false),
                outputSchema: Schema.terminalOutputItemSchema
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
                // strictly read-only. DEPRECATED in favour of reading `termq://terminal/{id}`
                // (pure) plus the `record_handshake` tool (explicit write). One-release
                // alias per the deprecation policy in audit §3.1.
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: false,
                    idempotentHint: false, openWorldHint: false),
                outputSchema: Schema.terminalOutputItemSchema
            ),
            Tool(
                name: "whoami",
                title: "Identify current terminal",
                description: """
                    Identify the terminal this MCP server is being called from. Looks up
                    the card whose UUID matches the `TERMQ_TERMINAL_ID` environment
                    variable. Returns the full card or null if the env var is unset or
                    points at a non-existent terminal.

                    Equivalent to `get(id: $TERMQ_TERMINAL_ID)` but avoids the manual
                    substitution dance and surfaces a friendly null when running outside
                    a TermQ terminal context (e.g. a top-level Claude session).
                    """,
                inputSchema: Schema.emptySchema(),
                annotations: Tool.Annotations(
                    readOnlyHint: true, idempotentHint: true, openWorldHint: false),
                outputSchema: Schema.terminalOutputItemSchema
            ),
            Tool(
                name: "restore",
                title: "Restore deleted terminal",
                description: """
                    Restore a soft-deleted terminal from the bin. The card's `deletedAt`
                    timestamp is cleared; the card reappears in the GUI in its original column.
                    Permanent deletes (those committed via `delete(permanent: true)`) cannot
                    be restored — the card is gone from board.json.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string("identifier", "Terminal name or UUID", required: true)
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: false,
                    idempotentHint: true, openWorldHint: false),
                outputSchema: Schema.terminalOutputItemSchema
            ),
            Tool(
                name: "create_column",
                title: "Create column",
                description: "Create a new column on the board.",
                inputSchema: Schema.objectSchema([
                    Schema.string("name", "Column name (must be unique)", required: true),
                    Schema.string("description", "Optional column description"),
                    Schema.string("color", "Optional hex colour (e.g. '#FF5733')"),
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: false,
                    idempotentHint: false, openWorldHint: false)
            ),
            Tool(
                name: "rename_column",
                title: "Rename column",
                description: "Rename an existing column. Cards retain their column membership.",
                inputSchema: Schema.objectSchema([
                    Schema.string("identifier", "Current column name", required: true),
                    Schema.string("newName", "New column name", required: true),
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: false,
                    idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "delete_column",
                title: "Delete column",
                description: """
                    Delete a column. Refuses to delete a column that still contains active cards —
                    move or delete those first. Use `force: true` to soft-delete all cards in the
                    column along with it (cards land in the bin and can be restored individually).
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string("identifier", "Column name", required: true),
                    Schema.bool("force", "If true, soft-deletes cards in the column too (default: false)"),
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: true,
                    idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "create_worktree",
                title: "Create git worktree",
                description: """
                    Create a new git worktree on a registered repository. The worktree path
                    is rooted under the repository's configured `worktreeBasePath` (or
                    `<repoParent>/<branch>` if unset).
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string("repoId", "Repository UUID (from termq://repos)", required: true),
                    Schema.string("branch", "Branch name to check out as a worktree", required: true),
                    Schema.bool("createBranch", "Create the branch if it doesn't exist (default: false)"),
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: false,
                    idempotentHint: false, openWorldHint: true)
            ),
            Tool(
                name: "remove_worktree",
                title: "Remove git worktree",
                description: """
                    Remove an existing worktree (does NOT delete the underlying branch).
                    Refuses to remove the main worktree or a worktree with uncommitted changes
                    unless `force: true` is passed.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string("repoId", "Repository UUID", required: true),
                    Schema.string("path", "Absolute path of the worktree to remove", required: true),
                    Schema.bool("force", "Force removal even if dirty (default: false)"),
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: true,
                    idempotentHint: true, openWorldHint: true)
            ),
            Tool(
                name: "harness_launch",
                title: "Launch YNH harness",
                description: """
                    Launch a YNH harness session against a working directory. The harness is
                    invoked via `ynh run <harness>` in the target directory; output is
                    captured and returned.

                    Pass the **canonical harness id** (the `id` field from `termq://harnesses`,
                    e.g. `local/claude-dev`), not the bare `name`. `ynh run` rejects bare
                    names with an `io_error` — TermQ does NOT translate bare-name → canonical-id
                    on the caller's behalf.

                    This is the most consequential write tool TermQ exposes: it spawns an
                    LLM/agent process. Permissioned clients should elicit user confirmation
                    before each call. The destructiveHint annotation is set conservatively
                    so strict clients prompt by default.
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string(
                        "harness",
                        "Canonical harness id (the `id` field from termq://harnesses, e.g."
                            + " `local/claude-dev` or `github.com/<org>/<repo>/<name>`)."
                            + " Bare names from the `name` field are NOT accepted by `ynh run`.",
                        required: true),
                    Schema.string("workingDirectory", "Absolute path to run in", required: true),
                    Schema.string("prompt", "Optional prompt to seed the harness with"),
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: true,
                    idempotentHint: false, openWorldHint: true)
            ),
            Tool(
                name: "record_handshake",
                title: "Record LLM handshake",
                description: """
                    Mark a terminal as touched by the current LLM session. Sets the card's
                    `lastLLMGet` timestamp. Idiomatic pair: read the card via
                    `termq://terminal/{id}` (pure, no side effects) then call this when you
                    have actually consumed the context.

                    Pre-Tier-1b, this side effect lived on the `get` tool — see audit §3.1.
                    `get` remains as a deprecated alias and still records the handshake; new
                    callers should split the read (resource) from the write (this tool).
                    """,
                inputSchema: Schema.objectSchema([
                    Schema.string(
                        "id", "Terminal UUID (use $TERMQ_TERMINAL_ID from your environment)",
                        required: true)
                ]),
                annotations: Tool.Annotations(
                    readOnlyHint: false, destructiveHint: false,
                    idempotentHint: true, openWorldHint: false)
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
            Resource(
                name: "Repositories",
                uri: "termq://repos",
                title: "Registered git repositories",
                description: "All git repositories the user has registered with TermQ.",
                mimeType: "application/json"
            ),
            Resource(
                name: "Worktrees",
                uri: "termq://worktrees",
                title: "Git worktrees across all repositories",
                description: "Worktrees enumerated from every registered repository.",
                mimeType: "application/json"
            ),
            Resource(
                name: "Installed harnesses",
                uri: "termq://harnesses",
                title: "Installed YNH harnesses",
                description:
                    "Output of `ynh ls --format json`, passed through verbatim — full YNH"
                    + " envelope including `capabilities`, `schema_version`, `ynh_version`,"
                    + " and the `harnesses` array. Each harness has both an `id`"
                    + " (canonical, e.g. `local/claude-dev`) and a `name` (bare). Use `id`"
                    + " when calling `harness_launch`. Empty array when `ynh` is not installed.",
                mimeType: "application/json"
            ),
        ]
    }
}

// MARK: - Resource Templates

extension TermQMCPServer {
    /// Parameterised resource URIs the client can fill in. Clients call
    /// `resources/templates/list` to discover these; once filled, the resulting URI is
    /// read via standard `resources/read`.
    static var availableResourceTemplates: [Resource.Template] {
        [
            Resource.Template(
                uriTemplate: "termq://terminal/{id}",
                name: "Terminal by UUID",
                title: "Terminal (by UUID)",
                description:
                    "One terminal card resolved by UUID. Use $TERMQ_TERMINAL_ID inside a TermQ session.",
                mimeType: "application/json"
            ),
            Resource.Template(
                uriTemplate: "termq://terminal-by-name/{name}",
                name: "Terminal by name",
                title: "Terminal (by name)",
                description:
                    "One terminal card resolved by exact name. Prefer UUID form for stability.",
                mimeType: "application/json"
            ),
            Resource.Template(
                uriTemplate: "termq://column/{name}",
                name: "Column by name",
                title: "Cards in column",
                description: "All active cards in the named column.",
                mimeType: "application/json"
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
