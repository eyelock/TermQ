# Commit and Pull Request

**Run this after [implementation-checks.md](implementation-checks.md) passes.**

## Branch Naming Conventions

Use conventional naming with hyphens (not slashes):

```
feat-<short-description>      # New features
fix-<short-description>        # Bug fixes
refactor-<short-description>   # Code refactoring
docs-<short-description>       # Documentation only
ci-<short-description>         # CI/CD changes
test-<short-description>       # Test additions/changes
```

**Why hyphens?** Keeps worktree directories flat in `../TermQ-worktrees/` for easy visibility.

Examples:
- `feat-terminal-quick-actions`
- `fix-terminal-selection-focus`
- `ci-persistent-claude-permissions`

## Commit Messages

### Format

Use **Conventional Commits** format:

```
<type>(<scope>): <subject>

<body>

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

### Types
- `feat:` - New feature
- `fix:` - Bug fix
- `refactor:` - Code change that neither fixes a bug nor adds a feature
- `docs:` - Documentation only
- `test:` - Adding or updating tests
- `ci:` - CI/CD changes
- `perf:` - Performance improvements
- `style:` - Code style changes (formatting, etc.)
- `chore:` - Maintenance tasks

### Scope (optional but recommended)
- `cli` - CLI tool changes
- `mcp` - MCP server changes
- `ui` - UI changes
- `core` - Core functionality
- `build` - Build system
- `localization` - Localization changes

### Examples

```
feat(cli): Add quick terminal creation button

Adds a "+" button in the toolbar for quickly creating terminals
without using keyboard shortcuts.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

```
fix(ui): Correct terminal selection focus behavior

Terminal selection now properly updates when switching between
terminals using keyboard shortcuts.

Fixes #123

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

## Creating the Commit

### Using Git Commands

```bash
# Stage files
git add <files>

# Create commit with Co-Authored-By
git commit -m "$(cat <<'EOF'
feat(scope): Your commit message

Optional body text here.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

### Commit Checklist

- [ ] All changes staged (`git add`)
- [ ] Commit message follows conventional format
- [ ] Co-Authored-By line included
- [ ] Message is clear and describes WHY, not just WHAT
- [ ] References issue number if applicable (Fixes #123)

## Creating Pull Request

### Before Creating PR

- [ ] All commits follow message format
- [ ] **Ensure branch is up-to-date with main** (MANDATORY)

**Check for conflicts and merge main:**

```bash
# 1. Fetch latest main
git fetch origin main

# 2. Check if behind main
git log HEAD..origin/main --oneline

# 3. If commits shown, merge main into your branch
git merge origin/main

# 4. Resolve any conflicts if they occur
# 5. Push updated branch
git push
```

- [ ] Branch is pushed to origin with latest changes

### PR Title

Use the same format as commit messages:
```
feat(scope): Brief description of the PR
```

### PR Description Template

```markdown
## Summary
Brief overview of changes and why they were made.

## Changes
- Change 1
- Change 2
- Change 3

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass (if applicable)
- [ ] Manual testing completed
- [ ] Localization validated (if UI changes)

## Related Issues
Fixes #123
Relates to #456

## Screenshots (if UI changes)
[Add screenshots here]

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### Create PR

```bash
# Using gh CLI
gh pr create --title "feat(scope): Description" --body "$(cat <<'EOF'
## Summary
...

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Or use the GitHub web interface.

### PR Checklist

- [ ] Title follows conventional format
- [ ] Description clearly explains changes
- [ ] All checks pass (CI, tests, lint)
- [ ] Reviewers assigned (if applicable)
- [ ] Labels added (if applicable)
- [ ] Linked to issues

## After PR Creation

- [ ] Monitor CI/CD status
- [ ] **Check for merge conflicts** (see below)
- [ ] Respond to review comments
- [ ] Update PR based on feedback
- [ ] Ensure all conversations resolved before merge

### Handling Merge Conflicts (After PR Created)

**If GitHub reports merge conflicts:**

```bash
# 1. Fetch latest main
git fetch origin main

# 2. Merge main into your branch
git merge origin/main

# 3. If conflicts occur, resolve them:
#    - Edit conflicted files
#    - Mark as resolved: git add <file>
#    - Complete merge: git commit

# 4. Push updated branch (updates PR automatically)
git push
```

**Check PR status:**
```bash
gh pr view <pr-number>  # Verify conflicts resolved
```

## Before Merging: Review Comments Check

**CRITICAL:** Always check for unresolved review comments before merging.

### Check for Review Comments

```bash
# View all review comments on your PR
gh pr view --comments

# Or check specific PR by number
gh pr view <pr-number> --comments
```

**Look for:**
- 🤖 **Claude Code Review comments** - Automated code review feedback
- 👤 **Human reviewer comments** - Team member feedback
- 💬 **Unresolved conversations** - Discussions needing resolution

### Process Review Feedback

**For each comment:**

1. **Read and understand** - What is the reviewer suggesting?
2. **Assess validity** - Is this a real issue or false positive?
3. **Make changes** - Address valid concerns in new commits
4. **Respond** - Explain your changes or reasoning
5. **Mark resolved** - Only when actually addressed

**Common mistakes:**
- ❌ Ignoring automated review comments
- ❌ Merging with unresolved conversations
- ❌ Not responding to reviewer questions
- ❌ Dismissing valid concerns without discussion

**Example workflow:**
```bash
# 1. Check for comments
gh pr view --comments

# 2. If issues found, fix them
make lint-fix          # If linter issues
make format            # If formatting issues
# ... make code changes as needed ...

# 3. Commit fixes
git add .
git commit -m "fix: address review feedback"

# 4. Push and verify CI passes again
git push

# 5. Respond to comments on GitHub
gh pr comment --body "Fixed in latest commit"

# 6. Verify all conversations resolved
gh pr view --comments
```

## Branch Protection: GitHub Rulesets

TermQ uses **GitHub Rulesets** for intelligent, path-based branch protection on `main`. Different file types have different requirements.

### The 5 Rulesets

#### 1. Code Protection (Strict)
**Applies to:** `Sources/`, `Tests/`, `Package.swift`, `Makefile`, `.swiftlint.yml`, `.swift-format`, `.github/workflows/ci.yml`

**Requirements:**
- ✅ All 4 CI checks must pass (Build, Test, Lint, Format Check)
- ✅ Pull request required
- ✅ 1 human approval required
- ✅ Branch must be up-to-date with main

**Why:** Code changes require full validation and human oversight.

#### 2. Documentation Protection (Relaxed)
**Applies to:** `Docs/`, `README.md`

**Requirements:**
- ❌ No CI checks required
- ❌ No pull request required
- ✅ Direct pushes allowed (enables automation)

**Why:** Allows appcast workflow and other automation to update docs directly without creating PRs.

#### 2a. Claude Documentation Protection (Quality Controlled)
**Applies to:** `.claude/**/*.md`

**Requirements:**
- ✅ `claude-review` check must pass
- ❌ No pull request required
- ✅ Direct pushes allowed if check passes

**Why:** Ensures quality of project documentation while still allowing automation.

#### 3. Scripts & Workflows Protection (Moderate)
**Applies to:** `scripts/`, `.github/workflows/**` (except ci.yml)

**Requirements:**
- ✅ Script validation checks must pass
- ✅ Pull request required
- ✅ 1 human approval required

**Why:** Scripts and workflows need validation but different checks than code.

#### 4. Fallback Protection (Default)
**Applies to:** Everything else not covered above

**Requirements:**
- ✅ All 4 CI checks must pass
- ✅ Pull request required
- ✅ 1 human approval required

**Why:** Conservative default - anything not explicitly relaxed gets full protection.

### How Rulesets Work

**Multiple rulesets can apply** to a single PR:
- If you change `Sources/App.swift` + `README.md`, both Ruleset 1 (Code) and Ruleset 2 (Docs) apply
- **The strictest requirements win** - you'd need all 4 CI checks + 1 approval
- Path-based: Only rulesets matching your changed files apply

**Direct push vs Pull Request:**
- **Direct push** (automation): Rulesets evaluate status checks + push restrictions only
- **Pull request** (developers): Rulesets evaluate status checks + PR approval requirements

### Practical Examples

**Scenario 1: Code change**
```bash
# Changed: Sources/Terminal.swift
# Ruleset: Code Protection (Ruleset 1)
# Result: PR required, all 4 CI checks + 1 approval needed
```

**Scenario 2: Documentation change**
```bash
# Changed: Docs/appcast.xml
# Ruleset: Documentation Protection (Ruleset 2)
# Result: Direct push allowed, no requirements
```

**Scenario 3: Claude documentation change**
```bash
# Changed: .claude/commands/new-feature.md
# Ruleset: Claude Documentation Protection (Ruleset 2a)
# Result: Direct push allowed IF claude-review check passes
```

**Scenario 4: Mixed change**
```bash
# Changed: Sources/App.swift + README.md
# Rulesets: Code Protection (1) + Documentation (2)
# Result: Strictest wins - PR required, all CI + 1 approval
```

### Why Rulesets Instead of Branch Protection?

**Old system (legacy branch protection):**
- ❌ Applied blanket rules to entire branch
- ❌ Required all 4 CI checks even for doc-only changes
- ❌ Blocked automation (appcast workflow couldn't push)
- ❌ No intelligence about file types

**New system (GitHub Rulesets):**
- ✅ Path-based - different rules for different file types
- ✅ Allows automation where appropriate (docs)
- ✅ Maintains strict protection where critical (code)
- ✅ More granular and maintainable

## Merging

**Only merge when:**
- ✅ All CI checks pass (if required by matching rulesets)
- ✅ All reviews approved (if required by matching rulesets)
- ✅ **All review comments addressed and conversations resolved**
- ✅ Branch is up-to-date with base

```bash
# Final check before merge
gh pr checks  # Verify all checks pass
gh pr view --comments  # Verify no unresolved comments

# Merge using gh CLI (after human approval or user instruction)
gh pr merge --squash  # or --merge or --rebase based on project preference
```

**🚨 NEVER USE THE `--admin` FLAG 🚨**

**CATASTROPHIC FAILURE: Using `gh pr merge --admin` to bypass CI checks is strictly forbidden.**

- ❌ **NEVER** use `--admin` to bypass failed checks
- ❌ **NEVER** merge without waiting for CI to complete
- ❌ **NEVER** assume checks will pass - wait for confirmation

**Why this is catastrophic:**
- Bypasses code quality checks that prevent broken builds
- Can introduce bugs, security issues, or breaking changes to main
- Wastes everyone's time debugging issues that checks would have caught
- Violates the entire purpose of having CI/CD

**If checks are failing:**
1. **FIX THE ISSUE** - Don't bypass it
2. Push the fix and wait for CI again
3. Only merge when ALL checks pass legitimately

## Post-Merge

- [ ] Delete feature branch (local and remote)
- [ ] Create session notes in `.claude/sessions/` if significant work
- [ ] Close related tasks/issues
- [ ] Clean up worktree (if used) - see below

## Worktree Cleanup (if used)

**CRITICAL: Only remove worktrees after PR is merged!**

### Before Removing Worktree

**Check if branch is merged:**

```bash
# Verify the branch is actually merged
git branch -r --merged origin/main | grep <branch-name>

# If nothing shows, the branch is NOT merged - DO NOT PROCEED
```

**If branch is NOT merged:**

1. **Summarize the worktree work** to help decide:
   ```bash
   # Show commits in this worktree
   git log origin/main..<branch-name> --oneline

   # Show files changed
   git diff origin/main..<branch-name> --stat
   ```

2. **Present summary to user:** "This worktree has X commits with changes to Y files. The commits are: [list]. Do you REALLY want to remove this worktree and lose this unmerged work?"

3. **Wait for explicit confirmation** before proceeding

### Cleanup Steps (after merge confirmed)

**If branch IS merged (or user confirms deletion), proceed:**

```bash
# 1. Return to main repo
cd /Users/david/Storage/Workspace/eyelock/TermQ

# 2. Remove the worktree (removes directory + git metadata)
git worktree remove ../TermQ-worktrees/<branch-name>

# 3. Delete local branch
git branch -d <branch-name>

# 4. Delete remote branch (keeps remote in sync)
git push origin --delete <branch-name>
```

**Example:**
```bash
cd /Users/david/Storage/Workspace/eyelock/TermQ
git worktree remove ../TermQ-worktrees/feat-terminal-quick-actions
git branch -d feat-terminal-quick-actions
git push origin --delete feat-terminal-quick-actions
```

### Common Mistakes to Avoid

- ❌ Don't manually `rm -rf` the worktree directory (use `git worktree remove`)
- ❌ Don't remove worktree before PR is merged
- ❌ Don't use `git branch -D` (force delete) unless you know why
- ❌ Don't forget to clean up the remote branch
