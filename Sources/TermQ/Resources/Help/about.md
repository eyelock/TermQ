# About TermQ

**TermQ** - Kanban-style Terminal Queue Manager

A macOS application for organizing multiple terminal sessions in a visual board layout.

## Features

- Kanban board layout with customizable columns
- Persistent terminal sessions
- Pinned terminals with tab navigation
- Command palette for quick navigation
- 8 built-in color themes
- Zoom mode and terminal search
- Session export to text files
- Smart paste with safety warnings
- Per-terminal fonts and init commands
- Native Terminal.app integration
- Rich metadata (titles, descriptions, badges, tags)
- Drag & drop for terminals and columns
- CLI tool for shell integration
- Comprehensive keyboard shortcuts
- Bin with soft-delete and recovery

## Credits

- The heavy lifting for terminal emulation is done by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) - a fantastic library by Miguel de Icaza. 
- This project was built with significant assistance from [Claude Code](https://claude.ai/code), Anthropic's AI coding assistant.

## Requirements

- macOS 14.0 (Sonoma) or later

## Known Limitations

- **macOS only** - Built specifically for macOS using SwiftUI and AppKit
- **Unsigned app** - Requires right-click "Open" on first launch (no Apple Developer certificate)
- **No cloud sync** - Board data is stored locally only
- **Single window** - One board per application instance
- **No terminal multiplexing** - Each card is a single terminal session (no splits/panes)

These limitations may be addressed in future versions based on community interest.

## License

MIT License

## Source Code

[github.com/eyelock/TermQ](https://github.com/eyelock/TermQ)
