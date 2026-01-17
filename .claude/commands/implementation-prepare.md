# Implementation Preparation

**Run this checklist BEFORE writing any code for features, fixes, or refactoring.**

## 1. Context Gathering

- [ ] Read the task/plan/issue description thoroughly
- [ ] Check ACME for related notes, reviews, or previous attempts
- [ ] Review recent commits related to this area (`git log --oneline <files>`)
- [ ] Identify the files that will need changes

## 2. Environment Verification

- [ ] Verify you're in the correct worktree/branch
- [ ] Run `git status` - ensure clean working directory (or expected changes only)
- [ ] Run `make check` - verify baseline passes before you start
- [ ] Check branch is up-to-date with main if needed (`git fetch origin main`)

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

- [ ] Use TodoWrite to create implementation checklist
- [ ] Break down changes into logical steps
- [ ] Identify testing strategy (unit, integration, manual)
- [ ] Note any concerns or questions for user

## 6. Ready to Code

Once all checks pass:
- ✅ Environment is clean and verified
- ✅ You understand the existing code
- ✅ You have a clear implementation plan
- ✅ You know what tests need updating/adding

**Now proceed with implementation. When done, follow [implementation-checks.md](implementation-checks.md)**
