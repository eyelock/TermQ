# Implementation Preparation

**Run this checklist BEFORE writing any code for features, fixes, or refactoring.**

## 1. Context Gathering

- [ ] Read the task/plan/issue description thoroughly
- [ ] Review session notes in `.claude/sessions/` for related work
- [ ] Review recent commits related to this area (`git log --oneline <files>`)
- [ ] Identify the files that will need changes

## 2. Environment Verification

- [ ] Verify you're in the correct worktree/branch
- [ ] Run `git status` - ensure clean working directory (or expected changes only)
- [ ] Run `make check` - verify baseline passes before you start
- [ ] Check branch is up-to-date with main if needed (`git fetch origin main`)

### Worktree Decision

**If you're in the main repository (not already in a worktree):**

🤔 **Should we create a worktree for this work?**

**Create a worktree when:**
- Multi-file feature or fix (will take multiple commits)
- Want to keep main clean for other investigations
- Work might span multiple sessions
- Multiple ideas/fixes flowing simultaneously

**Work on main when:**
- Quick documentation-only changes
- Single-file fixes (this session only)
- Need to investigate something ad-hoc
- Emergency hotfix (though consider hotfix workflow)

**Create worktree:**

```bash
# First-time setup: Create worktree directory (only needed once)
mkdir -p ../TermQ-worktrees

# Use conventional commit prefixes with hyphens: feat-, fix-, docs-, test-, refactor-, ci-
git worktree add ../TermQ-worktrees/<branch-name> -b <branch-name>
cd ../TermQ-worktrees/<branch-name>
```

**Example:**
```bash
git worktree add ../TermQ-worktrees/feat-terminal-quick-actions -b feat-terminal-quick-actions
cd ../TermQ-worktrees/feat-terminal-quick-actions
```

## 3. Code Review

- [ ] Read all files you'll be modifying (use Read tool)
- [ ] Understand existing patterns and conventions
- [ ] Check [code-style.md](code-style.md) for Swift/project patterns
- [ ] Identify existing tests that cover this code
- [ ] Look for similar implementations elsewhere in the codebase

## 4. Impact Assessment

- [ ] Will this change affect UI? → Check [localization.md](localization.md)
- [ ] Will this change APIs? → Document breaking changes
- [ ] Will this change database/storage? → Plan migration if needed
- [ ] Will this affect existing tests? → Plan test updates
- [ ] Will this require new dependencies? → Check necessity and size

## 5. Implementation Planning

### When to Create a Plan

Create a written plan in `.claude/plans/` if:
- **Multi-file changes** - 3+ files will be modified
- **Architectural decisions** - Need to choose between approaches
- **User requests planning** - Explicitly asked or using EnterPlanMode
- **Unclear path** - Multiple ways to implement, need to compare

**Plan format:** `YYYY-MM-DD-feature-name.md`

**Example:** `.claude/plans/2026-01-17-persistent-claude-settings.md`

### Planning Checklist

- [ ] Use TodoWrite to create implementation checklist
- [ ] Break down changes into logical steps
- [ ] Create written plan in `.claude/plans/` if complexity warrants it
- [ ] Identify testing strategy (unit, integration, manual)
- [ ] Note any concerns or questions for user

## 6. Ready to Code

Once all checks pass:
- ✅ Environment is clean and verified
- ✅ You understand the existing code
- ✅ You have a clear implementation plan
- ✅ You know what tests need updating/adding

**Now proceed with implementation. When done, follow [implementation-checks.md](implementation-checks.md)**
