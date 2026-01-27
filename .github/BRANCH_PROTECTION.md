# Branch Protection Configuration

## Main Branch Required Checks

The following CI checks must pass before merging to `main`:

- **Build**: Verify code compiles successfully
- **Test**: Run all unit tests
- **Lint**: SwiftLint code quality checks
- **Format Check**: swift-format code style verification

All checks are configured to run via GitHub Actions on every pull request.

## Claude Code Review

The `claude-review` workflow runs automatically on PRs and posts review comments for:
- Hardcoded UI strings that need localization
- Missing translations in 40+ language files
- Code quality issues and potential bugs
- Architecture violations

**Note**: Currently this check is **informational only** - it posts comments but doesn't block merges. To make it blocking, the workflow needs to be updated to fail when issues are found.

See `.github/workflows/claude-code-review.yml` for the review workflow.

## Configuration

Branch protection is configured via GitHub API and applies to the `main` branch.

See `.github/workflows/main.yml` for CI workflow definitions.
