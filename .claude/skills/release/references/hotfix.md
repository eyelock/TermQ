# Hotfix Release Procedure

Use for critical production bugs, security vulnerabilities, or data loss issues that cannot wait for a normal release cycle.

**NEVER bypass the automated release system. If automation fails, fix the automation.**

## Prerequisites

- You know the base version being hotfixed (e.g., v0.6.3)
- The bug is confirmed in production and cannot wait for `develop` to be promoted
- A fix is ready to implement (or already written and tested locally)

## Steps

### 1. Create Hotfix Branch from the Release Tag

```bash
git checkout -b hotfix/v0.6.4 v0.6.3
```

### 2. Implement the Fix and Update CHANGELOG

Apply the fix directly on the hotfix branch. Keep it minimal — only the targeted change.

**Always update `CHANGELOG.md`** in the same commit or as a follow-up commit on the hotfix branch — not as a separate PR afterwards. The changelog entry must be present before tagging.

Any skill or docs updates made during the hotfix should also be committed on the hotfix branch so they can be cleanly cherry-picked in the forward-port PR.

```bash
git add <files>
git commit -m "fix: <description>"
# Update CHANGELOG.md and any skill/docs changes, then:
git add CHANGELOG.md
git commit -m "chore: update CHANGELOG for v0.6.4"
git push -u origin hotfix/v0.6.4
```

### 3. Open a PR to Main and Wait for CI

**Open a PR targeting `main` before tagging.** CI runs on the PR — do not tag until it passes.

```bash
gh pr create --base main --title "fix: hotfix v0.6.4" \
  --body "Hotfix release v0.6.4. Cherry-picks <description> onto v0.6.3."
gh run list --branch hotfix/v0.6.4 --workflow=ci.yml --limit 1
gh run watch <run-id>
```

### 4. Merge PR to Main, Then Tag the Merge Commit

**Merge the PR before tagging.** The tag must point to the merge commit on `main` — not to a commit on the hotfix branch. Tagging from the hotfix branch before merging leaves `main` out of sync and creates ambiguity about what the release contains.

```bash
gh pr merge <pr-number> --merge
git fetch origin
git tag -a "v0.6.4" -m "Release v0.6.4" origin/main
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
git push origin --delete hotfix/v0.6.4
git branch -d hotfix/v0.6.4
```

### 7. Forward-Port to Develop — MANDATORY

**This step is not optional.** Every change that lands on `main` via hotfix MUST also land on `develop`. Skipping this causes divergence that creates merge conflicts on the next develop → main promotion.

**Consolidate everything into a single PR** — do not open multiple PRs for different pieces. One forward-port PR keeps the public history clean. It should include:

- Any fix commits not already on `develop` (cherry-picked from `main`)
- The appcast files auto-updated by `update-appcast.yml` on `main`
- Any CHANGELOG changes from the hotfix branch
- Any skill or docs updates made during the hotfix

```bash
git checkout -b chore-forward-port-v0.6.4 develop
git cherry-pick <fix-commit-sha> <changelog-sha> <skill-sha>
# Also cherry-pick the appcast update commit from main:
git cherry-pick <appcast-commit-sha>
git push -u origin chore-forward-port-v0.6.4
gh pr create --base develop --title "chore: forward-port v0.6.4 hotfix" \
  --body "Forward-ports hotfix v0.6.4 commits, appcast update, and CHANGELOG to develop."
```

Merge once CI passes. If cherry-picks have conflicts (develop has diverged significantly), resolve them before pushing.

**Auto-generated files (appcasts):** The `update-appcast.yml` workflow updates `Docs/appcast.xml` and `Docs/appcast-beta.xml` on `main` automatically after each release. These changes are never automatically forward-ported — include them manually in the forward-port PR.

## What NOT to Do

- NEVER create releases manually with `gh release create`
- NEVER bypass CI verification
- NEVER work around failed automation — fix it instead
- NEVER push unsigned/unnotarized builds
- NEVER skip step 7 — every main change must flow back to develop
- NEVER open multiple forward-port PRs — consolidate into one
