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
