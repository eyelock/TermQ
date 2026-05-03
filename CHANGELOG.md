# Changelog

All notable changes to TermQ will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.9.5] — 2026-05-03

### Fixed

- **Harness list and detail never load (ynh 0.3+ JSON shape change)** —
  Three breaking changes in ynh 0.3.0's structured-output format
  combined to leave TermQ with an empty harness list and unreadable
  detail responses:
  1. `ynh ls --format json` switched from emitting a bare harness
     array to an envelope object `{capabilities, harnesses,
     ynh_version}`.
  2. `ynh info <name> --format json` likewise switched to an envelope
     `{capabilities, harness, ynh_version}`.
  3. The `version` field on each harness row was renamed to
     `version_installed` in both `ynh ls` and `ynh info` payloads.
  The combined effect on v0.9.4 was every dependent surface — the
  Harnesses sidebar tab, harness detail view, the launch sheet
  (rendered as a blank rounded pill or did nothing at all when invoked
  from a worktree row), install/uninstall/update flows — silently
  no-op'd. Decoders updated to the envelope shapes and the
  `version_installed` JSON key. The blank-sheet symptom reported
  against v0.9.4 was a downstream consequence; the v0.9.4 identifier
  fallback remains in place.

## [0.9.4] — 2026-05-02

### Fixed

- **Launch-from-worktree blank sheet** — Launch <harness> from a worktree
  row (or a repo's default-harness context menu) now resolves the harness
  correctly when the install is namespaced. `HarnessRepository` previously
  matched `selectedHarnessName` against `Harness.id` only — for namespaced
  installs `id` is `"namespace/name"` while `YNHPersistence` keys
  associations by bare `name`, so the lookup missed and the launch sheet
  rendered with no content (a blank rounded sheet that never populated and
  could only be dismissed with Esc). Lookup is now tolerant of either
  form, and the stale-selection eviction in `refresh()` matches the same
  rule.

## [0.9.3] — 2026-04-29

### Fixed

- Fix EXC_BREAKPOINT crash caused by @MainActor isolation inherited by system-dispatched closures in TerminalLinkResolver and TmuxControlModeSession

## [0.9.2] — 2026-04-28

### Fixed

- Re-register URL Apple Event handler after SwiftUI scene setup (#239)
- Replace -50 Finder dialog error with correct file/URL open handling (#240)

## [0.9.1] — 2026-04-28

### Fixed

- Fix appcast not updating on stable release (#233)
- Fix uninstall for local harnesses with no YNH install record (#234)

## [0.9.0]

### Added

- **YNH Harness sidebar** (opt-in via Settings → YNH Harness Toolchain) — full
  harness lifecycle inside TermQ, built across the 0.9 beta series:
  - Detects the `ynh` binary on launch and app-focus
  - Installed harnesses list sourced from `ynh ls`
  - Detail pane with info, composition (`ynd compose`), dependencies, and the
    raw `.harness.json` manifest
  - Three-tab install sheet — registry search (`ynh search`), direct Git URL,
    and local source management (`ynh sources add/remove`)
  - Worktree ↔ harness linking — right-click a worktree to set, clear, or
    launch its configured harness; linkage stored in TermQ's `ynh.json`
  - Launch sheet with vendor, focus, prompt, working directory, and backend
    pickers, backed by `ynh run`
  - Update and uninstall from the detail pane's ⋯ menu or the sidebar
    context menu — confirmation alert warns about linked worktrees and open
    terminals before uninstalling; transient operation terminals auto-close
    on success and stay open on failure so errors remain readable
  - YNH subprocess stderr surfaces directly in the detail error banner
  - Harness-launched cards persist and deduplicate on re-launch
  - Tree layout with grouping for harness and marketplace sidebars
  - Pin marketplace and harness registry to a git ref
- **YNH 0.2 support** — namespace model, marketplace rename, capabilities gate
- **Marketplace browser** — registry search, direct Git URL install, harness wizard
- **Git worktree sidebar** — integrated worktree management with branch operations
  and drag-and-drop ordering across sidebar tabs
- **Open in Editor** submenu for worktree and harness context menus
- **Right-click context menu** in terminal with Copy and Paste
- **Protected branches deny-list** for Prune Merged Branches
- **Auto-tags, terminal naming, and tag tooltip**
- **In-app diagnostics log viewer**
- **Release notes generation** from conventional commits

### Changed

- Worktree creation unified into a single sheet
- Harness and marketplace sidebars adopt tree layout with grouping
- Security settings inherited from global defaults when creating new terminals
- TUI rendering corrected in tmux control mode terminals

### Fixed

- Fix upward scroll during text selection against streaming output
- Restore Reveal in Terminal across sidebar tabs
- Prevent SwiftUI from closing main window on URL events
- Spontaneous window hide — guard `NSApp.unhide` against calling on visible app
- Worktree row shows spinner during deletion
- Text selection and scroll in terminals with mouse tracking
- Restore tab drag-and-drop
- GitHub install and `ynh include add` GitHub source shorthand expansion
- Relative plugin paths in `ynh include add`
- Scroll tab bar to reveal selected terminal on sidebar jump
- Preserve tmux pane focus across SwiftUI re-renders
- Use async `panel.begin()` for Browse button in path pickers

### Security

- Migrate SecureStorage to Data Protection Keychain
- Use file-based key storage in debug builds

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
