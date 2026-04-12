# TermQ Toolchain

## Always Use Make Targets

Never call Swift tools directly — the Makefile handles critical configuration that direct commands bypass.

| ❌ Don't use | ✅ Use instead |
|---|---|
| `swift build` | `make build` |
| `swift test` | `make test` |
| `swiftlint lint` | `make lint` |
| `swift-format format` | `make format` |
| (all of the above) | `make check` |

**Why:** The Makefile handles:
- `DEVELOPER_DIR` for the correct Xcode toolchain
- Warning filters for third-party dependencies
- CI detection for GitHub annotations output format
- Auto-installation of missing tools (SwiftLint, swift-format)

Running `swift build` directly will use the wrong toolchain or produce unfiltered warnings.

## GitHub Operations

**Prefer `gh` CLI over MCP tools:**

- **Writes** (create PR, create issue, merge, release): always `gh` CLI
- **Reads** (view PR, list issues): `gh` CLI preferred; MCP reads are acceptable

Why: better error handling, aligns with git worktree workflow, more reliable for write operations.

## File Operations in Claude Code

| Task | Use |
|---|---|
| Search for files | `Glob` tool |
| Search file content | `Grep` tool |
| Read a file | `Read` tool |
| Edit a file | `Edit` tool |
| Broad exploration | `termq-explorer` agent |

Never use Bash equivalents (`find`, `grep`, `cat`, `sed`) when these tools are available.
