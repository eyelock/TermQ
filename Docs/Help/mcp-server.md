# MCP Server

> **Early Release**: The MCP Server feature is in early release. APIs and behavior may change.

> **Local Use Only**: The MCP Server is designed for local development workflows. Do NOT deploy as a networked service or expose to the internet.

TermQ includes a Model Context Protocol (MCP) server that enables LLM assistants like Claude Code to interact with your terminal queue.

## Overview

The `termqmcp` binary is a standalone MCP server that:
- Exposes TermQ's terminal management as MCP tools
- Provides resources for board data and workflow context
- Offers prompts for session initialization and guidance
- Supports smart search across terminal metadata

## Installation

The MCP server is installed alongside the TermQ CLI:

1. Open TermQ Settings (Cmd+,)
2. Go to the CLI tab
3. Click "Install" to install both `termq` and `termqmcp`

Or install manually:
```bash
# From TermQ.app bundle
cp /Applications/TermQ.app/Contents/Resources/termqmcp /usr/local/bin/
```

## Claude Code Configuration

Add to your Claude Code MCP settings (`~/.claude/mcp.json`):

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

## Command Line Options

| Option | Description |
|--------|-------------|
| `--http` | Run HTTP server instead of stdio |
| `--port <port>` | HTTP port (default: 8742) |
| `--secret <token>` | Bearer token for HTTP auth (required with --http) |
| `--debug` | Use debug data directory |
| `--verbose` | Enable verbose logging |
| `--help` | Show help information |
| `--version` | Show version |

### Stdio Mode (Default)

For integration with Claude Code and other MCP clients:

```bash
termqmcp
```

### HTTP Mode

For network transport with authentication:

```bash
termqmcp --http --port 8742 --secret "your-uuid-token"
```

The `--secret` is required for HTTP mode and uses Bearer token authentication.

## Available Tools

### termq_pending

Check terminals needing attention. **Run this at the START of every LLM session.**

Returns terminals with pending actions (`llmNextAction`) and staleness indicators, sorted: pending actions first, then by staleness (stale → ageing → fresh).

| Parameter | Type | Description |
|-----------|------|-------------|
| `actionsOnly` | boolean | Only show terminals with `llmNextAction` set |

### termq_context

Output comprehensive documentation for LLM/AI assistants. Includes session start/end checklists, tag schema, command reference, and workflow examples.

No parameters required.

### termq_list

List all terminals or filter by column.

| Parameter | Type | Description |
|-----------|------|-------------|
| `column` | string | Filter by column name |
| `columnsOnly` | boolean | Return only column names |

### termq_find

Search for terminals by various criteria. All filters are AND-combined.

| Parameter | Type | Description |
|-----------|------|-------------|
| `query` | string | **Smart search**: matches words across name, description, path, and tags |
| `name` | string | Filter by name (word-based matching) |
| `column` | string | Filter by column name |
| `tag` | string | Filter by tag (format: `key` or `key=value`) |
| `id` | string | Filter by UUID |
| `badge` | string | Filter by badge |
| `favourites` | boolean | Only show favourites |

#### Smart Search

The `query` parameter provides intelligent multi-word search:

- **Word normalization**: Separators like `-`, `_`, `:`, `/`, `.` are treated as word boundaries
- **Multi-field**: Searches across name, description, path, and tags simultaneously
- **Relevance scoring**: Results sorted by match quality (title matches score highest)

**Example**: Searching for `"MCP Toolkit Migrate"` will find a terminal named `"mcp-toolkit: migrate workflows/hooks"` because:
- `mcp` matches `mcp` in the name
- `toolkit` matches `toolkit` in the name
- `migrate` matches `migrate` in the name

### termq_open

Open an existing terminal by name, UUID, or path. Returns terminal details including `llmPrompt` (persistent context) and `llmNextAction` (one-time task).

| Parameter | Type | Description |
|-----------|------|-------------|
| `identifier` | string | Terminal name, UUID, or path (partial match supported) |

### termq_move

Move a terminal to a different column (workflow stage). This operation modifies the board directly.

| Parameter | Type | Description |
|-----------|------|-------------|
| `identifier` | string | Terminal name or UUID |
| `column` | string | Target column name |

### termq_create

Create a new terminal in TermQ. Returns CLI command for safety (creation requires app context).

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | string | Terminal name |
| `description` | string | Terminal description |
| `column` | string | Column name (e.g., 'In Progress') |
| `path` | string | Working directory path |
| `llmPrompt` | string | Persistent LLM context |
| `llmNextAction` | string | One-time action for next session |

### termq_set

Update terminal properties. Returns CLI command for safety.

| Parameter | Type | Description |
|-----------|------|-------------|
| `identifier` | string | Terminal name or UUID (required) |
| `name` | string | New name |
| `description` | string | New description |
| `column` | string | Move to column |
| `badge` | string | Comma-separated badges |
| `llmPrompt` | string | Set persistent LLM context |
| `llmNextAction` | string | Set one-time action |
| `favourite` | boolean | Set favourite status |

### termq_get

Get terminal context by UUID. Use with the `TERMQ_TERMINAL_ID` environment variable to get context for the terminal you're currently running in.

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | string | Terminal UUID (use `$TERMQ_TERMINAL_ID` from environment) |

**Example usage from within a TermQ terminal:**

```bash
# Get current terminal's context via MCP
termq_get id="$TERMQ_TERMINAL_ID"
```

This is useful for LLM agents that need to check their current terminal's persistent context (`llmPrompt`), pending actions (`llmNextAction`), tags, and metadata.

## Available Resources

| URI | Description | MIME Type |
|-----|-------------|-----------|
| `termq://terminals` | All terminals as JSON | application/json |
| `termq://columns` | Board columns as JSON | application/json |
| `termq://pending` | Pending work summary | application/json |
| `termq://context` | Workflow guide | text/markdown |

## Available Prompts

| Prompt | Description | Arguments |
|--------|-------------|-----------|
| `session_start` | Initialize LLM session with pending work overview | None |
| `workflow_guide` | Cross-session continuity guide | None |
| `terminal_summary` | Context and status for specific terminal | `terminal` (required) |

## LLM Workflow

### Session Start

1. Call `termq_pending` to see terminals needing attention
2. Check `withNextAction` count for queued tasks
3. Address pending actions or acknowledge to user

### Session End

1. Set `llmNextAction` for incomplete work
2. Update `staleness` tag to `fresh`
3. Update `llmPrompt` with new context if needed

### Cross-Session State Tags

| Tag | Values | Purpose |
|-----|--------|---------|
| `staleness` | fresh, ageing, stale | How recently worked on |
| `status` | pending, active, blocked, review | Work state |
| `project` | org/repo | Project identifier |
| `worktree` | branch-name | Current git branch |
| `priority` | high, medium, low | Importance |

## Agent Autorun

TermQ supports automatic execution of queued actions when terminals open. This enables LLM agents to queue work that runs automatically on the next terminal session.

### How It Works

1. An LLM sets `llmNextAction` on a terminal (e.g., "run tests and check for regressions")
2. The terminal's init command contains the `{{LLM_NEXT_ACTION}}` token
3. When the terminal opens, the token is replaced with the queued action
4. The action executes automatically and is cleared from the terminal

### Permission Model

Autorun requires **two permissions** to be enabled:

| Level | Setting | Location | Default |
|-------|---------|----------|---------|
| Global | Enable Terminal Autorun | Settings > Tools | Off |
| Per-Terminal | Allow Autorun | Terminal Editor > Terminal > Security | Off |

Both must be enabled for autorun to function. This two-level model ensures:
- Users explicitly opt-in to automatic command execution
- Individual terminals can be protected even when global autorun is enabled
- Sensitive terminals (production, databases) can remain protected

### Enabling Autorun

1. **Enable globally**: Settings > Tools > Enable Terminal Autorun
2. **Enable per-terminal**: Edit terminal > Terminal tab > Security > Allow Autorun
3. **Configure init command**: Include `{{LLM_NEXT_ACTION}}` token in the terminal's init command

Example init command:
```bash
{{LLM_NEXT_ACTION}}
```

Or combined with other setup:
```bash
source .env && {{LLM_NEXT_ACTION}}
```

### Behavior When Disabled

When autorun is disabled (either globally or per-terminal):
- The `{{LLM_NEXT_ACTION}}` token is replaced with an empty string
- The queued `llmNextAction` is **not** consumed (preserved for later)
- The terminal opens normally without executing the queued action

### MCP Output

Terminal responses include the `allowAutorun` field so LLMs can check if autorun is enabled:

```json
{
  "id": "...",
  "name": "My Terminal",
  "allowAutorun": true,
  "llmNextAction": "run npm test"
}
```

### Security Considerations

- **Opt-in by design**: Both global and per-terminal settings default to off
- **Safe Paste still applies**: Dangerous commands may still trigger paste warnings
- **Review queued actions**: Use `termq_pending` to see what actions are queued before enabling autorun
- **Audit trail**: Consider keeping terminals with autorun disabled for sensitive environments

## Security

- **Local Only**: The server is intended for local use only
- **HTTP Auth**: HTTP mode requires a shared secret (Bearer token)
- **No Remote**: Never expose the server to the internet
- **Read-Safe**: Most write operations return CLI commands instead of modifying directly

## Related

- [CLI Tool](cli-tool.md) - TermQ command-line interface
- [Command Palette](command-palette.md) - Quick access to commands
