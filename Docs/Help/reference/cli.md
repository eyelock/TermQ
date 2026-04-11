# CLI Reference

`termqcli` is the TermQ command-line interface. All commands output JSON.

Install via **Settings > Tools > Install Command Line Tool**.

## Global flags

| Flag | Description |
|---|---|
| `--help` | Show help for a command |
| `--version` | Show version |

## Commands

### `list`

List all terminals on the board.

```bash
termqcli list
termqcli list --column "In Progress"
termqcli list --columns-only        # Return column names only
```

| Flag | Type | Description |
|---|---|---|
| `--column` | string | Filter by column name |
| `--columns-only` | boolean | Return only column names |

---

### `open`

Open a terminal by name, UUID, or path. Returns full terminal details as JSON, including `llmPrompt` and `llmNextAction`.

```bash
termqcli open "API Server"
termqcli open "70D8ECF5-E3E3-4FAC-A2A1-7E0F18C94B88"
termqcli open "/path/to/project"
termqcli open "api"                 # Partial name match
```

---

### `find`

Search terminals. All filters are AND-combined.

```bash
termqcli find --query "myapp api"
termqcli find --name "server"
termqcli find --column "In Progress"
termqcli find --tag env=production
termqcli find --tag project              # Any terminal with a "project" tag
termqcli find --favourites
```

| Flag | Type | Description |
|---|---|---|
| `--query` | string | Smart search across name, description, path, and tags |
| `--name` | string | Filter by name (word-based matching) |
| `--column` | string | Filter by column name |
| `--tag` | string | Filter by tag (`key` or `key=value`) |
| `--id` | string | Filter by UUID |
| `--badge` | string | Filter by badge |
| `--favourites` | boolean | Only show favourites |

**Smart search:** The `--query` flag treats word separators (`-`, `_`, `:`, `/`, `.`) as boundaries and matches across all fields simultaneously. Results are sorted by relevance (title matches rank highest).

---

### `create`

Create a new terminal.

```bash
termqcli create \
  --name "API Server" \
  --description "FastAPI backend" \
  --column "In Progress" \
  --path ~/code/myapp \
  --tags env=local project=myapp \
  --llm-prompt "FastAPI service, entry point is main.py" \
  --init-command "source .env"
```

| Flag | Type | Description |
|---|---|---|
| `--name` | string | Terminal name (required) |
| `--description` | string | Description |
| `--column` | string | Column name |
| `--path` | string | Working directory |
| `--tags` | string[] | Tags in `key=value` format |
| `--llm-prompt` | string | Persistent LLM context |
| `--llm-next-action` | string | One-time queued action |
| `--init-command` | string | Command to run when terminal opens |

---

### `set`

Update terminal fields. Tags are additive by default.

```bash
termqcli set "API Server" --description "Updated description"
termqcli set "API Server" --tags status=active
termqcli set "API Server" --tags env=prod --replace-tags
termqcli set "API Server" --llm-next-action "Run tests, check AUTH-23"
termqcli set "API Server" --favourite true
```

| Flag | Type | Description |
|---|---|---|
| `--name` | string | New name |
| `--description` | string | New description |
| `--column` | string | Move to column |
| `--badge` | string | Comma-separated badges |
| `--tags` | string[] | Tags in `key=value` format |
| `--replace-tags` | boolean | Replace all tags (default: add to existing) |
| `--llm-prompt` | string | Set persistent LLM context |
| `--llm-next-action` | string | Set one-time queued action |
| `--init-command` | string | Command to run when terminal opens |
| `--favourite` | boolean | Set favourite status |

---

### `move`

Move a terminal to a different column.

```bash
termqcli move "API Server" "Done"
termqcli move "70D8ECF5-..." "Blocked"
```

---

### `pending`

List terminals needing attention, sorted by urgency.

Terminals with `llmNextAction` set appear first, then sorted by staleness (`stale` → `ageing` → `fresh`).

```bash
termqcli pending
termqcli pending --actions-only     # Only terminals with a next action set
```

---

### `context`

Output comprehensive workflow documentation for the current board — session start/end checklists, tag schema, command reference, and examples. Designed to be piped to an LLM at the start of a session.

```bash
termqcli context
termqcli context | pbcopy           # Copy to clipboard
```

---

### `delete`

Delete a terminal. Soft-delete (bin) by default.

```bash
termqcli delete "API Server"
termqcli delete "API Server" --permanent    # Cannot be recovered
```

---

## JSON output

All commands return JSON. Pipe to `jq` for filtering:

```bash
# Get all terminal names
termqcli list | jq '.[].name'

# Find terminals in a column
termqcli list | jq '.[] | select(.column == "In Progress") | .name'

# Check if a terminal has a next action
termqcli open "API Server" | jq '.llmNextAction'
```
