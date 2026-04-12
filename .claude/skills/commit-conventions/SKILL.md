---
name: commit-conventions
description: TermQ commit, branch, and PR conventions. Load when creating commits, branches, or pull requests.
---

# Commit Conventions

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

## Before Creating a PR

Ensure the branch is up-to-date with main:

```bash
git fetch origin main
git log HEAD..origin/main --oneline   # if output, merge first
git merge origin/main
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

**NEVER use `gh pr merge --admin`** — this bypasses CI and is strictly forbidden.

Only merge when:
- All CI checks pass
- All review comments addressed and conversations resolved
- Branch is up-to-date with base

```bash
gh pr checks         # verify all pass
gh pr view --comments  # verify no unresolved comments
gh pr merge --squash
```

## Post-Merge Cleanup

```bash
# Verify merged
git branch -r --merged origin/main | grep <branch-name>

# Clean up (from main repo, not worktree)
git worktree remove ../TermQ-worktrees/<branch-name>
git branch -d <branch-name>
git push origin --delete <branch-name>
```
