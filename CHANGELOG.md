# Changelog

All notable changes to TermQ will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-01-11

### Added

- 8 built-in terminal color themes (Dracula, Nord, Solarized, One Dark, etc.)
- Command palette for quick terminal switching (⌘K)
- Session export to save terminal buffer to text files
- Terminal buffer search (⌘F)
- Zoom mode to maximize terminal view (⌘⇧Z)
- Smart paste with dangerous content warnings
- Custom font support per terminal
- Drag-drop reordering for columns
- Init commands and LLM prompt fields on terminal cards
- Badge fields with comma parsing and open tab indicators
- Terminal bell notifications and OSC sequence support
- Native Terminal.app integration (launch at current directory)
- Session tabs with favourites and drag-drop reordering
- Bin feature for soft-delete terminal recovery
- Copy-on-select option in preferences
- Auto-scroll during text selection
- Per-terminal settings
- Alternate scroll mode for mouse wheel in fullscreen apps
- Colored column dropdown in toolbar
- Docsify server for help documentation preview
- Manual release target (`make publish-release`)

### Changed

- Reorganized documentation structure with new screenshots
- Improved card layout (badges after header, tags at bottom)
- Updated icons

### Fixed

- Column dropdown styling
- Drag-to-reorder cards upward within columns
- Delete new column when cancelling creation dialog
- UI polish and bell callback reliability
- Debug/release build isolation
- Window drag scroll bug

## [0.3.1] - 2025-12-15

### Added

- Searchable Help window

### Fixed

- Copy/paste functionality (SwiftTerm upgrade)

## [0.3.0] - 2025-12-01

### Added

- Pinned terminals with quick-switch tabs
- Keyboard shortcuts for terminal management
- Quick new terminal button in focused terminal toolbar
- Pin toggle in board view
- Responsive columns with consolidated toolbar
- `make run` target to build and launch app

### Fixed

- Terminal CWD switching
- Switch to new terminal after creation

## [0.1.0] - 2025-11-15

### Added

- Initial public release
- Kanban board layout for organizing terminal sessions
- Persistent terminal sessions across views
- CLI tool (`termq open`) for launching terminals
- Settings for CLI installation
- Visible delete button with confirmation dialog
- Basic terminal card management

[0.4.0]: https://github.com/eyelock/TermQ/releases/tag/v0.4.0
[0.3.1]: https://github.com/eyelock/TermQ/releases/tag/v0.3.1
[0.3.0]: https://github.com/eyelock/TermQ/releases/tag/v0.3.0
[0.1.0]: https://github.com/eyelock/TermQ/releases/tag/v0.1.0
