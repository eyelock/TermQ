# Changelog

All notable changes to TermQ will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Harnesses sidebar tab** (feature-flagged, opt-in via Settings → YNH Harness
  Toolchain) — detects the `ynh` binary on launch and app-focus and surfaces
  the full harness lifecycle inside TermQ:
  - Installed harnesses list sourced from `ynh ls`
  - Detail pane with info, composition (`ynd compose`), dependencies, and the
    raw `.harness.json` manifest
  - Three-tab install sheet — registry search (`ynh search`), direct Git URL,
    and local source management (`ynh sources add/remove`)
  - Worktree ↔ harness linking — right-click a worktree to set, clear, or
    launch its configured harness. Linkage stored in TermQ's `ynh.json`.
  - Launch sheet with vendor, focus, prompt, working directory, and backend
    pickers, backed by `ynh run`
  - Update and uninstall from the detail pane's ⋯ menu or the sidebar
    context menu — confirmation alert warns about linked worktrees and open
    terminals before uninstalling. Transient operation terminals auto-close
    on success and stay open on failure so errors remain readable.
  - YNH subprocess stderr now surfaces directly in the detail error banner
    instead of a generic fallback
- New tutorial: **[Tutorial 13 — Harnesses](docs/Help/tutorials/13-harness-sidebar.md)**

### Changed

- **CLI renamed**: `termq` → `termqcli` to fix Swift Package Manager case-insensitivity issue
  - On case-insensitive filesystems (macOS default), `termq` and `TermQ` resolve to the same file
  - This caused build issues where the CLI binary would overwrite the GUI binary
  - All CLI commands now use `termqcli` prefix: `termqcli list`, `termqcli open`, etc.

## [0.5.2] - 2026-01-14

### Fixed

- **Critical crash fix**: Resolved Swift 6 concurrency crash when dragging cards
  - The crash was caused by dispatch source handlers inheriting @MainActor isolation
  - Created separate FileMonitor helper class to avoid actor isolation in dispatch callbacks
- Build reliability improvements to prevent incorrect binary from being bundled

## [0.5.1] - 2026-01-14

### Fixed

- Release workflow now correctly generates Info.plist for app bundles

## [0.5.0] - 2026-01-14

### Added

- **MCP Server Integration** (`termqmcp`): LLM agents can now interact with TermQ via Model Context Protocol
  - `termq_list`, `termq_get`, `termq_find`, `termq_open` tools for reading terminal state
  - `termq_create`, `termq_set`, `termq_move`, `termq_pending`, `termq_context` for automation
- **File monitoring**: Board changes from MCP server are automatically detected and refreshed
- **MCP status indicator**: Shows whether the MCP server is installed and if LLM has accessed current terminal
- **Generate Init Command**: New section in Settings > Agents to generate terminal init commands
- **Terminal environment variables**: `TERMQ_ID`, `TERMQ_NAME`, etc. available in terminal sessions
- **LLM-friendly CLI commands**: `termq list`, `termq get`, `termq set`, `termq pending` for automation
- Column descriptions: Add optional descriptions to columns

### Changed

- Settings reorganized into General/Tools tabs
- Terminal Editor reorganized into General/Advanced tabs
- Claude AI assistant configuration added

### Fixed

- Focus stealing prevented during terminal text selection
- Column drag-to-reorder functionality restored
- CLI deadlock when launching TermQ app resolved

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

[0.5.0]: https://github.com/eyelock/TermQ/releases/tag/v0.5.0
[0.4.0]: https://github.com/eyelock/TermQ/releases/tag/v0.4.0
[0.3.1]: https://github.com/eyelock/TermQ/releases/tag/v0.3.1
[0.3.0]: https://github.com/eyelock/TermQ/releases/tag/v0.3.0
[0.1.0]: https://github.com/eyelock/TermQ/releases/tag/v0.1.0
