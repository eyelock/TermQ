# MCP Server

> **Early Release**: The MCP Server feature is in early release. APIs and behavior may change.

> **Local Use Only**: The MCP Server is designed for local development workflows. Do NOT deploy as a networked service or expose to the internet.

TermQ includes a Model Context Protocol (MCP) server that enables LLM assistants like Claude Code to interact with your terminal queue.

## Overview

The `termqmcp` binary is a standalone MCP server that:
- Exposes TermQ's terminal management as MCP tools
- Provides resources for board data and workflow context
- Offers prompts for session initialization and guidance

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

## Usage

### Stdio Mode (Default)

For integration with Claude Code:

```bash
termqmcp
```

### HTTP Mode

For network transport with authentication:

```bash
termqmcp --http --port 8742 --secret "your-uuid-token"
```

The `--secret` is required for HTTP mode and uses Bearer token authentication.

### Options

| Option | Description |
|--------|-------------|
| `--http` | Run HTTP server instead of stdio |
| `--port <port>` | HTTP port (default: 8742) |
| `--secret <token>` | Bearer token for HTTP auth (required with --http) |
| `--debug` | Use debug data directory |
| `--verbose` | Enable verbose logging |
| `--help` | Show help information |
| `--version` | Show version |

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

## Available Tools

| Tool | Description |
|------|-------------|
| `termq_pending` | Check terminals needing attention (run at session start) |
| `termq_context` | Get comprehensive LLM workflow documentation |
| `termq_list` | List all terminals or filter by column |
| `termq_find` | Search terminals by name, column, tag, badge, or UUID |
| `termq_open` | Open a terminal by name, UUID, or path |
| `termq_create` | Create a new terminal |
| `termq_set` | Update terminal properties |
| `termq_move` | Move terminal to a different column |

## Available Resources

| URI | Description |
|-----|-------------|
| `termq://terminals` | All terminals as JSON |
| `termq://columns` | Board columns as JSON |
| `termq://pending` | Pending work summary |
| `termq://context` | Workflow guide (markdown) |

## Available Prompts

| Prompt | Description |
|--------|-------------|
| `session_start` | Initialize LLM session with pending work overview |
| `workflow_guide` | Cross-session continuity guide |
| `terminal_summary` | Context and status for specific terminal |

## Security

- **Local Only**: The server is intended for local use only
- **HTTP Auth**: HTTP mode requires a shared secret (Bearer token)
- **No Remote**: Never expose the server to the internet

## Related

- [CLI Tool](cli-tool.md) - TermQ command-line interface
- [Command Palette](command-palette.md) - Quick access to commands
