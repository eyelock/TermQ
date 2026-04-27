# Beta Release Procedure

Beta releases go to `appcast-beta.xml` only. Users opt in via Settings → Include Beta Releases.

## Tag Naming

Beta tags MUST include a suffix:

```
v0.7.0-beta.1    v0.7.0-beta.2    v1.0.0-alpha.1    v1.0.0-rc.1
```

Suffixes: `-beta`, `-alpha`, `-rc`, `-dev`

## Version Format (git tag → app)

The git tag uses dash notation (required for GitHub to detect pre-releases). The app's plist and appcast use **dot notation** — converted automatically at build time:

| Git tag | App version (`CFBundleVersion`, `sparkle:version`) |
|---|---|
| `v0.7.0-beta.9` | `0.7.0.b9` |
| `v0.7.0-alpha.3` | `0.7.0.a3` |
| `v0.7.0-rc.2` | `0.7.0.rc2` |

The git SHA is stored in the custom key `TermQBuildSHA` (for display in Settings → About).
**Never use dashes in `CFBundleVersion` or `sparkle:version`** — `SUStandardVersionComparator` truncates at the first dash, making all betas of the same MAJOR.MINOR.PATCH compare as equal.

## Steps

### 1. Ensure Changes Are on Develop

```bash
git checkout develop
git pull
```

### 2. Create Beta Tag

```bash
git tag -a "v0.7.0-beta.1" -m "Release v0.7.0-beta.1"
git push origin v0.7.0-beta.1
```

### 3. Monitor

```bash
gh run list --workflow=release.yml --limit 1
gh run watch <run-id>
gh release view v0.7.0-beta.1
# Should be marked as pre-release
```

Beta releases skip `release.yml`'s own `verify-ci` step for faster iteration.
(CI still runs on `develop` for every push and PR — the skip is only in the release
workflow itself, not in CI.) They still sign and notarize.

### 4. Verify Feeds

```bash
gh run list --workflow=update-appcast.yml --limit 1
# appcast.xml should NOT include beta
# appcast-beta.xml SHOULD include beta
curl -s https://eyelock.github.io/TermQ/appcast-beta.xml | grep "beta"
```

## Promoting Beta to Stable

Once testing is complete, follow [stable.md](stable.md) in full.

**NEVER promote by opening `develop → main` directly.** Always cut a `release/vX.Y.Z` branch
first. `main` accumulates appcast commits after every beta — opening develop → main directly
forces conflict resolution inside develop. The release branch absorbs it cleanly.

The short version:

```bash
git checkout -b release/v0.7.0 develop
# Update CHANGELOG: rename [Unreleased] → [0.7.0], add new [Unreleased] above
git add CHANGELOG.md && git commit -m "chore: update CHANGELOG for v0.7.0" && git push
gh pr create --base main --head release/v0.7.0 --title "release: TermQ v0.7.0"
# Resolve any conflicts on the release branch, not on develop
# After merge to main: make check → make release-minor → back-merge → appcast sync
```

See `stable.md` for the complete step-by-step including back-merge and appcast sync.

## Version Progression

```
v1.0.0-alpha.1  →  v1.0.0-alpha.2  →  v1.0.0-beta.1  →  v1.0.0-beta.2  →  v1.0.0-rc.1  →  v1.0.0
```

## What NOT to Do

- NEVER create beta releases without the suffix in the tag
- NEVER manually edit appcast files (they're auto-generated)
- NEVER mark stable releases as pre-release
- NEVER promote beta to stable without testing
- NEVER open `develop → main` directly for promotion — always use a release branch
