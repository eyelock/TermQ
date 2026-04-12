---
name: code-style
description: TermQ Swift code style and patterns. Load when writing or reviewing Swift code. Covers Swift 6 concurrency, error handling, memory management, UI components, and testing.
---

# TermQ Code Style

Detailed patterns are in references/ — load the relevant file for the area you're working in:

- [swift-concurrency.md](references/swift-concurrency.md) — Sendable, actor isolation, god object decomposition, model separation
- [error-handling.md](references/error-handling.md) — per-context strategies (CLI, MCP, ViewModel, file ops)
- [memory-management.md](references/memory-management.md) — closure capture rules, event monitors, timers
- [ui-components.md](references/ui-components.md) — reusable SwiftUI components (PathInputField, SharedToggle, etc.)
- [testing-patterns.md](references/testing-patterns.md) — MCP type helpers, test data isolation

## Core Principles

- **Swift 6 strict concurrency** — all code must compile clean. No suppressions without justification.
- **No god objects** — classes over ~400 lines with mixed concerns should be split.
- **Typed errors** — never `NSError(domain: "", ...)`. Silent `try?` only for truly optional operations.
- **`[weak self]` in class closures** — prevent retain cycles. `[self]` is fine in SwiftUI struct views.
- **Sendable boundary** — `TermQShared` types are Sendable structs; `TermQCore` types are Observable, not Sendable. Never mix.

## Refactoring Checklist

1. Swift 6 Sendable: check static properties, extract GCD to `@unchecked Sendable` helpers, annotate callbacks
2. God object split: identify responsibility groups, use `configure()` callback pattern, add proxy properties
3. Generic extraction: define protocol for varying parts, create generic with constraint
4. Model separation: Observable in TermQCore (app-only), Sendable structs in TermQShared (multi-target)
5. Testing: use MCP type helper functions, isolate test data in temp directories
6. Error handling: CLI throws, MCP returns `isError: true`, ViewModels log + update state
7. Memory: `[weak self]` in class closures, event monitor cleanup in `onDisappear`, dispatch sources in `deinit`
