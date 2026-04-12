# Settings Architecture

## Three-Tier System

```
~/.claude/settings.json          — global (all projects)
         ↓
.claude/settings.json            — project (committed, follows worktrees)
         ↓
.claude/settings.local.json      — personal (gitignored, per-worktree)
```

Higher tiers take precedence. Project settings are checked in and shared with the team. Personal settings are local-only.

## What Goes Where

### Project `settings.json` (committed, shared)

Include only what every team member needs:
- Make targets: `make build`, `make test`, `make lint`, `make format`, `make check`
- Git commands: commit, push, pull, branch, fetch, merge, tag, worktree
- GitHub CLI: `gh pr *`, `gh issue *`, `gh release *`, `gh run *`
- WebSearch/WebFetch for documentation lookups

**Do NOT include:**
- Direct Swift tool access (`swift build`, `swiftlint`, `swift-format`)
- Personal scripts or machine-specific paths
- Experimental or rapidly-changing MCP tools

### Personal `settings.local.json` (gitignored)

Personal and debugging tools:
- Direct Swift/Xcode access (`swift build`, `xcodebuild`) for edge-case debugging
- TermQ MCP tools (actively changing during development)
- System utilities (`ls`, `cat`, `rm`, `plutil`, `codesign`, `osascript`)
- Personal scripts and paths
- Extended git commands not needed daily

## Audit

```bash
# Should return empty — no direct tool access in project settings
grep -E "swift build|swiftlint|swift-format" .claude/settings.json

# Check for duplication between files
diff .claude/settings.json .claude/settings.local.json
```

Duplication is waste — if something is in both, remove it from settings.local.json.
