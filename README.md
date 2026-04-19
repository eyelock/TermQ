# TermQ

A terminal command centre for macOS. Organise your sessions on a Kanban board, integrate with AI assistants, and manage external tooling — all from one place.

![TermQ Board View](./Docs/Help/Images/board-view.png)

> Personal project, developed in spare time. Contributions and feedback welcome!

## The Board

Terminal sessions live as cards on a Kanban board with customisable columns. Each card carries real context — name, description, tags, working directory, and init command — so you always know what's running, what's waiting, and what's done.

- Drag cards between stages as work progresses
- Pin terminals for instant tab access
- Persistent sessions via tmux — reconnects automatically on launch
- Per-terminal and global environment variables, with secrets stored in the macOS Keychain
- 8 colour themes — Dracula, Nord, Solarized, One Dark, Monokai, Gruvbox, and more

## Git & Worktrees

The Repositories sidebar surfaces your git repos and worktrees alongside their active terminals. Create and switch worktrees without leaving the app, and open a terminal directly into any branch.

![Repositories & Worktrees](./Docs/Help/Images/worktree-sidebar-overview.png)

## AI Integration

TermQ exposes two integration points for AI assistants:

- **MCP server** (`termqmcp`) — gives Claude Code and other LLM tools direct read/write access to the board, including persistent context and queued actions between sessions
- **CLI** (`termqcli`) — create, find, move, and update terminals from anywhere in the shell
- **Autorun** — queue a command on a card; it runs automatically the next time that terminal opens

![Focused terminal with Claude Code](./Docs/Help/Images/termq-terminal-focussed.png)

## Harnesses

Harnesses are installable tool integrations. Browse a registry, install with one click, and launch managed services directly from the sidebar.

Each harness can provide:

- **Artifacts** — binaries, scripts, or config bundled with the harness
- **Hooks** — shell commands wired to lifecycle events
- **MCP Servers** — additional AI tool integrations exposed automatically to the board
- **Profiles** — pre-configured terminal launch configurations

![Harness detail](./Docs/Help/Images/harness-detail-overview.png)

[YNH](https://github.com/eyelock/ynh) is the reference harness runtime — a tool for building and distributing harnesses that TermQ can discover, install, and manage.

## Installation

### From Release (Recommended)

1. Download the latest `TermQ-{version}.zip` from [Releases](../../releases)
2. Unzip and move `TermQ.app` to your Applications folder
3. Right-click → Open on first launch (required for unsigned apps)

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

- [Keyboard Shortcuts](./Docs/Help/reference/keyboard-shortcuts.md)
- [CLI Reference](./Docs/Help/reference/cli.md)
- [MCP Reference](./Docs/Help/reference/mcp.md)

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup, project structure, building, testing, and the release process.

## Credits

- Terminal emulation powered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza
- Session persistence powered by [tmux](https://github.com/tmux/tmux)
- Harness runtime by [YNH](https://github.com/eyelock/ynh)
- Built with assistance from [Claude Code](https://claude.ai/code)

## License

MIT License — See [LICENSE](LICENSE) for details.
