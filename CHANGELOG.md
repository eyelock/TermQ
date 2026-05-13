# Changelog

All notable changes to TermQ will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed — BREAKING (MCP / CLI)

- **MCP tool names lose the `termq_` prefix.** Every TermQ MCP tool is now reachable as `mcp__termq__<name>` rather than `mcp__termq__termq_<name>`. Affected tools: `pending`, `context`, `list`, `find`, `open`, `create`, `set`, `move`, `get`, `delete`. **No alias is provided.** Anyone with `mcp__termq__termq_*` hardcoded in a CLAUDE.md, hook script, or recorded prompt must update by deleting one prefix.
- **Tag filter semantics converge on literal exact-match.** Both `find(tag:)` (MCP) and `find --tag` (CLI) now interpret `key=value` as a literal exact match (case-insensitive). Previously CLI did partial-substring match on the value while MCP did exact — they now behave identically. To regex-match, prefix with `re:`: `find(tag: "staleness=re:(stale|ageing)")` matches the value as regex; `find(tag: "re:project=org/.+")` matches the whole `key=value` string as regex. Invalid regex patterns surface an error rather than silently falling back to literal. **CLI partial-match users:** rewrite as `--tag project=re:.*` or just `--tag project` (key-only still works).

### Fixed — MCP / CLI

- **MCP resource reads now surface load errors instead of returning empty arrays.** Previously `termq://terminals`, `termq://columns`, and `termq://pending` silently returned `[]` or `{}` if the board could not be loaded — conflating "the board has zero cards" with "the install is broken" and masking the original "empty results" bug. Failures now propagate as MCP errors with descriptive messages.
- **`AppProfile` runtime injection point in `BoardLoader` / `BoardWriter`.** Methods now take a `profile: AppProfile.Variant` parameter (default `.current`) instead of `debug: Bool`. `.current` resolves to `.debug` under `TERMQ_DEBUG_BUILD` and `.production` otherwise. Test code can pass `.debug` or `.production` explicitly without recompiling.
- **Atomic read-modify-write in `BoardWriter`.** `updateCard`, `moveCard`, and `createCard` previously split their read and write across two separate `NSFileCoordinator` claims, leaving a window where two concurrent writers could both finish their reads before either wrote — the second write silently clobbering the first. They now run inside a single `writingItemAt:` claim via the new `BoardWriter.atomicUpdate(...)` helper, closing the lost-update race and the `orderIndex` collision on concurrent appends.
- **`termqmcp --verbose` logs the resolved profile and data directory at startup**, so a debug-vs-production data-directory mismatch is visible to the operator.

### Added — MCP polish

- **Tool annotations** on every MCP tool — `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`. Permissioned clients (e.g. Claude Desktop) use these to auto-allow read-only tools and prompt before destructive ones. Notable: `delete` is marked destructive (even soft-delete prompts confirmation in strict clients); `set` and `move` are marked idempotent.
- **Display titles** on every tool, resource, prompt, and prompt argument — human-readable labels surfaced in client UIs alongside the programmatic names.
- **Argument completion** (`completion/complete`) — TermQ now provides autocomplete suggestions for the `terminal_summary` prompt's `terminal` argument, matching live board terminal names by case-insensitive substring. Capped at 100 results; clients see `total` and `hasMore` so they can prompt the user to refine.
- **`notifications/message` log mirror** — `termqmcp` now emits MCP log notifications (gated by client-configured minimum level via `logging/setLevel`) for board-load failures and other operationally relevant events. Lets a remote operator observe failures without needing `--verbose` stderr access.
- **`logging/setLevel` honoured properly** — previously the request was accepted and ignored; now the configured threshold actually filters subsequent log emissions.

### Added — MCP structural (Tier 1b)

- **Resource templates** (`resources/templates/list`) — `termq://terminal/{id}`, `termq://terminal-by-name/{name}`, `termq://column/{name}`. Idiomatic per-card reads via standard `resources/read` — no per-card tool needed.
- **Structured tool output** (`outputSchema` + `structuredContent`) on all read tools (`pending`, `list`, `find`, `open`, `get`). Clients can codegen types or runtime-validate against the published schema rather than re-parsing `text` content. Legacy `text` mirror is retained for one release; payload roughly doubles in the meantime (~80 KB instead of ~40 KB on a 200-card board — acceptable for stdio).
- **Resource subscriptions** (`resources/subscribe` / `resources/unsubscribe` + `notifications/resources/updated`) — long-running clients can subscribe to `termq://terminals`, `termq://pending`, or any other resource URI and be notified when board.json changes (e.g. the user moves a card in the GUI). Backed by a `DispatchSourceFileSystemObject` watcher with a 150ms debounce window so atomic writes don't fan out to multiple notifications. The `subscribe: true` capability TermQ has declared since 0.x is now actually honoured.
- **`record_handshake` tool** — explicit, side-effect-only marker that an LLM session has consumed a terminal's context. Idiomatic pair with reading `termq://terminal/{id}` (pure). `get` retains the combined read+handshake behaviour for one release as a deprecated alias per the audit's semantic-break policy.

### Added — MCP domain symmetry (Tier 2)

- **`whoami` tool** — resolves the current card from the `TERMQ_TERMINAL_ID` environment variable. Returns null (not error) when running outside a TermQ terminal context, so top-level Claude sessions don't see a spurious failure.
- **`restore` tool + `BoardWriter.restoreCard`** — restore a soft-deleted (binned) card by clearing its `deletedAt` timestamp. Permanent deletes remain irrecoverable. Closes the asymmetry where MCP could delete but not undelete.
- **Column CRUD** — `create_column`, `rename_column`, `delete_column` tools with matching `BoardWriter.createColumn` / `renameColumn` / `deleteColumn` primitives. `delete_column` refuses by default if active cards remain; pass `force: true` to soft-delete them along with the column.
- **`list` extended:** `includeDeleted: true` to include binned cards; `cursor` + `limit` for pagination. Unpaginated calls keep returning the bare array — pagination is opt-in.
- **`find` extended:** same `cursor` + `limit` parameters as `list`. Pagination cursor is base64-encoded offset, opaque to clients.

### Added — MCP new domains (Tier 3)

- **`termq://repos` resource** — list of every registered git repository (id, name, path, worktree base, protected branches, addedAt).
- **`termq://worktrees` resource** — git worktrees enumerated across every registered repository. Per-repo failures are mirrored to `notifications/message` rather than killing the whole listing — a misconfigured repo doesn't take the rest down.
- **`termq://harnesses` resource** — installed YNH harnesses via `ynh ls --format json`. Empty array when `ynh` isn't on PATH; degradation is logged at info level for diagnostics.
- **`create_worktree` and `remove_worktree` tools** — backed by the existing `GitServiceShared` primitives. Create takes a repo UUID + branch name; remove takes a repo UUID + absolute path. `force` plumbed onto the wire surface but currently informational (GitServiceShared.removeWorktree doesn't take it yet).
- **`harness_launch` tool** — invokes `ynh run <harness>` in a working directory, optionally seeded with a prompt. Annotated `destructiveHint: true` so permissioned clients prompt; full `elicitation/create` integration is a follow-up. Output is truncated to a 4 KB suffix to keep the MCP frame bounded.

Deferred from this release: a formal `elicitation/create` flow wired into `harness_launch` (annotations carry the prompt-hint for now), `roots/list` boundary enforcement (no filesystem-touching tools currently exceed `~/Library/Application Support`), and the GitHub-PR resource (`termq://prs`) which would shell out to `gh` and needs more design.

### Added — Tooling and docs

- **`ToolParity.swift` registry** — single source of truth listing every MCP tool as `mandatoryCLI` (a matching `termqcli` subcommand must exist) or `omittedCLI` (with a stated reason). Five `ToolParityTests` enforce classification at build time: adding a tool without classifying it fails CI.
- **`Scripts/check-mcp-docs.sh`** — narrow CI gate that fails when MCP surface files (`SchemaDefinitions.swift`, `ToolParity.swift`) change without a matching `Docs/Help/reference/mcp.md` update. Override via `[no-doc]` in commit subject for genuine no-surface changes.
- **`Docs/Help/reference/mcp.md` rewritten** — reflects the full Tier 0–3 surface, includes a spec-feature support matrix at the top, documents the CLI-parity policy and its enforcement.
- **`Docs/Help/tutorials/mcp-subscriptions.md`** — new tutorial walking through the resource-subscription feature with worked code and sharp-edges section.

Known gap: the Tier 2 / Tier 3 tools introduced on the MCP surface (`restore`, `whoami`, `create_column`, `rename_column`, `delete_column`) do not yet have matching `termqcli` subcommands. The parity registry classifies them as `mandatoryCLI` so the test currently passes by name only — adding the CLI subcommands is a follow-up that will tighten the registry test to verify actual CLI command existence.

## [0.11.0]

### Added

- **Focus and profile editing** — editable harnesses gain full inline editing for focuses and profiles
  directly in the detail pane:
  - **Focuses** — add, edit, and remove focuses from the Focuses section. The edit sheet exposes
    the focus name, prompt, and optional profile binding. Changes round-trip through
    `ynh focus add`, `ynh focus update`, and `ynh focus remove`.
  - **Profiles** — add and remove profiles from the Profiles section. Each profile card carries
    an **⋯** menu with **Edit** (opens the profile sheet) and **Remove** (with confirmation).
  - **Profile hooks** — within the profile edit sheet, add and remove hooks per event via the
    same `plus.circle` / `minus.circle` affordances used at the harness level.
  - **Profile MCP servers** — add and remove MCP servers within a profile. The Add MCP sheet
    supports both command and SSE-URL server types with args, env vars, and HTTP headers.
  - **Profile includes** — the profile edit sheet's Includes section uses the unified Source Picker
    (Library / Git URL) to add includes, and a remove button to drop them.
- **Harness-level hook and MCP server editing** — the Hooks and MCP Servers sections of the
  composition view now support inline add and remove for editable harnesses:
  - Add hooks via `ynh hook add`, remove individual hook entries by index via `ynh hook remove`.
  - Add MCP servers via `ynh mcp add`, remove them by name via `ynh mcp remove`.
  - Remove buttons appear per-entry and are disabled while a mutation is in flight to prevent
    double-actions.

## [0.10.1]

### Added

- **Run with Focus on non-checked-out PRs** — the Run with Focus sheet and Quick Launch Focus submenu are now available from the Remote PR context menu even when the PR's branch is not locally checked out. TermQ resolves the correct worktree root automatically and launches the harness session against it.
- **Active terminal sidebar highlight** — the sidebar entry matching the currently active terminal is now displayed in bold, making it easier to track your position across many open sessions.

### Fixed

- YNH CLI invocations now use canonical harness IDs instead of bare names, preventing argument-parsing errors when harness names contain characters that the CLI interprets as flags.

## [0.10.0]

### Added

- **Remote PR feed** — the Repositories sidebar gains a **Local / Remote** toggle.
  Remote mode lists open pull requests for each registered GitHub repository,
  fetched via the `gh` CLI. The feed is priority-ordered: checked-out PRs pin to
  the top, then review-requested, then open non-draft with no reviewers, then
  everything else. Within each tier, PRs are sorted by `updatedAt` descending.
  - **Per-host identity** — login is resolved per-repository by calling `gh api user`
    with the repo's working directory, so orgs on github.com, GHEC, and on-prem GHE
    each resolve the correct account automatically.
  - **Configurable feed cap** — defaults to 20 PRs per repo; adjustable globally in
    **Settings → GitHub** or per-repo via `YNHPersistence`. Tier-1 (checked-out) PRs
    always appear regardless of the cap.
  - **Overflow indicator** — when the full list exceeds the cap, a `+ N more` footer
    shows the count of hidden PRs.
  - **Priority badges** — each PR row carries role badges: **you** (author),
    **review** (review requested), **assigned**, **draft**, and **checked out** (green).
- **Run with Focus sheet** — right-clicking any PR row with a checked-out worktree
  exposes **Run with Focus…**, a sheet for launching a `ynh run` harness session
  against that PR's worktree:
  - Harness picker pre-selects the last-used harness for the repo.
  - Focus picker pre-selects the repo's saved default focus (if set).
  - Vendor picker lets you override the harness default vendor; shows availability.
  - Profile picker is interactive in ad-hoc mode, locked to the focus's profile when
    a focus is selected.
  - Prompt textarea shows the focus prompt read-only; a **Customize** button unlocks
    it for editing.
  - **Stay interactive** toggle (gated on vendor capability) appends `--interactive`
    so the agent stays open after the initial focus response.
  - **Harness detail caching** — focuses and profiles are cached in-process after the
    first load; re-opening the sheet is instant. A **⟳** refresh button forces a
    re-read from disk when the harness YAML has changed.
  - Terminal cards created from the sheet are titled `focus: org/repo#N`, with the
    repo slug middle-truncated if the total would exceed 40 characters.
- **Remote PR context menu** — the PR row right-click menu now matches the local
  worktree menu structure (when the PR is checked out):
  - **Run with Focus…** and **Quick Launch Focus ▶** submenu (per-focus quick launch
    without opening the full sheet; populated automatically when harness detail is
    cached).
  - **Quick Terminal** / **Create Terminal…** — open a terminal at the worktree path.
  - **Reveal in Finder** / **Reveal in Terminal** / **Copy Branch Name**.
  - **Open PR on Remote** / **Copy PR URL** / **Update from Origin**.
  - **Show in Local** — jump to Local mode, focused on the worktree.
  - **Set Default Focus ▶** — change or clear the default focus for the repo (used as
    the pre-selection next time the Run with Focus sheet opens).
- **Prune Closed PRs** — a **⊘ Prune Closed PRs** action appears in Remote mode for
  repos with checked-out worktrees whose PRs have since been closed or merged. A
  confirmation sheet lists candidates with dirty/ahead flags; safe-to-prune rows are
  checked by default.
- **GitHub Settings tab** — new **Settings → GitHub** tab with a stepper for the
  global PR feed cap (5–100, step 5).
- **Convert to Worktree** — local branch rows gain a **Convert to Worktree** context
  menu action that creates a linked worktree for the branch without switching the main
  checkout.

- **Inline include and manifest editing** — the detail pane now exposes
  per-row edit and remove on every include of an editable harness, plus
  a manifest-level editor for free-form fields. Mutations stream through
  `IncludeMutator` / `HarnessManifestEditor` against YNH and refresh the
  detail in place.
- **Per-row delegate management** — delegates added by the host harness
  show as their own rows with edit + remove affordances, parallel to the
  include UX. Backed by `DelegateMutator` with the same source-aware
  apply path.
- **Unified Source Picker** — Install Harness, Add Include, and Add
  Delegate now flow through a single Library / Git / Path picker
  surface. Library tab pulls from `ynh marketplace` results; Git accepts
  any URL with optional ref/sha pin; Path lets you point at a local
  source directory. Replaces the previous bespoke install + add-include
  sheets.
- **Schema-1 → 2 migration coordinator** — on first launch against a YNH
  binary that has migrated `~/.ynh` to canonical-id schema 2, TermQ
  consumes the migration manifest and rewrites its persisted
  worktree↔harness associations from the old `<namespace>/<name>`
  shape to the new host-prefixed canonical id (`<host>/<org>/<repo>/<name>`).
  Idempotent — re-applying the same manifest is a no-op.
- **Quarantine sidebar group** — quarantined harnesses (entries YNH could
  not load due to a broken manifest) appear in a dedicated QUARANTINED
  group below LOCAL with per-row Restore and Drop actions. Drop is
  confirmation-gated and permanently removes the entry from
  `~/.ynh/.quarantine/broken/`.
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

- **Canonical-id at the YNH CLI boundary** — every TermQ→YNH command now
  passes `harness.id` (the canonical id YNH stamps on each harness) rather
  than the bare name. Eliminates the duplicate-name bug class where a
  registry install and a local fork sharing a name could resolve to the
  wrong target. The `id || name` fallback in `HarnessRepository` is gone
  and `Harness.id` is sourced verbatim from the YNH envelope (with a
  `namespace + "/" + name` fallback for older binaries that don't emit
  the field).
- **Fork sheet aligned with `ynh fork --name`** — the fork sheet's free-form
  Identity field is replaced with an optional Name field. The new fork's
  canonical id is always `local/<name>`; submitting with no name keeps the
  source's name. Matches what the YNH binary actually exposes.
- **Detail pane refactored** — extracted `HarnessDetailViewModel` from the view;
  source classification, editability, and update signals live in pure types
  with their own test coverage. Old feature-flagged badge retired.
- **YNH command runner is injectable** — `YNHCommandRunner` protocol
  replaces direct `CommandRunner.run` calls in repository, vendor, search,
  update-availability, harness author runners, editor registry, and
  terminal session manager. Production paths use the live runner; tests
  inject stubs to exercise success and failure branches without spawning
  real YNH subprocesses.
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
  tolerant: `YNHListEnvelope` / `YNHInfoEnvelope` accept either the 0.3
  envelope or the 0.2 bare shape, and `Harness` / `HarnessInfo` accept
  either `version_installed` or `version`. The compat layer can be
  removed once YNH 0.3 ships to the tap and a capability gate is in
  place.

## [0.9.6] — 2026-05-04

### Fixed

- **Focus stealing on MCP-driven URL deliveries** — Background `termq://`
  URL deliveries via `NSWorkspace.open(activates: false)` were triggering
  AppleEvent Reopen, and `applicationShouldHandleReopen` unconditionally
  called `makeKeyAndOrderFront`, stealing focus from whatever app the
  user was working in. The handler now only activates the window on
  genuine user-initiated reopen (unhide on Cmd+H, deminiaturize on
  Cmd+M, or bring forward when no windows are visible). Backport of
  #268.
- **Marketplace removals not persisted** — Removing a marketplace from
  Settings → External Sources didn't survive relaunch. Three concurrent
  issues fixed: the confirmation dialog read state after dismissal
  (racy), `save()` swallowed errors with `try?`, and a re-seed could
  re-add a default the user had removed. Tombstones now track removed
  defaults (`marketplaces.removedDefaultURLs.v1`); Restore Defaults
  bypasses tombstones explicitly. Backport of #264.
- **OSC 52 clipboard default mismatched Settings UI** — The runtime gate
  defaulted to `true` on unset while Settings → Data & Security
  displayed `false`, so a never-touched user saw "Off" but terminal
  programs could silently copy to the clipboard. The runtime now
  defaults to `false` to match the Settings UI. Behavior change:
  existing users who relied on the implicit-on default will need to
  enable OSC 52 explicitly. Aligned with #270.

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
