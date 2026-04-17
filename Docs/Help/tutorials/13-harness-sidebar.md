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

## 13.3 — YNH detection states

TermQ auto-detects the `ynh` binary on focus and when the tab is activated. There are three possible states:

**1. `ynh` binary not installed.**

![YNH not installed](../Images/harness-ynh-not-installed.png)

Install YNH via its documented method (Homebrew, release binary, `go install`), then click the refresh button in the tab header. No restart needed — TermQ rechecks on every app-focus event.

**2. `ynh` binary installed, but not initialised.**

![YNH init required](../Images/harness-ynh-init-required.png)

YNH keeps its state in `~/.ynh/`. Run `ynh init` once in any terminal to create the directory. TermQ will detect the change the next time it polls.

**3. `ynh` ready.** The harness list appears.

> **Where TermQ looks:** `PATH`, then common fallbacks (`/opt/homebrew/bin`, `/usr/local/bin`, `~/go/bin`). If yours is elsewhere, set a custom path in Settings → YNH Harness Toolchain.

---

## 13.4 — Installing your first harness

Click the **+** button in the Harnesses tab header. The **Install Harness** sheet opens with three tabs.

### Search

![Install Sheet — Search](../Images/harness-install-sheet-search.png)

The Search tab queries configured YNH registries and local sources via `ynh search`. Type a term — results update live. Each row shows the harness name, version, description, vendor chips, and where it came from ("from \<registry\>" or "from \<source\>").

Click **Install** on any row. TermQ opens a transient terminal tab running `ynh install \<name\>`, shows the output, and auto-closes the tab on success.

> **No search results?** Search only finds harnesses in configured registries and sources. If you haven't added either, Search will always be empty — use the Git or Sources tabs instead.

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

This is the connective tissue that makes harnesses useful: tell TermQ which harness a worktree should use, and every terminal launched at that worktree inherits the harness configuration.

Switch to the **Repositories** tab. Right-click any worktree row.

![Worktree Context Menu](../Images/harness-worktree-context-menu.png)

Use **Set Harness…** to pick from your installed list, or **Clear Harness** to unlink. The choice persists in TermQ's `ynh.json` (never in YNH's own storage — TermQ owns its side of the mapping).

Once linked, the worktree row shows a harness chip, and the context menu gains a **Launch \<harness-name\>** item that skips the usual picker.

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

## 13.10 — What's next

The Harnesses tab covers install, update, uninstall, launching, and worktree linkage. In-app harness authoring — scaffolding a new harness and populating it with marketplace picks in one flow — is on the roadmap.

For now, author harnesses on the command line with `ynd create harness \<name\>` and install them via the **Sources** or **From Git** tabs.

> **Feedback:** the Harnesses tab is deliberately feature-flagged for 0.8 so we can iterate on the rough edges. If something feels wrong, please [open an issue](https://github.com/eyelock/termq/issues).
