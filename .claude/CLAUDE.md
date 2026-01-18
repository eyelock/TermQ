# Claude - TermQ

## 🛑 READ THIS BEFORE WRITING ANY CODE

**MANDATORY: If you're about to write, edit, or implement ANY code:**

1. **FIRST** → Read **[commands/implementation-prepare.md](commands/implementation-prepare.md)**
   - Gather context, verify environment, create plan
   - Running Edit or Write tools without reading this leads to incomplete implementations

2. **THEN** → Write your code following [code-style.md](commands/code-style.md)

3. **AFTER** → Read **[commands/implementation-checks.md](commands/implementation-checks.md)**
   - Build, lint, test, review before committing
   - Every check must pass - zero tolerance for errors

**This is not optional. Following this workflow prevents broken builds, wasted CI runs, and incomplete implementations.**

---

## 📋 Core Development Workflow

**YOU MUST follow this 5-step workflow for ALL features, fixes, and refactoring:**

### 1. Session Init
→ **[commands/init.md](commands/init.md)** - Session startup, git status, verify worktree

### 2. Prepare
→ **[commands/implementation-prepare.md](commands/implementation-prepare.md)** - Gather context, verify environment, plan implementation

**🚨 DO NOT skip step 2 - you MUST read this file before using Edit or Write tools**

### 3. Implement → 4. Check (Iterative Loop) 🔄

**These steps form a cycle - repeat until all checks pass:**

**3. Implement**
→ Write code following [code-style.md](commands/code-style.md)

**4. Check**
→ **[commands/implementation-checks.md](commands/implementation-checks.md)** - Build, lint, test, review changes

**If checks fail:** Return to step 3, fix issues, repeat
**If checks pass:** Proceed to step 5

### 5. Commit & PR
→ **[commands/commit-pr.md](commands/commit-pr.md)** - Create commits and pull requests

---

## 🚀 Quick Start

**Starting a new session?** Read **[commands/init.md](commands/init.md)** first.

This gives you:
- Session startup checklist
- Tool preferences (GitHub, file operations)
- Context loading strategy

---

## 🔄 Specialized Workflows

**These extend the core workflow for specific scenarios:**

- **[commands/release.md](commands/release.md)** - Standard release from main branch
  - Follow core workflow (1-5) + versioning + changelog + tagging

- **[commands/release-beta.md](commands/release-beta.md)** - Beta releases with Sparkle
  - Follow core workflow (1-5) + beta versioning + Sparkle integration

- **[commands/release-hotfix.md](commands/release-hotfix.md)** - Critical patches
  - Follow core workflow (1-5) + hotfix branching + cherry-picking

---

## 📚 Domain Guides

**Reference these when working in specific areas:**

- **[commands/code-style.md](commands/code-style.md)** - Swift patterns, concurrency, project conventions
- **[commands/localization.md](commands/localization.md)** - String management, translation workflow

---

## 🎯 Communication Preferences

### Complex Topics
When working with complex technical topics (architecture, schema design, multi-step planning):
- Take a guided, conversational approach
- Present context and explain the problem first
- Ask clarifying questions ONE AT A TIME
- Wait for response before moving to next question
- Don't dump large analysis documents all at once
- Frame it as a discussion, not a report

### Feedback Sessions
When I say "let me give you feedback" or similar:
- Wait for ALL feedback before making code changes
- I will explicitly say "done", "finished", "that's all" when ready for you to act
- Acknowledge each point briefly but don't implement mid-session
- Summarize what you understood before proceeding

---

## 🛡️ Project Standards

### Planning & Documentation
- ALWAYS put plans in `.claude/plans/`
- ALWAYS put session handovers in `.claude/sessions/`

### Responsible CI/CD Usage

**Every CI run consumes energy. Be responsible.**

Before pushing ANY code:
1. Run `make check` locally - this runs the same checks as CI
2. Fix ALL errors before pushing
3. Never push "to see if CI catches something"

This project uses path filtering - CI only runs when code-relevant files change.

### Pre-Push Requirements (MANDATORY)

**NEVER push code or create a PR without running locally:**

```bash
make check  # Runs: build, lint, format-check, test
```

Individual checks:
```bash
make build         # Must complete with zero errors
make format        # Format all code
make lint          # Must have zero errors (warnings acceptable but minimize)
make test          # All tests must pass
```

**Note:** The Makefile automatically handles:
- DEVELOPER_DIR for Xcode toolchain
- CI detection for GitHub-specific SwiftLint output
- Tool installation (SwiftLint, swift-format) if missing

**If local checks pass but CI fails**: This is a BUG. Investigate and file an issue.

### Code Hygiene

For the complete pre-commit checklist, see **[commands/implementation-checks.md](commands/implementation-checks.md)**.

This includes build verification, code quality review, testing, and domain-specific checks (localization, APIs, build/CI).

---

## 🗂️ Directory Structure

```
.claude/
├── CLAUDE.md              # This file - your guide
├── settings.json          # Project-wide permissions (checked in, follows to worktrees)
│                          # Example: Make targets, git commands, gh CLI
├── settings.local.json    # Personal overrides (gitignored, per-worktree)
│                          # Example: Debugging tools, personal productivity tools
├── commands/              # Workflow documentation
│   ├── init.md                      # Session initialization
│   ├── implementation-prepare.md    # Pre-coding checklist
│   ├── implementation-checks.md     # Post-coding verification
│   ├── commit-pr.md                 # Commit and PR guide
│   ├── release.md                   # Standard releases
│   ├── release-beta.md              # Beta releases
│   ├── release-hotfix.md            # Hotfix releases
│   ├── code-style.md                # Swift patterns
│   └── localization.md              # String management
├── plans/                 # Implementation plans (gitignored)
└── sessions/              # Session handovers (gitignored)
```

---

## 🎮 Choose Your Adventure

**Starting a session?**
→ [commands/init.md](commands/init.md)

**Working on a feature or fix?**
→ Follow the [Core Development Workflow](#-core-development-workflow) (steps 1-5)

**Creating a release?**
→ Follow Core Workflow + [commands/release.md](commands/release.md)

**Need to ship a hotfix?**
→ Follow Core Workflow + [commands/release-hotfix.md](commands/release-hotfix.md)

**Modifying UI strings?**
→ Reference [commands/localization.md](commands/localization.md) during step 4 (Check)

**Writing new Swift code?**
→ Reference [commands/code-style.md](commands/code-style.md) during step 3 (Implement)

**Doc-only changes?**
→ Follow steps 1-2-3-5 (skip heavy build/test in step 4)

**Investigating an issue?**
→ Steps 1-2 only (prepare context, no implementation)

**Addressing PR feedback?**
→ Start at step 2 (prepare), then 3-4-5

---

*"You're building a choose-your-own-adventure workflow guide!"* 🎲
