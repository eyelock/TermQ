---
name: release
description: TermQ release procedures. Load when executing any release — stable, beta, or hotfix. Covers versioning, tagging, monitoring, and verification.
---

# Release Procedures

## Release System Overview

Releases are fully automated via GitHub Actions. The workflow is:

1. Developer creates an annotated git tag
2. `release.yml` workflow triggers, verifies CI, builds, signs, notarizes, publishes
3. `update-appcast.yml` updates Sparkle feed(s) for auto-update delivery

**Never create releases manually.** Never use `gh release create` directly. If automation fails, fix the automation.

## Versioning

TermQ uses semantic versioning. Version is determined entirely from git tags — no VERSION file.

- **PATCH** (0.6.4 → 0.6.5) — bug fixes, small improvements
- **MINOR** (0.6.5 → 0.7.0) — new features, backwards compatible
- **MAJOR** (0.9.0 → 1.0.0) — breaking changes, major milestones

## Appcast Feeds

| Feed | Content | Used by |
|---|---|---|
| `appcast.xml` | Stable releases only | Default update channel |
| `appcast-beta.xml` | All releases including pre-releases | Beta opt-in users |

## Releasing from a Worktree

Development runs many worktrees at once, and **git allows a branch to be checked out in only
one worktree at a time**. From any worktree other than the one holding `develop` (or `main`),
the usual first step fails:

```
$ git checkout develop
fatal: 'develop' is already used by worktree at '/path/to/main/checkout'
```

This is the normal state of the repo, not an error to work around. Do **not** pass
`--ignore-other-worktrees` (it yanks the branch out from under the other worktree and still
leaves it at whatever commit it was on), and do not reach into another worktree to move its
branch — another session may be working there.

A release needs a **tag on the right commit**, and `git tag` accepts any commit-ish. So tag the
remote-tracking ref by SHA, from wherever you are:

```bash
git fetch origin
SHA=$(git rev-parse origin/develop)          # origin/main for a stable release
git log -1 --oneline "$SHA"                  # eyeball it — is this what you mean to ship?
git tag -a "v{VERSION}" "$SHA" -m "Release v{VERSION}"
```

Verify before pushing — these three checks catch the mistakes that are painful to undo:

```bash
git cat-file -t "v{VERSION}"                 # must print "tag" (annotated, not lightweight)
git rev-list -n1 "v{VERSION}"                # must equal $SHA
git ls-remote --exit-code --tags origin "v{VERSION}" && echo "ALREADY EXISTS — stop"
```

```bash
git push origin "v{VERSION}"                 # this is what triggers release.yml
```

The workflow builds from the tag, so the artifact is identical either way. Your local
`develop`/`main` stays where it is — expected and harmless; pull it next time you work there.

**The checkout is a convenience, not a prerequisite.** What matters is that the SHA you tag is
the tip of the branch you intend to release, which `git rev-parse origin/<branch>` guarantees
after a fetch.

### Do not use `make release-*` from a worktree

`make release-patch|minor|major` (and the underlying `tag-release`) **tag `HEAD`**, not `main`.
From a worktree, `HEAD` is that worktree's feature branch, so they will happily tag the wrong
commit after a single `[y/N]` warning. They are also interactive — two `read -p` prompts — so
they cannot be driven non-interactively by an agent.

Use them only from the checkout that actually holds `main`. Everywhere else, tag by SHA as above.

## Release Types

See the detailed procedure for each release type:

- [stable.md](references/stable.md) — standard release from main
- [beta.md](references/beta.md) — pre-release for testing
- [hotfix.md](references/hotfix.md) — critical patch on a branch

## Release Naming

All releases must use this exact format:
- **Title:** `TermQ v{VERSION}`
- **Tag:** `v{VERSION}`

## Monitoring Commands

```bash
gh run list --workflow=release.yml --limit 1
gh run watch <run-id>
gh release view v{VERSION}
gh run list --workflow=update-appcast.yml --limit 1
```
