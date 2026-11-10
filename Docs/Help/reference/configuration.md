# Configuration & Data

## Data file

TermQ stores all board state in a single JSON file:

```
~/Library/Application Support/TermQ/board.json
```

This file contains all columns, cards, tags, LLM context fields, and configuration. You can back it up manually, sync it via cloud storage (when the app is closed), or inspect it directly with any JSON editor.

> **Note:** Secrets (environment variables marked as secrets) are stored in your macOS Keychain, not in `board.json`. Backing up the file does not back up secrets.

## Settings

Open Settings with **⌘,** or via the TermQ menu. Sections are listed down the left; click one to see its settings on the right.

### General

| Setting | Description |
|---|---|
| **Updates** | Check for updates automatically, and opt in to beta releases |
| **Language** | The app's language |
| **Uninstall** | Remove TermQ and its tools |

### Terminal

| Setting | Description |
|---|---|
| **Theme** | Choose from 8 colour schemes |
| **Copy on Select** | Automatically copy selected text to clipboard |
| **Default Working Directory** | Working directory for new terminals (defaults to home) |
| **Default Backend** | Direct or tmux for new terminals |
| **Scrollback** | Lines of history kept per terminal |
| **Bin Retention** | Days before binned terminals are auto-deleted (0 = keep indefinitely) |

### Environment

Global environment variables injected into every terminal session. Manage variables and secrets here. See [Terminal Context](../tutorials/terminal-context.md) for details.

### Git & Stacks

| Setting | Description |
|---|---|
| **Protected Branches** | Comma-separated list of branch names that are never offered for deletion when pruning merged branches. Defaults to `main, master, develop`. Can be overridden per-repository in **Edit Repository**. |
| **Remote PR feed cap** | Most pull requests shown per repository in [Remote PRs](../tutorials/remote-prs.md) |
| **GitHub CLI and stacked PRs** | The `gh` CLI's status, and the backend used for [stacked branches](../tutorials/stacked-branches.md) |

### Integrations

| Setting | Description |
|---|---|
| **MCP Server** | Install / uninstall `termqmcp` |
| **CLI Tool** | Install / uninstall `termqcli` |
| **tmux** | Use tmux for session persistence, and silently reattach sessions on launch |

### Harnesses

The [YNH](https://github.com/eyelock/ynh) toolchain: whether it was found, **Show Harnesses sidebar tab**, the paths it uses, and **YNH Marketplaces** — the registries ynh installs harnesses from.

### Wheelhouses

| Setting | Description |
|---|---|
| **Show Wheelhouses sidebar tab** | Turn on the [Wheelhouses](../tutorials/wheelhouses.md) tab |
| **Inbox name for any human** / **Your own inbox name** | The names whose beads make up your Wheelhouse inbox |
| **Quick Terminal placement** | **Split** (the default) opens a seat's Quick Terminals in a panel beneath it; **Staged** gives each its own place on the stage |

### Marketplaces

Plugin marketplaces for the [Marketplace browser](../tutorials/marketplace-browser.md), whether to refresh them automatically, and the default folder for authored harnesses.

### Data & Security

| Setting | Description |
|---|---|
| **Enable Queued Actions** | Global permission for token injection in init commands |
| **Allow OSC 52 Clipboard Access** | Allow terminal programs to write to the clipboard via escape sequences |
| **Confirm External LLM Modifications** | Show a confirmation dialog when external tools attempt to modify `llmPrompt` or `llmNextAction` |

## Concurrent access

When the app, CLI (`termqcli`), and MCP server (`termqmcp`) are all running simultaneously, they share `board.json`. TermQ uses NSFileCoordinator for safe concurrent reads and writes, preventing data corruption from race conditions.
