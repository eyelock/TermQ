# Stable Release Procedure

## The Rule: Always Use a Release Branch

**NEVER open `develop → main` directly.** Always cut a `release/vX.Y.Z` branch first.

Why: `main` accumulates commits after every release (appcast updates, hotfix forward-ports).
Opening `develop → main` directly forces you to resolve those conflicts inside `develop`, which
is messy and pollutes its history. A release branch absorbs the conflict once, in isolation,
and the back-merge to develop is small and clean.

## Prerequisites

- All feature/fix work merged to develop
- CI passing on develop

## Steps

### 1. Cut the Release Branch

```bash
git checkout develop && git pull
git checkout -b release/v{VERSION}
git push -u origin release/v{VERSION}
```

### 2. Update CHANGELOG.md

```bash
# In CHANGELOG.md:
# 1. Rename ## [Unreleased] → ## [VERSION]  (no date — date is added at release time if desired)
# 2. Add a new empty ## [Unreleased] section above it
git add CHANGELOG.md
git commit -m "chore: update CHANGELOG for v{VERSION}"
git push
```

The release workflow reads `CHANGELOG.md` from the tagged commit. If it is not committed
before the tag is pushed, release notes will be empty.

### 3. Open the Release PR (release/vX.Y.Z → main)

```bash
gh pr create --base main --head release/v{VERSION} \
  --title "release: TermQ v{VERSION}" \
  --body "Promotes release/v{VERSION} to main for stable release."
```

If GitHub reports conflicts, resolve them on the release branch — **never on develop**:

```bash
git fetch origin
git merge origin/main          # resolve conflicts here
git push
```

Wait for CI to pass, then merge using a **true merge** (not squash, not rebase):

```bash
gh pr checks --watch
gh pr merge --merge
git checkout main && git pull
```

### 4. Pre-Release Checks

```bash
make check
```

All gates must pass: build zero errors, lint zero errors, format clean, all tests pass.

### 5. Create Release Tag

```bash
# Interactive — prompts for patch/minor/major
make release

# Or specify directly:
make release-patch   # 0.6.4 → 0.6.5
make release-minor   # 0.6.4 → 0.7.0
make release-major   # 0.6.4 → 1.0.0
```

This verifies you're on main, calculates the next version from git tags, creates an annotated
tag, and pushes it.

### 6. Monitor Automated Release

```bash
gh run list --workflow=release.yml --limit 1
gh run watch <run-id>
gh release view v{VERSION}
# Should show: title "TermQ v{VERSION}", assets (DMG, ZIP, checksums), NOT pre-release
```

### 7. Back-Merge the Release Branch to Develop — MANDATORY

```bash
git checkout -b chore/back-merge-v{VERSION} develop
git merge origin/release/v{VERSION}
git push -u origin chore/back-merge-v{VERSION}
gh pr create --base develop \
  --title "chore: back-merge release/v{VERSION} into develop" \
  --body "Brings CHANGELOG update and any release-branch conflict resolutions back to develop."
```

Merge once CI passes, then delete the release branch:

```bash
git push origin --delete release/v{VERSION}
```

### 8. Forward-Port Appcast to Develop — MANDATORY

`update-appcast.yml` commits appcast files directly to `main` after the release. These must
come to develop separately:

```bash
git checkout -b chore/sync-appcast-v{VERSION} develop
git checkout origin/main -- Docs/appcast.xml Docs/appcast-beta.xml
git commit -m "chore: sync appcast entries for v{VERSION} back to develop"
git push -u origin chore/sync-appcast-v{VERSION}
gh pr create --base develop \
  --title "chore: sync appcast entries for v{VERSION} back to develop"
```

Merge once CI passes.

> **Note:** Steps 7 and 8 can be combined into one PR if the appcast update workflow
> has already completed before you open the back-merge.

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

- NEVER open `develop → main` directly — always use a release branch
- NEVER create releases manually with `gh release create`
- NEVER tag without running `make check` first
- NEVER use custom release titles
- NEVER skip CI verification
- NEVER tag from branches other than `main`
- NEVER skip the back-merge (step 7) or appcast sync (step 8)
