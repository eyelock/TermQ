# Beta Release Procedure

Beta releases allow early access to new features for testing before stable release. TermQ uses Sparkle's dual-feed system for beta distribution.

## How Beta Releases Work

### Two Appcast Feeds

1. **Stable Feed** (`appcast.xml`) - Excludes pre-releases
2. **Beta Feed** (`appcast-beta.xml`) - Includes all releases

Users opt into beta releases via **Settings → Include Beta Releases**. When enabled, Sparkle switches from the stable feed to the beta feed.

### Tag Naming Convention

Beta releases MUST include one of these suffixes in the version tag:
- `-beta` (e.g., `v0.7.0-beta.1`)
- `-alpha` (e.g., `v1.0.0-alpha.1`)
- `-rc` (release candidate, e.g., `v1.0.0-rc.1`)
- `-dev` (development, e.g., `v0.7.0-dev.1`)

## When to Create Beta Releases

- New major features requiring user testing
- Significant architectural changes
- Breaking changes that need validation
- Release candidates before stable release

## Beta Release Procedure

### 1. Ensure Changes Are on Main

```bash
# Verify all changes are merged to main
git checkout main
git pull
git log --oneline -5
```

### 2. Create Beta Tag

```bash
# Tag format: vMAJOR.MINOR.PATCH-beta.INCREMENT
git tag -a "v0.7.0-beta.1" -m "Release v0.7.0-beta.1"

# Push the tag
git push origin v0.7.0-beta.1
```

### 3. Monitor Automated Release

Beta releases automatically:
- ✅ Skip CI verification (faster release)
- ✅ Build release binaries
- ✅ Sign with Developer ID
- ✅ Notarize with Apple
- ✅ Create DMG and ZIP
- ✅ Mark as **pre-release** on GitHub
- ✅ Update both appcast feeds

```bash
# Monitor release workflow
gh run list --workflow=release.yml --limit 1
gh run watch <run-id>

# Verify release was created and marked as pre-release
gh release view v0.7.0-beta.1
```

### 4. Verify Appcast Update

The `update-appcast.yml` workflow automatically updates both feeds after release:

```bash
# Check if appcast workflow ran
gh run list --workflow=update-appcast.yml --limit 1

# Verify feeds were updated
curl -s https://eyelock.github.io/TermQ/appcast.xml | grep -A5 "<title>"
curl -s https://eyelock.github.io/TermQ/appcast-beta.xml | grep -A5 "<title>"
```

**Expected Results:**
- `appcast.xml` - Should NOT include beta release
- `appcast-beta.xml` - Should include beta release

## Beta Testing

### For Beta Testers

1. Enable beta releases:
   - Open TermQ
   - Go to **TermQ → Settings** (⌘,)
   - Check **Include Beta Releases**
   - Click **Check for Updates**

2. Install the beta:
   - Sparkle will detect the beta update
   - Follow prompts to download and install

3. Provide feedback:
   - Report issues on GitHub
   - Test new features thoroughly
   - Check for regressions

## Promoting Beta to Stable

Once beta testing is complete and all issues are resolved:

### 1. Create Stable Release Tag

```bash
# Remove beta suffix for stable release
git tag -a "v0.7.0" -m "Release v0.7.0"
git push origin v0.7.0
```

### 2. Monitor Stable Release

Stable releases:
- ✅ Require CI to pass
- ✅ Build, sign, and notarize
- ✅ Mark as **latest release** (not pre-release)
- ✅ Update both appcast feeds

### 3. Verify Distribution

```bash
# Check stable release
gh release view v0.7.0

# Verify it appears in stable feed
curl -s https://eyelock.github.io/TermQ/appcast.xml | grep "v0.7.0"
```

## Version Numbering

### Beta Increments

Use sequential beta numbers:
```bash
v0.7.0-beta.1  # First beta
v0.7.0-beta.2  # Second beta (after fixes)
v0.7.0-beta.3  # Third beta (after more fixes)
v0.7.0         # Final stable release
```

### Multiple Pre-release Types

Follow this progression:
```bash
v1.0.0-alpha.1   # Early development
v1.0.0-alpha.2   # More development
v1.0.0-beta.1    # Feature complete, testing
v1.0.0-beta.2    # Bug fixes
v1.0.0-rc.1      # Release candidate
v1.0.0           # Stable release
```

## Appcast Feed Details

### Implementation

The Sparkle integration uses `SparkleUpdaterDelegate` to switch feeds:

```swift
func feedURLString(for updater: SPUUpdater) -> String? {
    let includeBeta = UserDefaults.standard.bool(forKey: "SUIncludeBetaReleases")
    let feedFile = includeBeta ? "appcast-beta.xml" : "appcast.xml"
    return "https://eyelock.github.io/TermQ/\(feedFile)"
}
```

### Feed Generation

The `generate-appcast.sh` script:
1. Fetches all releases from GitHub API
2. Filters by tag pattern: `(alpha|beta|rc|dev)`
3. Generates `appcast.xml` (stable only)
4. Generates `appcast-beta.xml` (all releases)

### Automatic Updates

The `update-appcast.yml` workflow:
1. Triggers on any release published
2. Runs `generate-appcast.sh`
3. Commits updated feeds to main branch
4. Pushes to GitHub Pages (eyelock.github.io/TermQ)

## Troubleshooting

### Beta Not Appearing for Testers

1. Check release is marked as pre-release:
   ```bash
   gh release view v0.7.0-beta.1 --json isPrerelease
   ```

2. Verify appcast-beta.xml includes it:
   ```bash
   curl -s https://eyelock.github.io/TermQ/appcast-beta.xml | grep "beta"
   ```

3. Ensure tester has beta releases enabled:
   ```bash
   defaults read net.eyelock.TermQ SUIncludeBetaReleases
   # Should return: 1
   ```

### Beta Appearing in Stable Feed

This is a bug. Check:
1. Tag name includes beta suffix
2. GitHub release marked as pre-release
3. Appcast generation script filtering correctly

### Appcast Not Updating

1. Check update-appcast workflow:
   ```bash
   gh run list --workflow=update-appcast.yml --limit 3
   ```

2. Manually trigger if needed:
   ```bash
   gh workflow run update-appcast.yml
   ```

## What NOT to Do

❌ **NEVER** create beta releases without beta suffix in tag
❌ **NEVER** manually edit appcast files (they're auto-generated)
❌ **NEVER** mark stable releases as pre-release
❌ **NEVER** skip beta testing for major changes
❌ **NEVER** promote beta to stable without testing

## Example: v0.7.0 Beta Cycle

```bash
# 1. Create first beta from main
git checkout main
git pull
git tag -a "v0.7.0-beta.1" -m "Release v0.7.0-beta.1"
git push origin v0.7.0-beta.1

# 2. Beta testers report issues, fix in main
# ... make fixes, merge PRs ...

# 3. Create second beta with fixes
git checkout main
git pull
git tag -a "v0.7.0-beta.2" -m "Release v0.7.0-beta.2"
git push origin v0.7.0-beta.2

# 4. After successful testing, release stable
git tag -a "v0.7.0" -m "Release v0.7.0"
git push origin v0.7.0

# 5. Verify stable release
gh release view v0.7.0
curl -s https://eyelock.github.io/TermQ/appcast.xml | grep "v0.7.0"
```

## Verification Checklist

- [ ] Tag includes `-beta`, `-alpha`, `-rc`, or `-dev` suffix
- [ ] Tag pushed to remote
- [ ] Release workflow completed successfully
- [ ] Release marked as pre-release on GitHub
- [ ] Release includes DMG, ZIP, and checksums
- [ ] Release is signed and notarized
- [ ] Appcast workflow ran and updated feeds
- [ ] Beta appears in `appcast-beta.xml`
- [ ] Beta does NOT appear in `appcast.xml`
- [ ] Beta testers can see and install update
