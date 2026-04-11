# Configuration & Data

## Data file

TermQ stores all board state in a single JSON file:

```
~/Library/Application Support/TermQ/board.json
```

This file contains all columns, cards, tags, LLM context fields, and configuration. You can back it up manually, sync it via cloud storage (when the app is closed), or inspect it directly with any JSON editor.

> **Note:** Secrets (environment variables marked as secrets) are stored in your macOS Keychain, not in `board.json`. Backing up the file does not back up secrets.

## Settings

Open Settings with **⌘,** or via the TermQ menu.

### General

| Setting | Description |
|---|---|
| **Default Working Directory** | Working directory for new terminals (defaults to home) |
| **Default Backend** | Direct or tmux for new terminals |
| **Bin Retention** | Days before binned terminals are auto-deleted (0 = keep indefinitely) |

### Appearance

| Setting | Description |
|---|---|
| **Theme** | Choose from 8 colour schemes |
| **Copy on Select** | Automatically copy selected text to clipboard |

### Environment

Global environment variables injected into every terminal session. Manage variables and secrets here. See [Tutorial 6](tutorials/06-terminal-context.md) for details.

### Tools

| Setting | Description |
|---|---|
| **CLI Tool** | Install / uninstall `termqcli` |
| **MCP Server** | Install / uninstall `termqmcp` |
| **Enable tmux Backend** | Allow terminals to use tmux for session persistence |
| **Auto-reattach Sessions** | Silently reconnect tmux sessions on launch |
| **Enable LLM Prompt Auto-injection** | Global permission for token injection in init commands |

### Updates

| Setting | Description |
|---|---|
| **Automatically check for updates** | Check once per day for new versions |
| **Include beta releases** | Opt in to pre-release builds |

### Data & Security

| Setting | Description |
|---|---|
| **Allow OSC 52 Clipboard Access** | Allow terminal programs to write to the clipboard via escape sequences |
| **Confirm External LLM Modifications** | Show a confirmation dialog when external tools attempt to modify `llmPrompt` or `llmNextAction` |

## Concurrent access

When the app, CLI (`termqcli`), and MCP server (`termqmcp`) are all running simultaneously, they share `board.json`. TermQ uses NSFileCoordinator for safe concurrent reads and writes, preventing data corruption from race conditions.
