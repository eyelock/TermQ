# Stable Release Procedure

## Prerequisites

- All changes merged to main via PR
- CI passing on main
- `make check` passes locally

## Steps

### 1. Pre-Release Checks

```bash
git checkout main
git pull
make check
```

All checks must pass: build zero errors, lint zero errors, format clean, all tests pass.

### 2. Create Release Tag

```bash
# Interactive — prompts for patch/minor/major
make release

# Or specify directly:
make release-patch   # 0.6.4 → 0.6.5
make release-minor   # 0.6.4 → 0.7.0
make release-major   # 0.6.4 → 1.0.0
```

This checks for uncommitted changes, verifies you're on main, calculates the next version from git tags, creates an annotated tag, and pushes it.

### 3. Monitor Automated Release

```bash
gh run list --workflow=release.yml --limit 1
gh run watch <run-id>
```

The workflow automatically: verifies CI passed → builds → signs → notarizes (~5-15 min) → creates DMG + ZIP + checksums → publishes GitHub release.

### 4. Verify Release

```bash
gh release view v{VERSION}
# Should show: title "TermQ v{VERSION}", assets (DMG, ZIP, checksums), NOT pre-release
```

### 5. Verify Appcast Update

```bash
gh run list --workflow=update-appcast.yml --limit 1
curl -s https://eyelock.github.io/TermQ/appcast.xml | grep "{VERSION}"
```

### 6. Forward-Port Appcast to Develop — MANDATORY

The `update-appcast.yml` workflow commits updated appcast files directly to main. These must be synced back to develop to prevent conflicts on the next release.

```bash
git checkout -b fix/sync-appcast-v{VERSION} develop
git checkout origin/main -- Docs/appcast.xml Docs/appcast-beta.xml
git commit -m "chore: Sync appcast entries for v{VERSION} back to develop"
git push -u origin fix/sync-appcast-v{VERSION}
gh pr create --base develop --title "chore: Sync appcast entries for v{VERSION} back to develop"
```

Merge once CI passes.

## Troubleshooting

**Release workflow fails on CI check:** The commit must have a passing CI run.
```bash
git log -1 --format="%H"
gh run list --commit <sha> --workflow=ci.yml
```
Fix the issue on main, wait for CI, delete the failed tag, re-tag.

**Delete and re-tag:**
```bash
gh release delete v{VERSION} --yes
git tag -d v{VERSION}
git push origin :refs/tags/v{VERSION}
# Then re-run make release
```

## What NOT to Do

- NEVER create releases manually with `gh release create`
- NEVER tag without running `make check` first
- NEVER use custom release titles
- NEVER skip CI verification
- NEVER tag from branches other than main
