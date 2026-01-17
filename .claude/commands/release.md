# Standard Release Procedure

This is the standard release flow for TermQ stable releases from the main branch.

## Prerequisites

- All changes merged to main via PR
- CI passing on main
- All tests passing locally: `make check`
- Ready to tag and release

## Release Flow

### 1. Run Pre-Release Checks

```bash
# Ensure you're on main and up to date
git checkout main
git pull

# Run all checks locally (MANDATORY)
make check

# Verify everything passes:
# - Build completes with zero errors
# - Lint passes with zero errors
# - Format check passes
# - All tests pass
```

### 2. Create Release Tag

Use the Makefile release targets for version management:

```bash
# Interactive: prompts for major/minor/patch
make release

# Or specify directly:
make release-patch  # 0.6.4 → 0.6.5
make release-minor  # 0.6.4 → 0.7.0
make release-major  # 0.6.4 → 1.0.0
```

This will:
1. Check for uncommitted changes (fails if dirty)
2. Verify you're on main/master branch
3. Calculate next version from git tags
4. Create annotated git tag: `v{VERSION}`
5. Push tag to origin

### 3. Monitor Automated Release

Once the tag is pushed, the release workflow automatically:

1. **Verify CI Passed** - Checks commit has successful CI run
2. **Build Release** - Compiles release binaries
3. **Sign App Bundle** - Signs with Developer ID certificate
4. **Notarize** - Submits to Apple for notarization (~5-15 min)
5. **Create DMG** - Builds and signs DMG installer
6. **Create ZIP** - Creates ZIP archive
7. **Generate Checksums** - SHA-256 checksums for all artifacts
8. **Publish Release** - Creates GitHub release with artifacts

```bash
# Monitor the release workflow
gh run list --workflow=release.yml --limit 1
gh run watch <run-id>

# After completion, verify release
gh release view v{VERSION}
```

### 4. Verify Release

Check that the release was created correctly:

```bash
# View release details
gh release view v{VERSION}

# Should show:
# - Title: "TermQ v{VERSION}"
# - Author: github-actions[bot]
# - Assets: DMG, ZIP, checksums.txt
# - Not marked as pre-release
# - Generated release notes
```

### 5. Verify Appcast Update

The appcast files are automatically updated after release:

```bash
# Check appcast update workflow ran
gh run list --workflow=update-appcast.yml --limit 1

# Verify stable feed includes new release
curl -s https://eyelock.github.io/TermQ/appcast.xml | grep "{VERSION}"
```

## Version Numbering

TermQ follows semantic versioning (MAJOR.MINOR.PATCH):

- **PATCH** (0.6.4 → 0.6.5) - Bug fixes, small improvements
- **MINOR** (0.6.5 → 0.7.0) - New features, backwards compatible
- **MAJOR** (0.9.0 → 1.0.0) - Breaking changes, major milestones

Version is determined entirely from git tags (no VERSION file).

## Release Workflow Details

### CI Verification

The release workflow REQUIRES CI to pass on the commit being released:
- Waits up to 5 minutes for CI to complete
- Fails if CI doesn't pass
- Skipped only for pre-releases (beta/alpha/rc)

### Signing and Notarization

All releases are automatically:
- **Signed** with Developer ID Application certificate
- **Notarized** by Apple (required for Gatekeeper)
- **Stapled** with notarization ticket

This ensures users can install without security warnings.

### Release Artifacts

Each release includes:
- `TermQ-{VERSION}.dmg` - Signed and notarized DMG installer
- `TermQ-{VERSION}.zip` - ZIP archive of app bundle
- `checksums.txt` - SHA-256 checksums for verification

## Release Naming Convention

All releases must use this exact format:
- **Title:** `TermQ v{VERSION}`
- **Tag:** `v{VERSION}`

Examples: `TermQ v0.6.4`, `TermQ v1.0.0`

Never use custom titles or descriptions in the title field.

## Troubleshooting

### Release Workflow Fails on CI Check

The commit must have a passing CI run before release:

```bash
# Check CI status for the commit
git log -1 --format="%H"  # Get commit SHA
gh run list --commit <sha> --workflow=ci.yml
```

If CI hasn't run or failed:
1. Fix the issues on main
2. Wait for CI to pass
3. Delete the failed tag: `git tag -d v{VERSION} && git push origin :v{VERSION}`
4. Re-tag from the fixed commit

### Release Already Exists

If you need to re-release (only in exceptional cases):

```bash
# Delete the release
gh release delete v{VERSION} --yes

# Delete the tag
git tag -d v{VERSION}
git push origin :refs/tags/v{VERSION}

# Re-run the release process
```

### Wrong Version Tagged

```bash
# Delete the wrong tag
git tag -d v{WRONG_VERSION}
git push origin :refs/tags/v{WRONG_VERSION}

# Create correct tag
make release-{patch|minor|major}
```

## What NOT to Do

❌ **NEVER** create releases manually with `gh release create`
❌ **NEVER** tag versions without running `make check` first
❌ **NEVER** use custom release titles or formatting
❌ **NEVER** skip CI verification
❌ **NEVER** push unsigned or unnotarized builds
❌ **NEVER** tag from branches other than main (use hotfix procedure)

## Post-Release

After successful release:

1. **Announce** - Update relevant channels/documentation
2. **Monitor** - Watch for user feedback and issues
3. **Update** - Users with auto-updates enabled will receive notification

## Example: v0.7.0 Release

```bash
# 1. Ensure main is clean and up to date
git checkout main
git pull

# 2. Run pre-release checks
make check

# 3. Create release tag
make release-minor  # 0.6.x → 0.7.0
# Confirms: "Release v0.7.0 [y/N]" → y
# Creates and pushes v0.7.0 tag

# 4. Monitor release workflow
gh run watch --workflow=release.yml

# 5. Verify release
gh release view v0.7.0

# 6. Verify appcast updated
curl -s https://eyelock.github.io/TermQ/appcast.xml | grep "0.7.0"
```

## Quick Reference

```bash
# Pre-release checklist
git checkout main && git pull
make check

# Create release
make release           # Interactive
make release-patch     # Bug fix: 0.6.4 → 0.6.5
make release-minor     # New feature: 0.6.5 → 0.7.0
make release-major     # Breaking change: 0.9.0 → 1.0.0

# Monitor
gh run watch --workflow=release.yml

# Verify
gh release view v{VERSION}
curl -s https://eyelock.github.io/TermQ/appcast.xml | grep "{VERSION}"
```

## Related Procedures

- **Beta Releases:** See `.claude/commands/release-beta.md`
- **Hotfix Releases:** See `.claude/commands/release-hotfix.md`

## Verification Checklist

- [ ] All changes merged to main
- [ ] CI passing on main
- [ ] `make check` passes locally
- [ ] Correct version type selected (patch/minor/major)
- [ ] Release workflow completed successfully
- [ ] Release has proper naming: "TermQ v{VERSION}"
- [ ] Release includes DMG, ZIP, and checksums
- [ ] Release is signed and notarized
- [ ] Appcast updated with new version
- [ ] Not marked as pre-release
