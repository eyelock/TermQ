# MCP Reference

`termqmcp` is a Model Context Protocol server that gives LLM assistants direct access to your TermQ board.

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

See [Tutorial 10](tutorials/10-mcp.md) for setup and the session workflow.

---

## Tools

### `termq_pending`

List terminals needing attention. Run this at the **start of every session**.

Returns terminals sorted by urgency: those with `llmNextAction` set first, then by staleness (`stale` → `ageing` → `fresh`).

| Parameter | Type | Description |
|---|---|---|
| `actionsOnly` | boolean | Only show terminals with `llmNextAction` set |

---

### `termq_list`

List all terminals, optionally filtered.

| Parameter | Type | Description |
|---|---|---|
| `column` | string | Filter by column name |
| `columnsOnly` | boolean | Return only column names |

---

### `termq_find`

Search terminals. All filters are AND-combined.

| Parameter | Type | Description |
|---|---|---|
| `query` | string | Smart search across name, description, path, and tags |
| `name` | string | Filter by name (word-based) |
| `column` | string | Filter by column |
| `tag` | string | Filter by tag (`key` or `key=value`) |
| `id` | string | Filter by UUID |
| `badge` | string | Filter by badge |
| `favourites` | boolean | Only show favourites |

**Smart search:** Word separators (`-`, `_`, `:`, `/`, `.`) are treated as boundaries. Searches all fields simultaneously. Results sorted by relevance.

---

### `termq_open`

Open a terminal. Returns full details including `llmPrompt` and `llmNextAction`.

| Parameter | Type | Description |
|---|---|---|
| `identifier` | string | Name, UUID, or path (partial match supported) |

---

### `termq_get`

Get context for a terminal by UUID. Use with `$TERMQ_TERMINAL_ID` to retrieve context for the terminal the LLM is currently running in.

| Parameter | Type | Description |
|---|---|---|
| `id` | string | Terminal UUID |

```
termq_get id="$TERMQ_TERMINAL_ID"
```

---

### `termq_create`

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

---

### `termq_set`

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

---

### `termq_move`

Move a terminal to a different column.

| Parameter | Type | Description |
|---|---|---|
| `identifier` | string | Name or UUID |
| `column` | string | Target column name |

---

### `termq_delete`

Delete a terminal. Soft-delete (bin) by default.

| Parameter | Type | Description |
|---|---|---|
| `identifier` | string | Name or UUID (required) |
| `permanent` | boolean | Permanently delete (cannot be recovered) |

---

## Resources

| URI | Description | MIME Type |
|---|---|---|
| `termq://terminals` | All terminals as JSON | application/json |
| `termq://columns` | Board columns as JSON | application/json |
| `termq://pending` | Pending work summary | application/json |
| `termq://context` | Workflow guide | text/markdown |

---

## Prompts

| Prompt | Description |
|---|---|
| `session_start` | Session initialisation — pending work overview and orientation |
| `workflow_guide` | Cross-session continuity guide |
| `terminal_summary` | Context and status for a specific terminal (requires `terminal` argument) |

---

## Session workflow

**Start:**
1. Call `termq_pending` to see what needs attention
2. Call `termq_get id="$TERMQ_TERMINAL_ID"` to load current terminal's context
3. Address `llmNextAction` if set, or ask the user which terminal to work in

**End:**
1. Call `termq_set` to write `llmNextAction` if work is incomplete
2. Update the `staleness` tag to `fresh`
3. Update `llmPrompt` if the standing context has materially changed

---

## Cross-session state tags

Use these tag keys consistently to make `termq_pending` sorting useful:

| Tag | Values | Purpose |
|---|---|---|
| `staleness` | `fresh`, `ageing`, `stale` | Recency of work |
| `status` | `pending`, `active`, `blocked`, `review` | Work state |
| `project` | `org/repo` | Project identifier |
| `worktree` | `branch-name` | Current git branch |
| `priority` | `high`, `medium`, `low` | Importance |

---

## Command-line options

```bash
termqmcp              # Stdio mode (default — for MCP clients)
termqmcp --version    # Show version
termqmcp --verbose    # Enable verbose logging
termqmcp --debug      # Use debug data directory
```

> **Local use only.** The MCP server is designed for local development. Do not expose it to the network.
