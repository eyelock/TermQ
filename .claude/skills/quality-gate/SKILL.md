---
name: quality-gate
description: TermQ code quality gate. Load when running verification checks before committing. Defines the four checks that must all pass with zero errors.
---

# Quality Gate

All four checks must pass before any code is committed:

| Check | Command | Requirement |
|---|---|---|
| Build | `make build` | Zero errors, zero warnings |
| Lint | `make lint` | Zero violations — `make lint` must exit 0 |
| Format | `make format-check` | Clean — run `make format` to fix |
| Tests | `make test` | All tests pass |

Run all four at once:

```bash
make check
```

The output must be clean. Any `warning:` or `error:` lines in the output are failures.

## Zero Tolerance

Never proceed to commit with build errors, lint errors, formatting violations, or failing tests.

**Verification scope:** Always run a **clean** build before declaring the gate passed:

```bash
swift package clean && make check
```

Incremental compilation caches object files — repeat `make check` runs will not regenerate warnings for already-compiled test files. Only a clean build guarantees the full warning picture. **Never declare success from an incremental build.**

If `make check` passes locally but CI fails, that is a bug — investigate and file an issue rather than pushing again.

## Line Length

Both SwiftLint (`line_length: 120`) and swift-format (`lineLength: 120`) enforce 120-character lines. These rules must stay enabled and in sync. Do **not** disable `line_length` in `.swiftlint.yml`.

When a line is too long, fix the code — do not suppress with `// swiftlint:disable` annotations or by disabling the rule. Long strings must be split manually; neither tool auto-breaks string literals.

## No Suppression Annotations

Do not add `// swiftlint:disable` annotations to silence violations. Disabling rules file-wide or project-wide is also forbidden. Every violation must be fixed at the source.

## Test Target Warnings

Swift compiler warnings in test files (`Tests/**`) only appear when test targets compile (i.e., during `make check` / `make test`). A clean `make build` does not guarantee a clean `make check`. Always use `make check` as the authoritative gate.
