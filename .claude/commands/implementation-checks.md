# Implementation Checks

**Run this checklist AFTER completing code changes, BEFORE committing.**

## 1. Build Verification

**MANDATORY - Zero tolerance for errors:**

```bash
make check  # Runs: build, lint, format-check, test
```

- [ ] `make build` - MUST pass with zero errors
- [ ] `make lint` - MUST pass with zero errors (minimize warnings)
- [ ] `make format-check` - MUST pass (run `make format` to fix)
- [ ] `make test` - ALL tests MUST pass

**IMPORTANT: Always use make targets, NEVER use `swift`, `swiftlint`, or `swift-format` directly.**
The Makefile handles DEVELOPER_DIR, warning filters, CI detection, and tool installation.

**If any check fails, fix it before proceeding.**

## 2. Code Quality Review

- [ ] Review your `git diff` for:
  - [ ] No debug code (print statements, test data, etc.)
  - [ ] No commented-out code
  - [ ] No TODO comments (create GitHub issues instead)
  - [ ] No accidentally committed personal configs
- [ ] Check for compiler warnings you may have introduced
- [ ] Verify you're following patterns from [code-style.md](code-style.md)
- [ ] Check that error handling is appropriate

## 3. Testing Verification

- [ ] All existing tests still pass
- [ ] New tests added for new functionality
- [ ] Edge cases covered
- [ ] Manual testing performed (if UI changes)
- [ ] Consider test coverage - are critical paths tested?

## 4. Domain-Specific Checks

### If you modified UI strings or Swift files with UI:
**REQUIRED:** Run localization validation

- [ ] Run `./scripts/localization/validate-strings.sh`
      (Ensures all 40 language files have matching keys)
- [ ] Verify all language files updated correctly
- [ ] Check [localization.md](localization.md) for string guidelines
- [ ] Test UI in different languages if possible

**Skip if:** Only modified non-UI code (models, services, tests, etc.)

### If you modified APIs:
- [ ] Document breaking changes
- [ ] Update version if needed
- [ ] Consider backward compatibility

### If you modified build/CI:
- [ ] Verify changes work locally first
- [ ] Remember: Every CI run consumes energy - be responsible

## 5. Documentation

- [ ] Update relevant comments/docstrings
- [ ] Update README if user-facing changes
- [ ] Update command docs if workflow changes
- [ ] Create session handover notes in `.claude/sessions/` if needed

## 6. Final Verification

- [ ] Run `git status` - only expected files changed
- [ ] Run `make check` one more time - everything still passes
- [ ] Review your changes tell a coherent story

## ✅ Ready to Commit

Once all checks pass, proceed to [commit-pr.md](commit-pr.md) to create your commit and PR.

**NEVER skip these checks - they prevent broken builds and wasted CI runs.**
