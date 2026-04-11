# About TermQ

**TermQ** — Kanban-style terminal manager for macOS.

## Credits

- Terminal emulation powered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza
- Built with significant assistance from [Claude Code](https://claude.ai/code), Anthropic's AI coding assistant

## Requirements

- macOS 14.0 (Sonoma) or later

## Known Limitations

- **macOS only** — Built with SwiftUI and AppKit
- **Unsigned app** — Requires right-click "Open" on first launch (no Apple Developer certificate)
- **No cloud sync** — Board data is stored locally; sync via cloud storage by pointing to a shared `board.json`
- **Single window** — One board per application instance
- **No terminal splits in Direct mode** — Pane splitting requires the tmux backend

## License

MIT — See the [LICENSE](https://github.com/eyelock/TermQ/blob/main/LICENSE) file.

## Source Code

[github.com/eyelock/TermQ](https://github.com/eyelock/TermQ)
