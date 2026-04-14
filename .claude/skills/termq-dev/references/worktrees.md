# Worktree Workflow

## When to Create a Worktree

**Create a worktree when:**
- Multi-file feature or fix (will take multiple commits)
- Want to keep main clean for parallel investigations
- Work spans multiple sessions
- Multiple ideas in flight simultaneously

**Skip the separate worktree when:**
- Documentation-only changes
- Single-file ad-hoc fixes (this session only)
- Quick investigations with no planned commits

## Creating a Worktree

```bash
# One-time setup (only needed once per machine)
mkdir -p ../TermQ-worktrees

# Create worktree with new branch
git worktree add ../TermQ-worktrees/<branch-name> -b <branch-name>
```

**Branch naming — use hyphens, not slashes** (keeps worktree directories flat and easy to see):

```
feat-<description>      # new feature
fix-<description>       # bug fix
refactor-<description>  # refactoring
docs-<description>      # docs only
ci-<description>        # CI/CD changes
test-<description>      # tests
```

Example: `git worktree add ../TermQ-worktrees/feat-quick-actions -b feat-quick-actions`

## Cleaning Up a Worktree

**Only remove a worktree after its PR is merged.**

```bash
# 1. Verify merged into develop (feature branches)
git branch -r --merged origin/develop | grep <branch-name>
# If nothing shows, the branch is NOT merged — do not proceed

# 2. Clean up from main repo (not from inside the worktree)
git worktree remove ../TermQ-worktrees/<branch-name>
git branch -d <branch-name>
git push origin --delete <branch-name>
```

**Never** use `rm -rf` on a worktree directory — use `git worktree remove`.
**Never** use `git branch -D` (force delete) without understanding why.

## Summarising Unmerged Worktree Work

Before removing a worktree that might have unmerged commits, summarise first:

```bash
git log origin/develop..<branch-name> --oneline   # commits
git diff origin/develop..<branch-name> --stat     # files changed
```

Present the summary and ask for explicit confirmation before proceeding.
