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

## RELEASE PROCESS

When creating a release:

1. **Update VERSION file** - The `VERSION` file in the repo root MUST be updated to match the release version (e.g., `0.4.5`)
2. **Create git tag** - Tag format is `v{VERSION}` (e.g., `v0.4.5`)
3. **Push tag** - `git push origin v{VERSION}`
4. **GitHub Actions** - The `release.yml` workflow will:
   - Verify CI passed for the commit
   - Build the release binary
   - Create app bundle with CLI tools
   - Sign and package as DMG and ZIP
   - Create GitHub Release with assets

**IMPORTANT**: The VERSION file is the source of truth for the app version displayed in the UI. The git tag triggers the release workflow but the VERSION file must also be updated.

## CODE HYGIENE

Want to do this workflow at the end of any significant development work, especially in the middle of 

* Use ACME if it is available
* Clean the software, including dependencies
* Install dependencies, check for any new or large warnings in the logs
* Build the project, zero error tolerance and strive for zero warning tolerance
* Format the code, add any changes as needed
* Lint the code, zero error tolerance and strive for zero warning tolerance
* Specific technologies
  * Typescript
    * Always check the Typescript for errors regularly, it's a lot of wasted time trying to fix a massive batch of them
* Run the unit tests with coverage, look for failures and address low coverage if needed
* If project has integration tests, run them and ensure zero errors
