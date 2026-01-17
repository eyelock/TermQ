# Claude Configuration Audit

**Use this document to audit and improve Claude Code configuration and workflows.**

## Purpose

This document captures the design decisions, principles, and best practices for organizing Claude Code workflows in the TermQ project. Use it to:

1. **Onboard new team members** - Understand why our workflows are structured this way
2. **Audit configuration** - Review settings files for issues or improvements
3. **Maintain consistency** - Ensure changes align with our architecture
4. **Improve workflows** - Identify gaps and opportunities for optimization

## Configuration Architecture

### Three-Tier Settings System

```
~/.claude/settings.json              # Global (all projects)
    ↓
.claude/settings.json               # Project (checked in, follows to worktrees)
    ↓
.claude/settings.local.json         # Personal (gitignored, per-worktree)
```

**Design Principles:**

1. **Project settings.json (shared):**
   - Essential permissions ALL team members need
   - Make targets (build, test, lint, format, check)
   - Git commands (commit, push, branch, etc.)
   - GitHub CLI (pr, issue, release operations)
   - WebSearch/WebFetch for documentation
   - **NO** direct tool access (swift, swiftlint, swift-format)
   - **NO** experimental features (beta MCP tools, personal productivity tools)
   - **NO** personal scripts or machine-specific paths

2. **Personal settings.local.json (gitignored):**
   - Personal productivity tools (not ready for team use)
   - TermQ MCP tools (changing rapidly in dev)
   - GitHub MCP tools (don't work well, but keep for testing)
   - Direct tool access (swift, xcodebuild) for debugging
   - Extended git/gh commands
   - System utilities (ls, cat, rm, etc.)
   - macOS-specific tools (plutil, codesign, osascript)
   - Personal scripts and paths
   - Testing binaries

3. **Global settings (optional):**
   - Cross-project permissions
   - Personal preferences that span all repositories

### Why Make Targets, Not Direct Tools?

**Problem:** Direct tool commands (`swift build`, `swiftlint lint`) bypass critical configurations.

**Solution:** Always use make targets. The Makefile handles:
- `DEVELOPER_DIR` for Xcode toolchain
- Warning filters for third-party dependencies
- CI detection for GitHub annotations
- Tool installation (auto-installs if missing)
- Consistent behavior across local/CI

**Enforcement:**
- ❌ Removed from `settings.json`: `Bash(swift build:*)`, `Bash(swiftlint:*)`
- ✅ Added to documentation: `init.md`, `implementation-checks.md`
- ✅ Kept in `settings.local.json`: For debugging/edge cases only

## Workflow Architecture

### Layered Documentation Design

**Tier 1: Core Development Workflow** (every feature/fix)
```
1. init.md                    → Session startup
2. implementation-prepare.md  → Pre-coding checklist
3. (Implement code)           → Follow code-style.md
4. implementation-checks.md   → Post-coding verification
5. commit-pr.md              → Create commits and PRs
```

**Tier 2: Specialized Workflows** (extends core)
```
release.md        → Core workflow (1-5) + versioning + changelog
release-beta.md   → Core workflow (1-5) + beta + Sparkle
release-hotfix.md → Core workflow (1-5) + hotfix branching
```

**Tier 3: Domain Guides** (referenced when needed)
```
code-style.md     → Swift patterns, concurrency (step 3)
localization.md   → String management (step 4)
```

**CLAUDE.md** = Navigation hub with "Choose Your Adventure" quick reference

### Why This Structure?

**Problems Solved:**

1. **Context loss in worktrees** - Settings didn't follow, workflows had to be re-explained
2. **Inconsistent processes** - Team members did things differently
3. **Repeated questions** - "How do I make a PR?", "What checks to run?"
4. **Tool confusion** - When to use GitHub MCP vs gh CLI? When to use make vs swift?
5. **Documentation sprawl** - Information scattered, hard to find

**Solutions:**

1. **Composable workflows** - Pick the path that fits your task
2. **Clear hierarchy** - Core → Specialized → Domain
3. **Cross-referencing** - Everything links together
4. **Tool preferences** - Explicit guidance on which tools to use
5. **Single source of truth** - CLAUDE.md as navigation hub

## Common Audit Checks

### 1. Check Settings Duplication

**Problem:** Permissions duplicated between `settings.json` and `settings.local.json`

**Check:**
```bash
# Compare the files - local should only have extras
diff .claude/settings.json .claude/settings.local.json
```

**Fix:** Remove duplicates from `settings.local.json` - it should only contain:
- Experimental features (beta MCP, personal tools)
- Debugging tools (direct swift/xcodebuild)
- Personal scripts/paths
- Extended commands not needed by everyone

### 2. Check for Direct Tool Access

**Problem:** Direct tool commands in project settings bypass Makefile

**Check:**
```bash
# Should return EMPTY - no direct tool access
grep -E "swift build|swiftlint|swift-format" .claude/settings.json
```

**Fix:** Remove direct tool access from `settings.json`. Only make targets allowed.

### 3. Check Tool Preference Documentation

**Problem:** Claude tries to use tools we don't want (GitHub MCP, direct swift)

**Check files:**
- `.claude/commands/init.md` - Should explicitly warn against GitHub MCP and direct tools
- `.claude/commands/implementation-checks.md` - Should emphasize make targets

**Fix:** Add/update tool preference sections with ❌/✅ examples

### 4. Check Workflow Cross-References

**Problem:** Documentation doesn't link together, workflows unclear

**Check:**
- Does `CLAUDE.md` link to all command docs?
- Does each workflow doc link to next step?
- Does "Choose Your Adventure" section cover all paths?

**Fix:** Update cross-references, ensure navigation is clear

### 5. Check for Missing Workflow Steps

**Problem:** Gaps in workflow cause confusion or missed checks

**Common gaps:**
- No PR review check (miss reviewer comments)
- No localization validation for UI changes
- No manual testing reminder
- No session handover notes

**Fix:** Add checklist items to appropriate workflow docs

## Quick Audit Script

Run these checks periodically:

```bash
# 1. Check for direct tool access in project settings
echo "=== Checking for direct tool access in settings.json ==="
grep -E "swift|swiftlint|swift-format" .claude/settings.json || echo "✅ Clean"

# 2. Check settings files exist with correct permissions
echo "=== Checking settings files ==="
ls -l .claude/settings*.json

# 3. Check all workflow docs exist
echo "=== Checking workflow documentation ==="
ls -1 .claude/commands/*.md

# 4. Verify CLAUDE.md structure
echo "=== Checking CLAUDE.md structure ==="
grep -E "^## " .claude/CLAUDE.md
```

## Improvement Opportunities

When auditing, look for:

1. **New patterns emerging** - Are we repeatedly doing something that should be a workflow doc?
2. **Missing make targets** - Are we using direct commands that should be wrapped?
3. **Tool confusion** - Do we need to add more tool preference guidance?
4. **Workflow gaps** - Are there steps we consistently forget?
5. **Documentation drift** - Do the docs match reality?

## Session Start Checklist for Audits

When performing a configuration audit:

1. **Read this document** - Refresh on design principles
2. **Run quick audit script** - Check for common issues
3. **Review recent commits** - Look for configuration changes
4. **Check worktree behavior** - Does settings.json work in worktrees?
5. **Test tool preferences** - Does Claude try to use banned tools?
6. **Review workflows** - Are docs clear and complete?
7. **Document findings** - File GitHub issues or create session notes

## Questions to Ask

**For Settings:**
- Does every permission in `settings.json` serve the whole team?
- Is there duplication between `settings.json` and `settings.local.json`?
- Are we allowing tools we explicitly don't want to use?
- Are path-specific permissions (with full paths) in the right place?

**For Workflows:**
- Can someone follow this workflow without asking questions?
- Does each step link to the next?
- Are tool preferences explicit?
- Do we have examples (good/bad)?
- Is the "why" explained?

**For Documentation:**
- Is navigation easy?
- Are cross-references correct?
- Is the structure scannable?
- Does it match reality?

## Contact & Feedback

When you find issues or have suggestions:
1. File a GitHub issue
2. Create session notes in `.claude/sessions/`
3. Update this document with what you learned
4. Share with the team

---

*This document itself should be audited periodically - does it still reflect our best practices?*
