---
name: commit-conventions
description: TermQ commit, branch, and PR conventions. Load when creating commits, branches, or pull requests.
---

# Commit Conventions

## ABSOLUTE RULE — NEVER COMMIT DIRECTLY TO MAIN OR DEVELOP

Every change goes through a branch and PR — no exceptions, no matter how small or urgent.

- **Feature/fix work:** branch from `develop`, PR back into `develop`
- **Release promotion:** PR from `develop` → `main` (you open this at release time)
- **Hotfix:** branch from a release tag, fix directly on hotfix branch, CI passes, tag fires release from hotfix branch — `main` never receives the commit directly; fix reaches `develop` via a forward-port PR after shipping

If the user has not yet created a branch, create one before touching any files:

```bash
git checkout -b <type>-<description>
```

Only the user can authorise a direct push to `main` or `develop`, and only for a specific stated technical reason. Never decide this unilaterally.

---

## Branch Naming

Use hyphens (not slashes) — keeps worktree directories flat and scannable:

```
feat-<description>
fix-<description>
refactor-<description>
docs-<description>
ci-<description>
test-<description>
```

Examples: `feat-terminal-quick-actions`, `fix-terminal-selection-focus`, `ci-persistent-permissions`

## Commit Message Format

Use Conventional Commits:

```
<type>(<scope>): <subject>

<body — explain WHY, not WHAT>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

**Types:** `feat` `fix` `refactor` `docs` `test` `ci` `perf` `style` `chore`

**Scopes (optional):** `cli` `mcp` `ui` `core` `build` `localization`

Pass via HEREDOC to avoid quoting issues:
```bash
git commit -m "$(cat <<'EOF'
feat(ui): Add quick terminal creation button

Adds a "+" button in the toolbar for quickly creating terminals
without using keyboard shortcuts.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

## Commit Count Before Pushing

Ask: **what is the minimum number of commits that meaningfully separates this work?**

Feature/fix branch PRs use squash-merge (`gh pr merge --squash`), so branch commits are ephemeral — they become one commit on `develop` regardless. Their only job is to help a reviewer understand the PR. That means:

- Lean toward 1–3 commits per PR, one per logical concern
- WIP checkpoints, format commits, and implementation-journey fixes → squash them away
- The PR description carries the narrative; commits are just grouping for review

```bash
git log origin/develop..HEAD --oneline   # read it — if you'd be embarrassed showing it, squash
git rebase -i origin/develop             # fixup/reword until only meaningful separations remain
```

A common clean split: one commit for code changes, one for documentation or tooling changes. Don't over-invest in commit granularity on a branch that will be squashed.

> Note: for the `develop → main` release promotion PR, these become `origin/main`.

## Before Creating a PR

Ensure the branch is up-to-date with the base branch (`develop` for feature branches):

```bash
git fetch origin develop
git log HEAD..origin/develop --oneline   # if output, merge first
git merge origin/develop
git push
```

## PR Description Template

```markdown
## Summary
Brief overview of changes and why.

## Changes
- Change 1
- Change 2

## Testing
- [ ] make check passes
- [ ] Manual testing completed
- [ ] Localization validated (if UI changes)

## Related Issues
Fixes #123

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## PR Title

Same format as commit message: `feat(scope): Brief description`

## Merge Rules

**NEVER use `gh pr merge --admin`** — bypasses CI, strictly forbidden.
**NEVER use `gh pr merge --auto`** — sets auto-merge on GitHub; only the user may do this.

Only merge when:
- All CI checks pass
- All review comments addressed and conversations resolved
- Branch is up-to-date with base

```bash
gh pr checks         # verify all pass
gh pr view --comments  # verify no unresolved comments
gh pr merge --squash   # feature/fix branches → develop
```

**Exception — release promotion PR (`develop` → `main`):** always use `--merge` (true merge), never `--squash`. Squash loses ancestry and makes `git log v{VERSION}..develop` show the entire history as if nothing was released.

```bash
gh pr merge --merge   # develop → main only
```

## Post-Merge Cleanup

**Order matters** — follow exactly to avoid CWD becoming invalid.

```bash
# 1. Capture the main repo path and branch name BEFORE moving anywhere
MAIN_REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "<main-repo-path>")
BRANCH=<branch-name>

# 2. Verify merged into develop (feature branches) or main (release PRs)
git -C "$MAIN_REPO" branch -r --merged origin/develop | grep "$BRANCH"

# 3. Pivot CWD to main repo FIRST (before removing worktree — once removed, CWD is invalid)
cd "$MAIN_REPO"

# 4. Remove worktree (path relative to main repo)
git worktree remove ../TermQ-worktrees/"$BRANCH"

# 5. Delete local branch
git branch -d "$BRANCH"

# 6. Delete remote branch only if it still exists (GitHub auto-deletes on merge)
git ls-remote --exit-code origin "$BRANCH" 2>/dev/null && git push origin --delete "$BRANCH" || echo "Remote branch already deleted"
```

**Never** run cleanup from inside the worktree — `git worktree remove` and `git branch -d` must
run from the main repo. **Never** assume the remote branch still exists after merge.
