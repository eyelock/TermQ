# Changelog

All notable changes to TermQ will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Harness Management Phase 1** — first slice of the harness-as-first-class-citizen
  rework. Registry harnesses, local harnesses, and forks now have distinct
  identities, editability rules, and provenance display in TermQ.
- **Source badges** — sidebar rows and detail pane header show a provenance
  chip: registry name (registry installs), short Git URL (git installs),
  `Local` (path installs), or `Forked from <registry>` (forked-locals).
- **Read-only indicator** — registry harnesses display a Read-only pill;
  surfaces that direct edits will be overwritten by the next `ynh update`.
- **Update detection with three-state drift signal**
  - **Versioned** — manifest `version` bumped upstream → orange dot, info
    banner, single-click Update.
  - **Unversioned drift** — content changed upstream without a version bump
    → amber warning triangle, warning banner, confirmation step in the
    Update sheet listing each drifted include path with `installed → available`
    SHAs. Surfaces the supply-chain signal explicitly.
  - **None** — clean.
- **Fork to local** — actions menu offers Fork to local on registry harnesses;
  single-call flow against pointer-model YNH (`ynh fork --to <path>`); creates
  one editable working tree, no copy under `~/.ynh/harnesses/`. Detail pane
  shows ghost origin via `installed_from.forked_from`.
- **Duplicate** — local-only renamed copy via `ynh fork --to <path> --name
  <newname>` single call. Hidden for registry harnesses (Fork covers that
  intent). Appears in sidebar context menu and detail action menu.
- **Action menu parity** — sidebar context menu and detail action menu share
  the same canonical layout in five groups (Run, Location, Actions, Help,
  Destructive). Sidebar drops Help and advanced Actions; detail keeps
  everything. "Open in…" submenu (VS Code, Cursor, Zed, etc.), Reveal in
  Terminal, Open in browser (URL sources), Copy as Pathname all consistent.
- **Editable path resolution** — for forked-locals, Reveal/Open/Copy actions
  target the editable source tree (`installed_from.source`), not the YNH
  install slot. Single canonical "where this lives on disk" location.
- **Sidebar header spinner** — global probe in flight shows a spinner next
  to the "Harnesses" title; per-harness operations show the spinner next to
  the row.
- **Vendor override picker** — per-harness vendor override (claude / codex /
  cursor) persists across launches, surfaces as a picker badge in the detail
  header.
- **Update menu hidden for forks** — YNH explicitly refuses `ynh update` on
  forks; menu reflects that rather than offering an action that always errors.

### Changed

- **Detail pane refactored** — extracted `HarnessDetailViewModel` from the view;
  source classification, editability, and update signals live in pure types
  with their own test coverage. Old feature-flagged badge retired.
- **YNH JSON envelope** — TermQ now reads `capabilities` and `ynh_version`
  from the structured-output envelope (YNH 0.3.0+) and gates Phase 1 features
  behind a version probe.
- **Tolerant decoder** — `Harness` decoder accepts `null` for `includes` and
  `delegates_to` (which YNH emits for broken installs whose source path is
  missing). A single bad row no longer collapses the whole sidebar.
- **Settings layering** — introduced `SettingsStore` as the single owner for
  user preferences, with explicit defaults → user → per-card override
  resolution. The four per-terminal fields the audit named — safe paste,
  font size, theme, and backend — now carry an Optional override on the card
  rather than being snapshotted from `UserDefaults` at create time. New
  cards inherit the global default and track future changes to it; the card
  editor exposes an "Override default" toggle for each field.

  **Upgrade behaviour for existing cards:** cards persisted before this
  release keep their concrete values as explicit overrides. They will
  *not* track future changes to the matching global default. To opt back
  into the global, open the card editor and turn the "Override default"
  toggle off. This is intentional — it preserves "what users had" through
  the upgrade.

## [0.9.7] — 2026-05-07

### Fixed

- **Harness loading broken against YNH 0.2.x** — v0.9.5/0.9.6 hard-coded
  the YNH 0.3 structured-output shape (`{harnesses: [...]}` envelope,
  `version_installed` field), but YNH 0.3 was never published to the
  Homebrew tap. Every user running `brew install ynh` is on YNH 0.2.3,
  which emits a bare `[Harness]` array with `version`. The mismatch
  left the Harnesses sidebar empty and produced a blank Launch card on
  worktree rows that already had a harness associated. Decoding is now
  tolerant: `HarnessListResponse` / `HarnessInfoResponse` accept either
  the 0.3 envelope or the 0.2 bare shape, and `Harness` / `HarnessInfo`
  accept either `version_installed` or `version`. The compat layer can be
  removed once YNH 0.3 ships to the tap and a capability gate is in place.

## [0.9.6] — 2026-05-05

### Fixed

- **Focus stealing on MCP-driven URL deliveries** — Background `termq://`
  URL deliveries via `NSWorkspace.open(activates: false)` were triggering
  AppleEvent Reopen, and `applicationShouldHandleReopen` unconditionally
  called `makeKeyAndOrderFront`, stealing focus from whatever app the
  user was working in. The handler now only activates the window on
  genuine user-initiated reopen (unhide on Cmd+H, deminiaturize on
  Cmd+M, or bring forward when no windows are visible).
- **Marketplace removals not persisted** — Removing a marketplace from
  Settings → External Sources didn't survive relaunch. Three concurrent
  issues fixed: the confirmation dialog read state after dismissal
  (racy), `save()` swallowed errors with `try?`, and a re-seed could
  re-add a default the user had removed. Tombstones now track removed
  defaults (`marketplaces.removedDefaultURLs.v1`); Restore Defaults
  bypasses tombstones explicitly.
- **OSC 52 clipboard default mismatched Settings UI** — The runtime gate
  defaulted to `true` on unset while Settings → Data & Security
  displayed `false`, so a never-touched user saw "Off" but terminal
  programs could silently copy to the clipboard. The runtime now
  defaults to `false` to match the Settings UI. Behavior change:
  existing users who relied on the implicit-on default will need to
  enable OSC 52 explicitly.

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
- **Sheet first-paint pill** — Fork, Update, Duplicate, Install, Add
  Marketplace, and Session Recovery sheets now apply their frame at the
  `.sheet` content closure rather than inside the sheet body. Eliminates
  the rounded-rect placeholder that flashed before content resolved.
- **Phantom drift detection** — pre-pointer-model YNH builds (and migrated
  installs) no longer surface false-positive drift dots. Drift is only
  reported when both `installed` and `available` SHAs are present and differ.

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
