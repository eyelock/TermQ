# Stable Release Procedure

## Prerequisites

- All feature/fix work merged to develop
- CI passing on develop

## Steps

### 0. Update CHANGELOG.md (on develop, before opening the release PR)

```bash
# In CHANGELOG.md:
# 1. Rename ## [Unreleased] → ## [VERSION] - YYYY-MM-DD
# 2. Add a new empty ## [Unreleased] section above it
git add CHANGELOG.md
git commit -m "chore: Update CHANGELOG for v{VERSION}"
git push
```

This commit must land on develop (or a `release/vVERSION` branch) and be included in the develop → main PR. The release workflow reads `CHANGELOG.md` from the tagged commit — if it's not committed before the tag is pushed, the release notes will be empty.

### 1. Open and Merge the Release PR

```bash
gh pr create --base main --head develop \
  --title "release: TermQ v{VERSION}" \
  --body "Promotes develop to main for stable release v{VERSION}"
```

Wait for CI to pass on the PR, then merge. After merge:

```bash
git checkout main && git pull
```

### 2. Pre-Release Checks

```bash
make check
```

All checks must pass: build zero errors, lint zero errors, format clean, all tests pass.

### 3. Create Release Tag

```bash
# Interactive — prompts for patch/minor/major
make release

# Or specify directly:
make release-patch   # 0.6.4 → 0.6.5
make release-minor   # 0.6.4 → 0.7.0
make release-major   # 0.6.4 → 1.0.0
```

This checks for uncommitted changes, verifies you're on main, calculates the next version from git tags, creates an annotated tag, and pushes it.

### 4. Monitor Automated Release

```bash
gh run list --workflow=release.yml --limit 1
gh run watch <run-id>
```

The workflow automatically: verifies CI passed → builds → signs → notarizes (~5-15 min) → creates DMG + ZIP + checksums → publishes GitHub release.

### 5. Verify Release

```bash
gh release view v{VERSION}
# Should show: title "TermQ v{VERSION}", assets (DMG, ZIP, checksums), NOT pre-release
```

### 6. Verify Appcast Update

```bash
gh run list --workflow=update-appcast.yml --limit 1
curl -s https://eyelock.github.io/TermQ/appcast.xml | grep "{VERSION}"
```

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
