# Commit and Pull Request

**Run this after [implementation-checks.md](implementation-checks.md) passes.**

## Branch Naming Conventions

Use conventional naming:

```
feat/<short-description>      # New features
fix/<short-description>        # Bug fixes
refactor/<short-description>   # Code refactoring
docs/<short-description>       # Documentation only
ci/<short-description>         # CI/CD changes
test/<short-description>       # Test additions/changes
```

Examples:
- `feat/terminal-quick-actions`
- `fix/terminal-selection-focus`
- `ci/persistent-claude-permissions`

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

- [ ] Branch is pushed to origin
- [ ] All commits follow message format
- [ ] Branch is up-to-date with main (if needed)

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
- [ ] Respond to review comments
- [ ] Update PR based on feedback
- [ ] Ensure all conversations resolved before merge

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

## Merging

**Only merge when:**
- ✅ All CI checks pass
- ✅ All reviews approved
- ✅ **All review comments addressed and conversations resolved**
- ✅ Branch is up-to-date with base

```bash
# Final check before merge
gh pr checks  # Verify all checks pass
gh pr view --comments  # Verify no unresolved comments

# Merge using gh CLI
gh pr merge --squash  # or --merge or --rebase based on project preference
```

## Post-Merge

- [ ] Delete feature branch (local and remote)
- [ ] Create session notes in `.claude/sessions/` if significant work
- [ ] Close related tasks/issues
