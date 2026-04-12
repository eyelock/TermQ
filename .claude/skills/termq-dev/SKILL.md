---
name: termq-dev
description: TermQ development context. Load at session start and when working on TermQ. Covers project structure, module layout, toolchain rules, worktree workflow, and settings architecture.
compatibility: Designed for Claude Code. Requires Xcode, Swift 6, macOS 15+.
---

# TermQ Development

TermQ is a macOS terminal emulator built in Swift 6. It wraps tmux sessions in a native SwiftUI interface and exposes them via an MCP server for AI-driven terminal control.

## Module Structure

```
Sources/
├── TermQ/          — SwiftUI app: ViewModels, UI, @Observable types
├── TermQCore/      — Observable types for the app (TerminalCard, Board)
├── TermQShared/    — Sendable structs shared across all targets (MCPCard, MCPBoard, BoardLoader)
├── MCPServerLib/   — MCP server implementation (depends on TermQShared)
└── termq-cli/      — CLI tool (depends on TermQShared)
```

**Key boundary:** `TermQCore` types are `@Observable` for SwiftUI binding — not `Sendable`. `TermQShared` types are `Sendable` structs safe for cross-actor and cross-target use. Never mix these.

## Essential Rules

Always use `make` targets — never call Swift tools directly. See [toolchain.md](references/toolchain.md).

Use git worktrees for feature work. See [worktrees.md](references/worktrees.md).

Follow the three-tier settings architecture. See [settings.md](references/settings.md).

## Session Start

See [session-start.md](references/session-start.md) for the session initialization checklist.
