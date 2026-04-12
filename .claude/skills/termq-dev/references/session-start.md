# Session Start Checklist

Run at the beginning of every session.

## 1. Orient

```bash
git status
git log --oneline -5
```

- Confirm the current branch
- Check for uncommitted changes
- Review recent commits to understand what's happened

## 2. Check for Continuations

- Look in `.claude/sessions/` for handover notes from previous sessions
- If continuing work: review session notes and run `git diff` to understand state

## 3. Choose a Path

**Continuing previous work:**
1. Review session notes
2. Run `git status` to confirm state
3. Resume at the appropriate step

**Starting new implementation work:**

Do not use Edit or Write tools until all of these are complete.

1. **Gather context** — explore affected files, trace existing patterns, identify tests that cover the area
2. **Read every file you will modify** — understand what's already there before changing anything
3. **Verify a clean baseline** — `make check` must pass before starting; if it's broken, fix or report it first
4. **Decide on worktree vs main** — see worktrees.md; prefer a worktree for multi-file or multi-session work
5. **Plan if warranted** — for multi-file or architectural changes, create a plan in `.claude/plans/YYYY-MM-DD-name.md` before writing any code

**Investigating only (no planned code changes):**
- Use targeted file/code search
- No need for worktree or build baseline check

## 4. Before Coding

Always verify a clean baseline before making any changes:

```bash
make check
```

If the baseline is broken, fix it or report it before starting new work. Never build on a broken foundation.

## 5. Before Committing

Run quality verification on all changed Swift files. Ensure no logging violations, style issues, or failing tests before creating a commit.
