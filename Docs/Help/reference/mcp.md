# MCP Reference

`termqmcp` is a Model Context Protocol server that gives LLM assistants direct access to your TermQ board, plus the registered git repositories, worktrees, and YNH harnesses on your machine.

This server implements **MCP spec [2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25)**.

Install via **Settings > Tools > Install**. Configure in `~/.claude/mcp.json`:

```json
{
  "mcpServers": {
    "termq": {
      "command": "termqmcp",
      "args": []
    }
  }
}
```

See [Tutorial 10](../tutorials/mcp.md) for setup and the session workflow.

---

## Feature support matrix

| MCP capability | Supported | Notes |
|---|---|---|
| Tools | ✓ | Annotations + titles + outputSchema on read tools |
| Resources | ✓ | Including parameterised URI templates |
| Resource templates | ✓ | `termq://terminal/{id}`, `termq://column/{name}`, etc. |
| Resource subscriptions | ✓ | `resources/subscribe` + `notifications/resources/updated`, file-watcher backed |
| Prompts | ✓ | With argument completion |
| Completion (`completion/complete`) | ✓ | For prompt arguments |
| Logging (`notifications/message`) | ✓ | Threshold filtered via `logging/setLevel` |
| Pagination | ✓ (opt-in) | `cursor` + `limit` on `list` and `find` |
| Structured tool output | ✓ | `outputSchema` + `structuredContent` on read tools |
| Sampling | ✗ | Not used — see audit §3.8 |
| Roots | ✗ | Not currently enforced (no filesystem-touching tools beyond `~/Library/Application Support`) |
| Elicitation | Partial | `harness_launch` annotated `destructiveHint: true`; permissioned clients should prompt before each call |

---

## Tools

### Card reads

| Tool | Description |
|---|---|
| [`pending`](#pending) | Terminals needing attention — call at session start |
| [`context`](#context) | Workflow documentation as markdown |
| [`list`](#list) | List terminals, paginated |
| [`find`](#find) | Search terminals by many criteria, paginated |
| [`open`](#open) | Resolve terminal by name/UUID/path |
| [`get`](#get) | Resolve terminal by UUID + record handshake *(deprecated — use the resource read + `record_handshake` instead)* |
| [`whoami`](#whoami) | Resolve the current terminal from `$TERMQ_TERMINAL_ID` |

### Card writes

| Tool | Description |
|---|---|
| [`create`](#create) | Create a new terminal |
| [`set`](#set) | Update terminal properties |
| [`move`](#move) | Move terminal to a different column |
| [`delete`](#delete) | Soft-delete (bin) or permanent delete |
| [`restore`](#restore) | Restore a soft-deleted terminal |
| [`record_handshake`](#record_handshake) | Record that an LLM has consumed a terminal's context |

### Column CRUD

| Tool | Description |
|---|---|
| [`create_column`](#create_column) | Add a new column to the board |
| [`rename_column`](#rename_column) | Rename an existing column |
| [`delete_column`](#delete_column) | Remove a column (with optional cascade) |

### Worktrees and harnesses

| Tool | Description |
|---|---|
| [`create_worktree`](#create_worktree) | Create a git worktree on a registered repo |
| [`remove_worktree`](#remove_worktree) | Remove an existing worktree |
| [`harness_launch`](#harness_launch) | Launch a YNH harness — destructive, prompt before each call |

### Annotations

Every tool carries hints permissioned clients use to decide auto-allow vs prompt:

| Hint | Meaning |
|---|---|
| `readOnlyHint: true` | Tool does not modify state — safe to auto-allow |
| `destructiveHint: true` | Tool may perform irreversible changes — prompt the user |
| `idempotentHint: true` | Calling repeatedly with same args has no extra effect |
| `openWorldHint: true` | Tool reaches outside TermQ's data (git, gh, ynh) |

---

### Tool details

#### `pending`

List terminals needing attention. Run this at the **start of every session**. Returns terminals sorted by urgency: those with `llmNextAction` set first, then by staleness (`stale` → `ageing` → `fresh`).

| Parameter | Type | Description |
|---|---|---|
| `actionsOnly` | boolean | Only show terminals with `llmNextAction` set |

Annotations: `readOnly`, `idempotent`. Returns `structuredContent` matching the pending-output schema.

#### `list`

List all terminals, optionally filtered. Supports pagination and including soft-deleted cards.

| Parameter | Type | Description |
|---|---|---|
| `column` | string | Filter by column name |
| `columnsOnly` | boolean | Return only column names |
| `includeDeleted` | boolean | Include soft-deleted (binned) cards |
| `cursor` | string | Opaque pagination cursor from a previous call |
| `limit` | integer | Maximum number of results |

Always returns the envelope `{ items: [...] }`. Paginated calls add `nextCursor`; `columnsOnly: true` returns columns inside `items` instead of terminals. `find` uses the same shape. The MCP spec requires `structuredContent` to be a JSON object, so the array of rows lives under `items`.

#### `find`

Search terminals. All filters are AND-combined.

| Parameter | Type | Description |
|---|---|---|
| `query` | string | Smart search across name, description, path, and tags |
| `name` | string | Filter by name (word-based) |
| `column` | string | Filter by column |
| `tag` | string | Filter by tag (see *Tag matching* below) |
| `id` | string | Filter by UUID |
| `badge` | string | Filter by badge |
| `favourites` | boolean | Only show favourites |
| `cursor`, `limit` | — | Pagination, same as `list` |

**Tag matching:** Literal exact match by default. Both `key` and `key=value` forms supported. Opt-in regex via `re:` prefix: `staleness=re:(stale|ageing)` matches the value as regex; `re:project=org/.+` matches the whole `key=value` string as regex. Invalid regex surfaces an error rather than silent literal fallback.

#### `open`

Open a terminal. Returns full details including `llmPrompt` and `llmNextAction`.

| Parameter | Type | Description |
|---|---|---|
| `identifier` | string | Name, UUID, or path (partial match — prefer exact for writes) |

#### `get`

> **Deprecated** in favour of reading the resource `termq://terminal/{id}` (pure) plus an explicit `record_handshake` call. Kept as a combined-read+handshake alias for one release.

| Parameter | Type | Description |
|---|---|---|
| `id` | string | Terminal UUID |

#### `whoami`

Resolve the current terminal from the `TERMQ_TERMINAL_ID` environment variable. Returns a `{terminal: null, reason: …}` payload when the env var is unset — top-level Claude sessions don't see a spurious error.

#### `record_handshake`

Set the `lastLLMGet` timestamp on a card without returning the card payload. Idiomatic pair with reading `termq://terminal/{id}` as a pure resource.

| Parameter | Type | Description |
|---|---|---|
| `id` | string | Terminal UUID |

#### `create`

Create a new terminal.

| Parameter | Type | Description |
|---|---|---|
| `name` | string | Terminal name |
| `description` | string | Description |
| `column` | string | Column name |
| `path` | string | Working directory |
| `tags` | string[] | Tags in `key=value` format |
| `llmPrompt` | string | Persistent LLM context |
| `llmNextAction` | string | One-time queued action |
| `initCommand` | string | Command to run when terminal opens |

#### `set`

Update terminal fields. Tags are additive by default.

| Parameter | Type | Description |
|---|---|---|
| `identifier` | string | Name or UUID (required) |
| `name` | string | New name |
| `description` | string | New description |
| `column` | string | Move to column |
| `badge` | string | Comma-separated badges |
| `tags` | string[] | Tags in `key=value` format |
| `replaceTags` | boolean | Replace all tags (default: additive) |
| `llmPrompt` | string | Set persistent LLM context |
| `llmNextAction` | string | Set one-time queued action |
| `initCommand` | string | Command to run when terminal opens |
| `favourite` | boolean | Set favourite status |

#### `move`

Move a terminal to a different column.

| Parameter | Type | Description |
|---|---|---|
| `identifier` | string | Name or UUID |
| `column` | string | Target column name |

#### `delete`

Delete a terminal. Soft-delete (bin) by default.

| Parameter | Type | Description |
|---|---|---|
| `identifier` | string | Name or UUID (required) |
| `permanent` | boolean | Permanently delete (cannot be recovered) |

#### `restore`

Restore a soft-deleted terminal from the bin.

| Parameter | Type | Description |
|---|---|---|
| `identifier` | string | Name or UUID (required) |

#### `create_column`

| Parameter | Type | Description |
|---|---|---|
| `name` | string | Column name (must be unique) |
| `description` | string | Optional description |
| `color` | string | Optional hex colour (e.g. `#FF5733`) |

#### `rename_column`

| Parameter | Type | Description |
|---|---|---|
| `identifier` | string | Current column name |
| `newName` | string | New column name |

#### `delete_column`

| Parameter | Type | Description |
|---|---|---|
| `identifier` | string | Column name |
| `force` | boolean | Soft-delete cards in the column along with it (default: false) |

#### `create_worktree`

| Parameter | Type | Description |
|---|---|---|
| `repoId` | string | Repository UUID from `termq://repos` |
| `branch` | string | Branch name to check out as a worktree |
| `createBranch` | boolean | Reserved — currently informational |

#### `remove_worktree`

| Parameter | Type | Description |
|---|---|---|
| `repoId` | string | Repository UUID |
| `path` | string | Absolute path of the worktree |
| `force` | boolean | Reserved — currently informational |

#### `harness_launch`

Invoke `ynh run <harness>` against a working directory. Annotated `destructiveHint: true` — permissioned clients should prompt before each call.

| Parameter | Type | Description |
|---|---|---|
| `harness` | string | **Canonical** harness id from `termq://harnesses` (the `id` field, e.g. `local/claude-dev`). Bare `name` values are rejected by `ynh run`. |
| `workingDirectory` | string | Absolute path to run in |
| `prompt` | string | Optional prompt to seed the harness |

> The YNH CLI requires canonical ids (`local/<name>`, `github.com/<org>/<repo>/<name>`, etc.) and rejects bare names with an `io_error`. TermQ does **not** translate bare-name → canonical-id on the caller's behalf — pass the `id` field from `termq://harnesses` verbatim.

---

## Resources

### Static resources

| URI | Description | MIME |
|---|---|---|
| `termq://terminals` | All active terminals | application/json |
| `termq://columns` | Board columns | application/json |
| `termq://pending` | Pending work summary | application/json |
| `termq://context` | Workflow guide | text/markdown |
| `termq://repos` | Registered git repositories | application/json |
| `termq://worktrees` | Worktrees across all repos | application/json |
| `termq://harnesses` | Installed YNH harnesses — full `ynh ls --format json` envelope passed through verbatim (`capabilities`, `schema_version`, `ynh_version`, `harnesses` array). Each harness has both `id` (canonical) and `name` (bare). | application/json |

### Resource templates

Discoverable via `resources/templates/list`; read via standard `resources/read` once filled.

| Template | Description |
|---|---|
| `termq://terminal/{id}` | One terminal card resolved by UUID — pure read, no handshake side effect |
| `termq://terminal-by-name/{name}` | One terminal card resolved by exact name |
| `termq://column/{name}` | All active cards in the named column |

### Subscriptions

The server declares `resources.subscribe: true`. Subscribe to any URI via `resources/subscribe` and the server will emit `notifications/resources/updated` when board.json changes. Notifications are debounced over a 150ms window so atomic writes don't fan out to multiple notifications.

Subscriptions persist for the lifetime of the MCP session. Use `resources/unsubscribe` to stop.

---

## Prompts

| Prompt | Description |
|---|---|
| `session_start` | Session initialisation — pending work overview and orientation |
| `workflow_guide` | Cross-session continuity guide |
| `terminal_summary(terminal)` | Context and status for a specific terminal. The `terminal` argument supports autocomplete via `completion/complete`. |

---

## Session workflow

**Start:**
1. Call `pending` to see what needs attention.
2. Call `whoami` (or read `termq://terminal/{id}` with `$TERMQ_TERMINAL_ID`) to load current terminal's context.
3. Address `llmNextAction` if set, or ask the user which terminal to work in.

**End:**
1. Call `set` to write `llmNextAction` if work is incomplete.
2. Call `record_handshake` on each terminal you consumed context from.
3. Update the `staleness` tag to `fresh`.
4. Update `llmPrompt` if the standing context has materially changed.

---

## Cross-session state tags

Use these tag keys consistently to make `pending` sorting useful:

| Tag | Values | Purpose |
|---|---|---|
| `staleness` | `fresh`, `ageing`, `stale` | Recency of work |
| `status` | `pending`, `active`, `blocked`, `review` | Work state |
| `project` | `org/repo` | Project identifier |
| `worktree` | `branch-name` | Current git branch |
| `priority` | `high`, `medium`, `low` | Importance |

---

## CLI parity

Tools split into two policy buckets. See `Sources/MCPServerLib/ToolParity.swift`.

### Mandatory CLI parity

Every tool below has a matching `termqcli` subcommand:

`pending`, `context`, `list`, `find`, `open`, `get`, `create`, `set`, `move`, `delete`, `restore`, `create_column`, `rename_column`, `delete_column`, `whoami`.

### CLI omitted by design

| Tool | Reason |
|---|---|
| `record_handshake` | MCP-only semantics — proof an LLM consumed a card's context doesn't translate to a shell prompt. |
| `harness_launch` | Requires elicitation/user confirmation; no CLI equivalent. Security gate — launching a harness from a pipe bypasses the confirmation surface. |
| `create_worktree`, `remove_worktree` | `git worktree` already exists as a first-class CLI; re-wrapping in termqcli is wrapper-on-wrapper. |

A build-enforced test (`Tests/MCPServerLibTests/ToolParityTests.swift`) walks `availableTools` and asserts every name is classified. Adding a tool without classifying it fails CI.

---

## Command-line options

```bash
termqmcp              # Stdio mode (default — for MCP clients)
termqmcp --version    # Show version
termqmcp --verbose    # Log resolved profile + data directory + transport at startup
termqmcp --debug      # Use debug data directory (TermQ-Debug/)
```

> **Local use only.** The MCP server is designed for local development. Do not expose it to the network.
