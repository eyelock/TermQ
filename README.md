# TermQ

A Kanban-style terminal manager for macOS. Organise your terminal sessions as cards on a board — give each one a name, description, and stage — so you always know what's running, what's waiting, and what's done.

![TermQ Board View](./Docs/Help/Images/board-view.png)

> **Note**: This is a personal project developed in my spare time. Contributions and feedback welcome!

## What it does

- **Visual board** — Terminals live on a Kanban board with customisable columns. Drag cards between stages as work progresses.
- **Rich cards** — Each terminal has a name, description, tags, badges, working directory, and init command. Cards carry real context, not just a window title.
- **Persistent sessions** — tmux integration keeps sessions running when the app closes and reconnects automatically on launch.
- **Pinned terminals** — Pin frequently-used terminals for instant tab access without hunting the board.
- **Environment & secrets** — Per-terminal and global environment variables, with sensitive values stored in the macOS Keychain.
- **CLI tool** — `termqcli` controls the board from the shell. Create, find, move, and update terminals from anywhere.
- **MCP server** — `termqmcp` gives LLM assistants like Claude Code direct read/write access to the board — including persistent context and queued actions between sessions.
- **Autorun** — Queue an action on a terminal card; it executes automatically the next time the terminal opens.
- **8 colour themes** — Dracula, Nord, Solarized, One Dark, Monokai, Gruvbox, and more.

![Terminal Focused](./Docs/Help/Images/terminal-tabs.png)

## Installation

### From Release (Recommended)

1. Download the latest `TermQ-{version}.zip` from [Releases](../../releases)
2. Unzip and move `TermQ.app` to your Applications folder
3. Right-click and select "Open" on first launch (required for unsigned apps)

### From Source

```bash
git clone https://github.com/eyelock/termq.git
cd termq
make sign
open TermQ.app
```

See [CONTRIBUTING.md](./CONTRIBUTING.md) for detailed build instructions.

## Requirements

- macOS 14.0 (Sonoma) or later

## Documentation

📖 **[View Online Documentation](https://eyelock.github.io/TermQ/)**

The docs are structured as progressive tutorials — start with [Why TermQ](./Docs/Help/why.md) and follow the narrative through to the AI integration features. Or jump straight to the reference if you know what you're looking for:

- [Keyboard Shortcuts](./Docs/Help/reference/keyboard-shortcuts.md)
- [CLI Reference](./Docs/Help/reference/cli.md)
- [MCP Reference](./Docs/Help/reference/mcp.md)

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup, project structure, building, testing, and the release process.

## Credits

- Terminal emulation powered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza
- Built with assistance from [Claude Code](https://claude.ai/code), Anthropic's AI coding assistant

## License

MIT License — See [LICENSE](LICENSE) for details.
