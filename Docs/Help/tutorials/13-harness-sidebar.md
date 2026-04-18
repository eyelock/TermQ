# Tutorial 13: Harnesses

In this tutorial you'll connect TermQ to [YNH](https://github.com/eyelock/ynh), browse and install AI harnesses from registries, Git URLs, and local sources, then launch them in dedicated terminal sessions — all without leaving the app.

By the end you'll know how to enable the Harnesses tab, run through the YNH detection and setup flow, install your first harness, link it to a git worktree, and manage the full lifecycle including updates and uninstalls.

**Time:** about 20 minutes
**Requires:** TermQ 0.8 or later, [YNH CLI](https://github.com/eyelock/ynh) installed

---

## 13.1 — What the Harnesses tab is for

A **harness** is a reusable bundle of AI configuration — skills, rules, MCP servers, prompt profiles — that you can apply to any directory. Instead of re-configuring Claude, Cursor, or your other AI tools per project, you install a harness once and tell TermQ which worktrees should use it.

The Harnesses tab brings this workflow into TermQ directly:

- Detect whether YNH is installed and ready on this machine
- Browse and install harnesses from registries, Git, or local source directories
- View a full breakdown of what each harness contains (hooks, MCP servers, profiles, focuses)
- Link git worktrees to harnesses so launching a terminal "just works"
- Update and uninstall harnesses with one right-click

![Harnesses Sidebar Overview](../Images/harness-sidebar-overview.png)

The tab sits alongside **Repositories** as a segmented picker at the top of the sidebar.

---

## 13.2 — Enabling the Harnesses tab

The Harnesses tab is **opt-in** for 0.8. Open Settings (**⌘,**) and find the **YNH Harness Toolchain** section.

![Feature flag setting](../Images/harness-feature-flag-settings.png)

Toggle **Enable Harnesses tab**. The sidebar now shows a two-segment picker at the top.

Switching tabs in the sidebar persists across launches — if you end a session in Harnesses, you come back to Harnesses next time.

---

## 13.3 — YNH detection

TermQ auto-detects the `ynh` binary on launch and on app focus. If it's not found, the tab shows an install prompt:

![YNH not installed](../Images/harness-ynh-not-installed.png)

Install YNH via its documented method (Homebrew, release binary, `go install`), then click the refresh button in the tab header. No restart needed — TermQ rechecks on every app-focus event.

When YNH is installed and ready, the harness list appears.

> **Where TermQ looks:** `PATH`, then common fallbacks (`/opt/homebrew/bin`, `/usr/local/bin`, `~/go/bin`). If yours is elsewhere, set a custom path in Settings → YNH Harness Toolchain.

---

## 13.4 — Installing your first harness

Click the **+** button in the Harnesses tab header. The **Install Harness** sheet opens with three tabs.

### Step 0 — Add a registry first (recommended)

Search only finds harnesses in configured YNH registries. On a fresh YNH install, no registries are configured, so the Search tab will be empty.

Click the **globe** (🌐) button in the Harnesses sidebar header to add a registry.

![Add Registry Sheet](../Images/harness-add-registry.png)

**Walk-through: add the eyelock/assistants registry**

1. Click the **globe** button.
2. Paste this URL into the **Registry URL** field:
   ```
   https://github.com/eyelock/assistants
   ```
3. Click **Add**. TermQ runs `ynh registry add https://github.com/eyelock/assistants` in a transient terminal, which clones the registry index locally. The terminal auto-closes on success.

Once the registry is added, open the **Install Harness** sheet (**+** button) and switch to **Search** — harnesses from `eyelock/assistants` now appear in search results.

**Install a harness from search:**

1. Click **+** to open the Install sheet.
2. Type a search term — for example `dev` or `ynh-dev`.
3. Click **Install** next to the harness you want.

TermQ runs `ynh install \<name\>`, streams the output in a transient terminal, and auto-closes on success. The harness appears in the sidebar list immediately.

### Search

![Install Sheet — Search](../Images/harness-install-sheet-search.png)

The Search tab queries configured YNH registries and local sources via `ynh search`. Type a term — results update live. Each row shows the harness name, version, description, vendor chips, and where it came from ("from \<registry\>" or "from \<source\>").

Click **Install** on any row. TermQ opens a transient terminal tab running `ynh install \<name\>`, shows the output, and auto-closes the tab on success.

> **No search results?** Add a registry first — see Step 0 above. If registries are configured and results are still empty, the registry index may not contain a harness matching your search term.

### From Git

![Install Sheet — From Git](../Images/harness-install-sheet-git.png)

Install directly from any Git URL. The Subpath field is optional — use it when a monorepo has a harness at `ynh/my-harness` rather than at the root.

A live command preview shows the exact `ynh install` invocation TermQ will run, so you can sanity-check the URL before clicking **Install**.

### Sources

![Install Sheet — Sources](../Images/harness-install-sheet-sources.png)

Local source directories are places YNH searches when you run `ynh search` or `ynh install \<name\>`. They're ideal for harnesses you're authoring locally and iterating on.

Click **Add Source…** to pick a directory. The row shows the source name, path, and harness count — the count renders in orange when zero, which usually means the directory doesn't contain any `.harness.json` files yet.

---

## 13.5 — Reading the detail pane

Click a harness in the list to open its detail pane on the right.

![Harness Detail Overview](../Images/harness-detail-overview.png)

The pane is split into sections:

- **Header** — name, version, description, vendor badge, source chip, and action buttons (Launch, ⋯ menu, close ×)
- **Linked Worktrees** — any git worktrees configured to use this harness; each row has a quick Launch button
- **Information** — install path, source, install timestamp
- **Artifacts** — summary counts from the harness's own configuration
- **Composition** — resolved hooks, MCP servers, profiles, and focuses after `ynd compose` merges includes
- **Dependencies** — other harnesses this one includes, delegates to, or picks from
- **Manifest** — the raw `.harness.json`, collapsible, copyable

---

## 13.6 — Linking a worktree to a harness

This is the connective tissue that makes harnesses useful: tell TermQ which harness a worktree should use, and clicking the worktree row will launch it automatically.

### Repository default vs. worktree override

There are two levels of linkage, both accessible from the **Repositories** sidebar:

**Repository default:** Right-click the **repo header row** (the row showing the repo name). Choose **Set Harness…** to pick a default that applies to every worktree in that repo unless overridden. A green jigsaw icon appears on the repo header.

**Worktree override:** Right-click any **worktree row** — including the main worktree. Choose **Set Harness…** to assign a harness specifically to that worktree. An orange jigsaw icon appears on the row.

Worktrees that inherit from the repo default (no own override) show a dimmed jigsaw badge.

The choice persists in TermQ's `ynh.json` (never in YNH's own storage — TermQ owns its side of the mapping).

### Auto-launch

Once a harness is linked, **clicking the branch name** in the worktree row launches it immediately — no sheet, no prompts. TermQ creates a transient terminal running `ynh run <harness>` at the worktree path.

The context menu also gains a **Launch `<harness>`** item as the first entry, for when you want the full launch sheet (vendor, focus, backend, prompt options).

---

## 13.7 — Launching a harness

Click **Launch** on any harness row in the sidebar (or the Launch button in the detail header). The launch sheet opens.

![Launch Sheet](../Images/harness-launch-sheet.png)

Fields:

- **Vendor** — which AI client to launch under (Claude, Cursor, etc.). The default is taken from the harness's `default_vendor`, or the worktree link if one exists.
- **Focus** — optionally narrow the launch to a specific profile within the harness. Mutually exclusive with Prompt.
- **Working Directory** — where the vendor client runs. Pre-filled when launched from a worktree context.
- **Prompt** — optional text sent directly to the client on launch. Mutually exclusive with Focus.
- **Backend** — direct shell or tmux session (see Tutorial 5).

Click **Launch**. TermQ creates a new transient terminal card running `ynh run \<harness\> …` and immediately focuses it.

---

## 13.8 — Updating a harness

Open the harness detail pane and click the **⋯** menu next to Launch.

![Detail More-actions menu](../Images/harness-detail-more-menu.png)

Click **Update**. TermQ opens a transient terminal running `ynh update \<name\>`, streams the output, and auto-closes on success. The detail cache is invalidated so the next detail view you open shows fresh data.

If the update fails (non-zero exit), the terminal stays open so you can read the error — no silent failures.

---

## 13.9 — Uninstalling a harness

From the same **⋯** menu, click **Uninstall**. A confirmation alert appears.

![Uninstall Confirmation](../Images/harness-uninstall-alert.png)

The alert warns you about:

- **Linked worktrees** — if any worktrees are configured for this harness, their associations will be cleared
- **Open terminals** — if any active terminal cards are tagged with this harness, they stay open (the harness itself goes away but existing sessions keep their environment)

Click **Uninstall** to proceed. TermQ runs `ynh uninstall \<name\>` in a transient terminal, auto-closes on success, clears any worktree associations, and refreshes the list.

The same action is also in the right-click menu on any harness row, if you prefer not to open the detail first.

---

## 13.10 — Exporting a harness as a marketplace package

If you author harnesses and want to share them — or turn a private harness into a marketplace that other TermQ users can browse — you can export it directly from the sidebar.

**Requires:** YND CLI installed (the `ynd` authoring toolchain).

Right-click a harness row and choose **Export as Marketplace…**.

A directory picker opens. Choose where you want the export to land. TermQ then opens a transient terminal running:

```
ynd export <harness-path> -o <output-dir>
```

The output directory receives a `marketplace.json` index (in the appropriate vendor format) that TermQ — or any other YNH-compatible client — can consume as a marketplace source.

The terminal stays open so you can read any output or errors. It auto-closes on success.

> **Note:** Export requires the `ynd` binary (part of the YNH toolchain) in addition to `ynh`. If `ynd` is not detected, the menu item is absent.

---

## 13.11 — What's next

The Harnesses tab covers install, update, uninstall, launching, worktree linkage, and export.

To go further — creating a new harness from scratch and populating it with skills and agents from community marketplaces — continue to **[Tutorial 14: Marketplace Browser & Harness Authoring](14-marketplace.md)**.

> **Feedback:** the Harnesses tab is deliberately feature-flagged for 0.8 so we can iterate on the rough edges. If something feels wrong, please [open an issue](https://github.com/eyelock/termq/issues).
