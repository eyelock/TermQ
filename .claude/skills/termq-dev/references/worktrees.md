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
# 1. Verify merged (from inside worktree or main repo)
git branch -r --merged origin/develop | grep <branch-name>
# If nothing shows, the branch is NOT merged — do not proceed

# 2. Capture paths BEFORE moving anywhere
MAIN_REPO=$(git rev-parse --show-toplevel)
BRANCH=<branch-name>

# 3. Pivot to main repo FIRST — once worktree is removed, its CWD becomes invalid
cd "$MAIN_REPO"

# 4. Remove worktree, delete local branch
git worktree remove ../TermQ-worktrees/"$BRANCH"
git branch -d "$BRANCH"

# 5. Delete remote branch only if it still exists (GitHub auto-deletes on merge)
git ls-remote --exit-code origin "$BRANCH" 2>/dev/null && git push origin --delete "$BRANCH" || echo "Remote branch already deleted — skipping"
```

**Never** use `rm -rf` on a worktree directory — use `git worktree remove`.
**Never** use `git branch -D` (force delete) without understanding why.
**Always** `cd` to the main repo before removing the worktree — never run removal from inside it.

## Summarising Unmerged Worktree Work

Before removing a worktree that might have unmerged commits, summarise first:

```bash
git log origin/develop..<branch-name> --oneline   # commits
git diff origin/develop..<branch-name> --stat     # files changed
```

Present the summary and ask for explicit confirmation before proceeding.
