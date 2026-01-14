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

## PRE-PUSH / PRE-PR REQUIREMENTS (MANDATORY)

**NEVER push code or create a PR without running these checks locally first:**

1. `swift build` - Must complete with zero errors
2. `swift-format format -r -i Sources/` - Format all code
3. `swiftlint lint` - Must have zero errors (warnings acceptable but minimize)
4. `swift test` - All tests must pass

This prevents wasting CI resources and reduces environmental impact. Run these checks BEFORE:
- Any `git push`
- Creating or updating a PR
- Requesting code review

If SwiftLint crashes locally (SourceKit issues), at minimum verify the build succeeds and check line counts on modified files against SwiftLint rules (e.g., type_body_length max 500 lines).

**If local checks pass but CI fails**: This is a BUG. Investigate the discrepancy - local and CI environments should produce identical results. File an issue to track and fix the root cause.

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
