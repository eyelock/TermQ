---
name: quality-gate
description: TermQ code quality gate. Load when running verification checks before committing. Defines the four checks that must all pass with zero errors.
---

# Quality Gate

All four checks must pass before any code is committed:

| Check | Command | Requirement |
|---|---|---|
| Build | `make build` | Zero errors |
| Lint | `make lint` | Zero errors (minimize warnings) |
| Format | `make format-check` | Clean — run `make format` to fix |
| Tests | `make test` | All tests pass |

Run all four at once:

```bash
make check
```

## Zero Tolerance

Never proceed to commit with build errors, lint errors, formatting violations, or failing tests.

If `make check` passes locally but CI fails, that is a bug — investigate and file an issue rather than pushing again.
