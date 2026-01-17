# Session Initialization

**Read this file at the start of every Claude session.**

## Session Start Checklist

1. **Initialize ACME** (if available)
   - Check for pending items, reviews, and tasks
   - Review any session handover notes from `.claude/sessions/`
   - Log effort throughout the session

2. **Check git status**
   - Verify current branch
   - Check for uncommitted changes
   - Review recent commits

3. **Verify worktree context**
   - Confirm you're in the correct worktree
   - Check if this is main repo or a feature worktree

## Tool Preferences

### GitHub Operations - Use `gh` CLI, NOT GitHub MCP Tools

**IMPORTANT:** GitHub MCP tools (`mcp__github__*`) do not work well for our workflow. Always use the `gh` CLI instead:

- ❌ DON'T use: `mcp__github__get_pull_request`
- ✅ DO use: `gh pr view`

- ❌ DON'T use: `mcp__github__search_issues`
- ✅ DO use: `gh issue list` or `gh search`

- ❌ DON'T use: `mcp__github__get_pull_request_files`
- ✅ DO use: `gh pr diff` or `gh pr view --json files`

**Why:** The MCP tools have poor error handling and don't align with our git worktree workflow.

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
- **Continuing work:** Check ACME for context, review recent commits
- **Large codebase exploration:** Use Task/Explore agent to avoid context bloat
- **Specific questions:** Use targeted Grep/Glob, then Read specific files

## Quick Reference

Project documentation locations:
- Session handovers: `.claude/sessions/`
- Implementation plans: `.claude/plans/`
- Release procedures: `.claude/commands/release*.md`
- Code style guide: `.claude/commands/code-style.md`
- Localization guide: `.claude/commands/localization.md`
