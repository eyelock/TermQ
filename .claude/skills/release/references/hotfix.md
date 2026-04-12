# Hotfix Release Procedure

Use for critical production bugs, security vulnerabilities, or data loss issues that cannot wait for a normal release cycle.

**NEVER bypass the automated release system. If automation fails, fix the automation.**

## Prerequisites

- The fix is already on `main` via the standard PR process
- CI has passed on main
- You know the base version being hotfixed (e.g., v0.6.3)

## Steps

### 1. Create Hotfix Branch from the Release Tag

```bash
git checkout -b hotfix/v0.6.4 v0.6.3
```

### 2. Cherry-Pick the Fix from Main

```bash
git log main --oneline | grep "fix:"     # find the fix commit
git cherry-pick <commit-sha>
git push -u origin hotfix/v0.6.4
```

### 3. Wait for CI

**MANDATORY before tagging.** The CI workflow runs on `hotfix/*` branches.

```bash
gh run list --branch hotfix/v0.6.4 --workflow=ci.yml --limit 1
gh run watch <run-id>
```

### 4. Tag After CI Passes

```bash
git tag -a "v0.6.4" -m "Release v0.6.4"
git push origin v0.6.4
```

### 5. Monitor Automated Release

```bash
gh run list --workflow=release.yml --limit 1
gh run watch <run-id>
gh release view v0.6.4
```

### 6. Cleanup

```bash
gh pr close <pr-number>           # close any hotfix PRs
git push origin --delete hotfix/v0.6.4
git branch -d hotfix/v0.6.4
```

## What NOT to Do

- NEVER create releases manually with `gh release create`
- NEVER bypass CI verification
- NEVER work around failed automation — fix it instead
- NEVER push unsigned/unnotarized builds
