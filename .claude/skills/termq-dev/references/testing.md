# TermQ Testing

## Test Target Structure

All unit tests live in `Tests/TermQTests/` and import only `TermQCore`:

```swift
@testable import TermQCore
```

This means:
- `TermQCore` types (`TerminalCard`, `Board`, `Column`, `Tag`, …) — **fully testable**
- `TermQ` types (`BoardViewModel`, `ContentView`, `TabManager`, …) — **not unit-testable**
- `TermQShared` / `MCPServerLib` / `termq-cli` — tested indirectly via `TermQCore`

## Rule: Tests Are Not Optional

Every code change must include tests. No exceptions.

**If the changed logic lives in `TermQCore`:** add or update tests directly.

**If the changed logic lives in the `TermQ` layer (ViewModels, Views):** extract the testable predicate or decision into a form that can be exercised from `TermQTests`. Common patterns:
- Test the matching/filtering predicate directly against `TerminalCard` and `Board` instances
- Test the data-model outcome (e.g., card ends up in `board.cards`) without needing the ViewModel

Do not accept "the code is in a View and can't be tested" as a reason to skip tests. If there is logic worth writing, there is a test worth writing.

## Test File Conventions

| What changed | Where to add tests |
|---|---|
| `TerminalCard` properties or behaviour | `TerminalCardTests.swift` |
| `Board` operations | `BoardTests.swift` |
| Harness launch / card matching | `HarnessCardTests.swift` |
| Tag logic | `TagTests.swift` |
| New distinct feature | Create `<Feature>Tests.swift` |

## Running Tests

```bash
make test
```

All tests must pass before committing.
