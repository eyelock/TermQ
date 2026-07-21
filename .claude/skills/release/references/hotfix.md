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

### 7. Back-Merge to Develop — MANDATORY

**This step is not optional.** Every change that lands on `main` via hotfix MUST also land on `develop`. Skipping this (or substituting cherry-picks) causes permanent branch divergence — main accumulates commits that are never in develop's ancestry, and the gap grows with every release cycle.

**Use a real `git merge`, not cherry-picks.** Cherry-picks create new commits with different SHAs. Even when the content is identical, git sees main's original commits as absent from develop's history, so the divergence count keeps climbing. A merge commit pulls all of main's history into develop's ancestry in one step.

Wait for the appcast PR (`hotfix/appcast-update → main`) to merge before opening the back-merge, so the appcast files are included automatically.

```bash
# 1. Confirm the appcast PR has merged
gh pr list --base main --search "appcast in:title" --state merged --limit 1

# 2. Build the back-merge branch from develop
git fetch origin
git checkout -b chore/back-merge-v0.6.4 develop
git merge origin/main          # real merge — never cherry-pick
# Resolve any conflicts (CHANGELOG is the most common — keep develop's [Unreleased]
# section and accept main's released version sections below it)
git push -u origin chore/back-merge-v0.6.4

# 3. Open the PR
gh pr create --base develop \
  --title "chore: back-merge v0.6.4 hotfix into develop" \
  --body "Merges main (hotfix v0.6.4, CHANGELOG, and appcast updates) into develop. Keeps branch histories in sync."
```

Merge once CI passes (true merge, not squash — squashing would re-introduce the divergence).

## What NOT to Do

- NEVER create releases manually with `gh release create`
- NEVER bypass CI verification
- NEVER work around failed automation — fix it instead
- NEVER push unsigned/unnotarized builds
- NEVER skip step 7 — every main change must flow back to develop
- NEVER use cherry-picks in step 7 — always `git merge origin/main`
- NEVER squash the back-merge PR — squashing re-introduces divergence
