# Claude - TermQs 

## Communication Preferences

When working with complex technical topics (architecture, schema design, multi-step planning):
- Take a guided, conversational approach
- Present context and explain the problem first
- Ask clarifying questions ONE AT A TIME
- Wait for my response before moving to the next question
- Don't dump large analysis documents all at once
- Frame it as a discussion, not a report

## Feedback Sessions

When I say "let me give you feedback" or similar phrases indicating I want to provide iterative input:
- Wait for ALL my feedback before making any code changes
- I will explicitly say "done", "finished", "that's all", or similar when I'm ready for you to act
- Acknowledge each point briefly but don't implement anything mid-session
- At the end, summarize what you understood before proceeding

## Planning

- ALWAYS put your plans in .claude/plans 
- ALWAYS put your session handovers in .claude/sessions 

## RESPONSIBLE CI/CD USAGE

**Every CI run consumes energy. Be responsible.**

Before pushing ANY code:
1. Run `make check` locally - this runs the same checks as CI
2. Fix ALL errors before pushing
3. Never push "to see if CI catches something" - run checks locally first

This project uses path filtering - CI only runs when code-relevant files change. Documentation-only changes won't trigger CI.

## PRE-PUSH / PRE-PR REQUIREMENTS (MANDATORY)

**NEVER push code or create a PR without running these checks locally first:**

```bash
make build         # Must complete with zero errors
make format        # Format all code
make lint          # Must have zero errors (warnings acceptable but minimize)
make test          # All tests must pass
```

Or run all checks at once:
```bash
make check         # Runs build, lint, format-check, and test
```

**Note:** The Makefile automatically handles:
- DEVELOPER_DIR for Xcode toolchain (fixes "no such module 'XCTest'" errors)
- CI detection for GitHub-specific SwiftLint output
- Tool installation (SwiftLint, swift-format) if missing

**If local checks pass but CI fails**: This is a BUG. Local and CI environments use identical make targets. Investigate the discrepancy and file an issue.

## COMMAND REFERENCE

Detailed procedures and guidelines are documented in the `.claude/commands/` directory:

- **[commands/release.md](commands/release.md)** - Standard release procedure from main branch
- **[commands/release-beta.md](commands/release-beta.md)** - Beta release procedure with Sparkle integration
- **[commands/release-hotfix.md](commands/release-hotfix.md)** - Hotfix release procedure for critical patches
- **[commands/localization.md](commands/localization.md)** - Localization management and string handling
- **[commands/code-style.md](commands/code-style.md)** - Code style, patterns, and Swift 6 concurrency guidelines

## CODE HYGIENE

Run this workflow at the end of any significant development work:

* Use ACME if it is available
* Clean the software, including dependencies
* Install dependencies, check for any new or large warnings in the logs
* Build the project, zero error tolerance and strive for zero warning tolerance
* Format the code, add any changes as needed
* Lint the code, zero error tolerance and strive for zero warning tolerance
* Validate localization strings: `./scripts/localization/validate-strings.sh`
  * Ensure all 40 language files have matching keys
  * Run this before any release
* Specific technologies
  * Typescript
    * Always check the Typescript for errors regularly, it's a lot of wasted time trying to fix a massive batch of them
* Run the unit tests with coverage, look for failures and address low coverage if needed
* If project has integration tests, run them and ensure zero errors
