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

## RELEASE PROCESS

Releases are automated via GitHub Actions when a version tag is pushed.

1. Ensure all changes are committed and pushed to main
2. Run `make release` - interactive prompt for major/minor/patch
3. Or use specific targets: `make release-patch`, `make release-minor`, `make release-major`
4. The release workflow will:
   - Verify CI passed for the commit
   - Build the release app bundle
   - Create DMG and zip artifacts
   - Publish to GitHub Releases with checksums

## LOCALIZATION REQUIREMENTS (MANDATORY)

**NEVER use hardcoded user-facing strings in SwiftUI views or UI code.**

All user-visible text MUST use the centralized `Strings` enum:

```swift
// ❌ WRONG - hardcoded string
Text("New Terminal")
Button("Cancel") { ... }
.help("Close window")

// ✅ CORRECT - localized string
Text(Strings.Editor.titleNew)
Button(Strings.Editor.cancel) { ... }
.help(Strings.Common.close)
```

**Before any PR involving UI changes:**
1. Search for hardcoded strings: `grep -r "Text(\"" Sources/TermQ/Views/`
2. Verify all new strings are added to `Strings.swift`
3. Run `./scripts/localization/validate-strings.sh` to ensure all 40 language files are in sync

**Key files:**
- `Sources/TermQ/Strings.swift` - Centralized string enum using `localizedBundle`
- `Sources/TermQ/Resources/*.lproj/Localizable.strings` - Translation files (40 languages)

**Adding new strings:**
1. Add the key to `Strings.swift` with appropriate category
2. Add the English string to `Sources/TermQ/Resources/en.lproj/Localizable.strings`
3. Run the localization script to propagate to all language files

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
