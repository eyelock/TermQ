# Hotfix Release Procedure

**CRITICAL: NEVER bypass the automated release system. If automation fails, FIX THE AUTOMATION.**

## When to Use Hotfix Releases

- Critical bugs in production that cannot wait for the next regular release
- Security vulnerabilities requiring immediate patches
- Data loss or corruption issues

## Prerequisites

1. Fix is already merged to `main` via standard PR process
2. CI has passed on main branch
3. You know the base version to hotfix (e.g., v0.6.3)

## Procedure

### 1. Create Hotfix Branch

```bash
# Branch from the tagged release you're hotfixing
git checkout -b hotfix/vX.Y.Z vX.Y.Z-1

# Example: hotfix v0.6.3 to create v0.6.4
git checkout -b hotfix/v0.6.4 v0.6.3
```

### 2. Cherry-Pick Fix from Main

```bash
# Find the fix commit SHA from main
git log main --oneline | grep "fix:"

# Cherry-pick the fix
git cherry-pick <commit-sha>

# Push hotfix branch
git push -u origin hotfix/vX.Y.Z
```

### 3. Wait for CI to Pass

**MANDATORY:** CI must pass on the hotfix branch before tagging.

```bash
# Check CI status
gh run list --branch hotfix/vX.Y.Z --workflow=ci.yml --limit 1

# Wait for completion
gh run watch <run-id>
```

### 4. Tag the Release

**ONLY after CI passes:**

```bash
# Tag the hotfix commit
git tag -a "vX.Y.Z" -m "Release vX.Y.Z"

# Push the tag
git push origin vX.Y.Z
```

### 5. Monitor Automated Release

The release workflow automatically:
- ✅ Verifies CI passed
- ✅ Builds release binaries
- ✅ Signs with Developer ID
- ✅ Notarizes with Apple
- ✅ Creates DMG and ZIP
- ✅ Publishes GitHub release with proper naming

```bash
# Monitor release workflow
gh run list --workflow=release.yml --limit 1
gh run watch <run-id>

# Verify release was created
gh release view vX.Y.Z
```

## What NOT to Do

❌ **NEVER** create releases manually with `gh release create`
❌ **NEVER** bypass CI verification
❌ **NEVER** use custom release titles (always "TermQ vX.Y.Z")
❌ **NEVER** build artifacts locally for release
❌ **NEVER** push unsigned/unnotarized builds

## If Automation Fails

1. **DO NOT WORK AROUND IT**
2. Identify why the workflow failed
3. Fix the workflow
4. Delete any manual releases created
5. Re-run through automation

## CI Workflow Configuration

The CI workflow runs on `hotfix/*` branches to enable release validation:

```yaml
on:
  push:
    branches: [main, master, 'hotfix/*']
```

This ensures hotfix releases go through full CI validation before the release workflow runs.

## Cleanup

After successful release:

```bash
# Close any hotfix PRs
gh pr close <pr-number>

# Optionally delete hotfix branch
git push origin --delete hotfix/vX.Y.Z
git branch -d hotfix/vX.Y.Z
```

## Example: v0.6.4 Hotfix

```bash
# 1. Create branch from v0.6.3
git checkout -b hotfix/v0.6.4 v0.6.3

# 2. Cherry-pick fix from main (commit 58212bc)
git cherry-pick 58212bc

# 3. Push and wait for CI
git push -u origin hotfix/v0.6.4
gh run watch --workflow=ci.yml

# 4. Tag after CI passes
git tag -a "v0.6.4" -m "Release v0.6.4"
git push origin v0.6.4

# 5. Monitor automated release
gh run watch --workflow=release.yml
gh release view v0.6.4
```

## Verification Checklist

- [ ] Hotfix branch created from correct base version tag
- [ ] Fix cherry-picked from main (or committed directly)
- [ ] CI passed on hotfix branch
- [ ] Tag created and pushed
- [ ] Release workflow completed successfully
- [ ] Release has proper naming: "TermQ vX.Y.Z"
- [ ] Release includes DMG, ZIP, and checksums
- [ ] Release is signed and notarized
