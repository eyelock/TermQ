# Session Initialization

**🛑 YOU MUST read this file at the start of EVERY Claude session.**

**This is step 1 of the Core Development Workflow. Do not skip it.**

## Session Start Checklist

1. **Check git status**
   - Verify current branch
   - Check for uncommitted changes
   - Review recent commits

2. **Verify worktree context**
   - Confirm you're in the correct worktree
   - Check if this is main repo or a feature worktree

## Tool Preferences

### GitHub Operations - Prefer `gh` CLI

**Prefer `gh` CLI for most operations:**

- **For writes** (creating, updating): Always use `gh` CLI
  - ✅ `gh pr create`, `gh issue create`, `gh pr merge`
  - ❌ Don't use MCP write operations

- **For reads** (viewing, listing): `gh` CLI preferred, MCP acceptable
  - ✅ Prefer: `gh pr view`, `gh issue list`
  - 🟡 Acceptable: `mcp__github__get_pull_request` (reads work fine)

**Why prefer gh CLI:**
- Better error handling
- Aligns with git worktree workflow
- More reliable for write operations
- Consistent experience across all GitHub operations

### Build & Test Operations - Use Make Targets

**ALWAYS use make targets, NEVER use swift/swiftlint/swift-format directly:**

- ❌ DON'T use: `swift build`, `swift test`
- ✅ DO use: `make build`, `make test`

- ❌ DON'T use: `swiftlint lint`, `swift-format format`
- ✅ DO use: `make lint`, `make format`

- ❌ DON'T use: Direct tool commands
- ✅ DO use: `make check` (runs all checks)

**Why:** The Makefile handles DEVELOPER_DIR, warning filters, CI detection, and tool installation. Direct commands bypass these critical configurations.

### File Operations - Use Specialized Tools

When exploring the codebase:
- For general exploration: Use `Task` tool with `subagent_type=Explore`
- For specific file searches: Use `Glob` or `Grep` directly
- For reading files: Use `Read` tool, not `cat` or `Bash`
- For editing files: Use `Edit` tool, not `sed` or `Bash`

## Context Loading Strategy

- **First time in a worktree:** Read `CLAUDE.md` and relevant command docs
- **Continuing work:** Review recent commits and session notes
- **Large codebase exploration:** Use Task/Explore agent to avoid context bloat
- **Specific questions:** Use targeted Grep/Glob, then Read specific files

## Quick Reference

Project documentation locations:
- Session handovers: `.claude/sessions/`
- Implementation plans: `.claude/plans/`
- Release procedures: `.claude/commands/release*.md`
- Code style guide: `.claude/commands/code-style.md`
- Localization guide: `.claude/commands/localization.md`

---

## ✅ Session Initialized - What's Next?

You've completed step 1. Choose your path:

### If implementing code:
**→ NEXT: Read [implementation-prepare.md](implementation-prepare.md) (step 2 of workflow)**

**🚨 DO NOT use Edit or Write tools until you've read implementation-prepare.md**

### If continuing previous work:
1. Check `.claude/sessions/` for handover notes
2. Run `git status` to see current state
3. Resume at appropriate workflow step (likely step 2 or 3)

### If only investigating/exploring:
- Use `Task` tool with `subagent_type=Explore` for broad exploration
- Use targeted `Grep`/`Glob` queries for specific searches
- No need to follow full workflow for investigation-only tasks

**Need the full workflow reference?** → [CLAUDE.md](../CLAUDE.md)
