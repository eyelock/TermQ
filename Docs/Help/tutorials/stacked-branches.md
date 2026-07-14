# Stacked Branches & PRs

In this tutorial you'll break a large piece of work into a stack of small, dependent branches — each with its own pull request — and manage the whole stack from the TermQ sidebar: adding branches, switching between them, restacking after changes, submitting PRs, and syncing after merges.

**Time:** about 20 minutes
**Requires:** TermQ 0.13 or later, [git-spice](https://abhinav.github.io/git-spice/) installed, `gh` CLI authenticated, a GitHub repository registered in the sidebar

---

## What stacking is — and TermQ's model

A **stack** is a chain of branches where each builds on the one below it: `trunk ← api ← ui ← tests`. Each branch gets its own small PR targeting the branch beneath it, so reviewers see focused diffs instead of one monolith. When the bottom PR merges, the rest of the stack shifts down.

TermQ's model is deliberately simple: **a stack lives inside one worktree**. The worktree has one checked-out branch at a time — the stack's entries share that worktree's directory and its terminals. Switching entries re-points the same working directory at a different branch. (When you genuinely need two branches of the same stack open at once, see *Break-out worktrees* below.)

The one conceptual trap worth internalising up front: **uncommitted changes travel with the worktree, not the branch**. If you edit files while `ui` is checked out and then switch the worktree to `tests`, those edits would come along and land in the wrong branch. This is why TermQ *refuses* to switch a dirty worktree — commit or stash first. It's not being obstructive; it's protecting you from committing work to the wrong branch.

---

## Prerequisites

Stacking is powered by [git-spice](https://abhinav.github.io/git-spice/), a third-party CLI that TermQ detects but never bundles:

```
brew install git-spice
```

Check **Settings → Tools** — the **git-spice** card shows Installed/Missing status, the detected version and path, and a **Check Again** button after you install. git-spice reuses the `gh` CLI's authentication, so if Remote PRs already work, no extra sign-in is needed.

Then enable stacking per repository: right-click the repo row in the sidebar and choose **Enable Stacking…**. TermQ runs `gs repo init` against the repo's default branch. Repos without stacking enabled are completely unaffected — the sidebar looks exactly as before.

---

## Sidebar anatomy

Once a repo is stacked, two things change in the sidebar:

**The worktree row grows a chevron.** When a worktree's checked-out branch is part of a stack, the row becomes expandable. Expanding it shows the chain bottom-to-top, one entry per branch:

- **●** marks the entry currently checked out in *this* worktree
- **#123** — the branch's PR, coloured by status (open, merged, closed); click to open it on GitHub
- **⟳ (orange)** — *needs restack*: the branch's base has moved and it should be rebased
- **↑N unpushed** — local commits not yet pushed
- **⚠ base mismatch** — the PR targets a different base than the stack expects (happens after a downstack merge; Sync Repo fixes it)
- **↩ (jump)** — the entry is checked out in a *different* worktree; click to reveal that worktree's row

**A STACKS section appears** between the worktree list and LOCAL BRANCHES. It's the inventory: every tracked stack in the repo, whether or not it's anchored to a worktree, grouped under its bottom branch. Entries here are read-only — the worktree row is where actions live — but each entry shows the same badges, and an unanchored stack offers **New Worktree…** to check its bottom branch out and start working. Branches listed in a stack group are removed from LOCAL BRANCHES so each branch appears in exactly one place.

The WORKTREES header itself is collapsible too — if you work exclusively from the Stacks section, fold the worktree list away.

---

## Everyday operations

All of these live in the worktree row's context menu (right-click):

**Add Branch to Stack…** — creates a new branch stacked on top of the current one (or a target you pick) via `gs branch create`. Anything you have *staged* becomes the new branch's first commit; with a clean tree it creates an empty branch ready for work. If you type the name of a branch that already exists, the sheet switches to *tracking* it onto the stack instead.

**Restack Stack** — rebases every branch in the stack onto its updated parent (`gs stack restack`). Use it after amending or adding commits to a branch lower in the stack, so the branches above incorporate the change. When nothing has diverged, restack is a **no-op** — TermQ tells you "Stack already up to date" rather than staying silent. Individual entries also offer **Restack from Here** for just a branch and everything above it.

**Submit Stack** — opens a confirmation sheet listing exactly what will happen per branch: **create** a new PR or **update** the existing one. A Draft toggle opens new PRs as drafts; *update only* skips creating PRs for branches that don't have one yet. Submits are idempotent — running it again is safe. Entries offer **Submit This Branch…** for a single PR.

**Sync Repo** — the stack-aware refresh (`gs repo sync`): pulls trunk, deletes local branches whose PRs merged, and retargets/restacks the branches above a merged one. Run it after a downstack PR merges. TermQ lists any branches the sync removed ("Sync removed 2 merged branches: …") — and says "Everything in sync" when there was nothing to do. The repo row's ⟳ refresh button also uses sync automatically for stacked repos.

While any of these runs, the repo row shows a spinner and the stack actions are disabled — mutations queue one at a time per repository.

---

## Switching between entries

Expand the worktree row and **double-click** an entry (or right-click → **Switch to <branch>**) to re-point the worktree at that branch. A single click never switches — it's safe to click around and inspect.

Switches are **guarded**. TermQ refuses when:

- **The worktree is dirty** — uncommitted changes would travel to the other branch (see the trap above). Commit or stash first.
- **A terminal is open in the worktree** — a running session's working directory would have its files swapped out from under it. Close the terminal first.
- **The branch is checked out in another worktree** — git enforces one checkout per branch; the alert names the worktree that owns it.

The guard messages tell you which case you hit. The rules exist so a switch is always boring — nothing moves that you didn't commit.

---

## Break-out worktrees

Sometimes you genuinely need two branches of the same stack open at once — a harness churning on `api` while you edit `ui`. Right-click any stack entry that isn't checked out anywhere and choose **Break Out into Worktree…**. The branch gets its own worktree and behaves like any other worktree row: its own terminals, its own cards. Stack entries for it everywhere now show the ↩ indicator that jumps to its row.

One thing changes behind the scenes: git cannot rebase a branch that's checked out in another worktree, so git-spice quietly *skips* such branches during restack and sync — which would leave them stale. TermQ orchestrates around this: after a restack or sync, it finds skipped branches and runs a follow-up restack *inside* each owning worktree, provided that worktree is clean and has no open terminal (the same guards as switching). If a broken-out worktree is dirty or in use, TermQ leaves it alone and tells you — "Not restacked: feat/ui (checked out in … with uncommitted changes)" — and the orange ⟳ badge stays on that entry until you deal with it.

---

## When a restack hits conflicts

A restack or sync can stop on a merge conflict, exactly like a manual rebase. TermQ shows a banner on the affected worktree row: **"Restack paused — conflicts in N files"** with **Continue** and **Abort** buttons.

This is where TermQ's home advantage kicks in: the conflicted worktree's terminal is one click away. Open it, resolve the conflicts, `git add` the files, then click **Continue** (`gs rebase continue`). If you'd rather back out entirely, **Abort** (`gs rebase abort`) restores the pre-restack state. If the follow-up restack of a broken-out worktree is what conflicted, the banner appears on *that* worktree's row.

---

## What you learned

- A stack is a chain of dependent branches with one PR each; in TermQ a stack lives in **one worktree** and entries share its terminals
- git-spice powers stacking — `brew install git-spice`, check **Settings → Tools**, then **Enable Stacking…** per repo
- The worktree row expands into the stack chain with PR, restack, and push badges; the **STACKS** section is the repo-wide inventory
- **Add Branch to Stack**, **Restack Stack**, **Submit Stack**, and **Sync Repo** cover the daily loop — every operation confirms what it did, including "already up to date" no-ops
- Switching entries is double-click or context menu, and it's **guarded**: dirty worktrees, in-use terminals, and branches owned by other worktrees are refused — because uncommitted changes travel with the worktree, not the branch
- **Break Out into Worktree…** gives a stack entry its own worktree for concurrent sessions; TermQ restacks broken-out branches in their own worktrees afterwards, and tells you when a dirty or in-use worktree was skipped
- Conflict pauses show a banner with **Continue** / **Abort** — resolve in the worktree's own terminal

## Next

[Tutorial: CLI Automation](cli.md) — drive TermQ from scripts and CI with the `termq` command-line tool.
