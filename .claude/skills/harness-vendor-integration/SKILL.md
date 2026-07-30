---
name: harness-vendor-integration
description: How TermQ integrates LLM CLI harnesses (Claude Code, Cursor, Copilot CLI, Codex, etc.). Load when adding, auditing, or debugging support for a new LLM vendor/CLI tool.
---

# Harness Vendor Integration

## The core architectural fact

**TermQ does not implement harnesses.** Harnesses are managed entirely by **YNH**, a separate first-party CLI tool (see [[project-ynh-ownership]] in memory). TermQ is a *consumer* of whatever YNH reports — it renders vendor lists, harness manifests, and hook/skill/MCP compositions generically, without ever hardcoding a vendor's name, binary, or behavior.

The proof is in `Sources/TermQShared/Vendor.swift`:

```swift
/// A YNH vendor — decoded from `ynh vendors --format json`.
///
/// No hardcoded vendor IDs anywhere in TermQ. UI asks `VendorService` for
/// the list; selections hold opaque `vendorID` strings.
```

`VendorService` (`Sources/TermQ/Services/VendorService.swift`) runs `ynh vendors --format json`, decodes it into `[Vendor]`, and every consuming view (`HarnessLaunchSheet`, `HarnessDetailView`, `RunWithFocusSheet`) switches on data, never on vendor identity.

**Consequence:** adding a new LLM CLI (e.g. GitHub Copilot CLI, a new Codex variant, a future vendor) is almost entirely YNH-side work — a new `internal/vendor/<name>.go` adapter in the YNH repo (pattern: `claude.go` is the most complete reference implementation, `cursor.go` is the newest/most minimal). That adapter is responsible for:
- CLI binary name and invocation shape (interactive vs. one-shot flags)
- Config directory convention and custom-instructions file discovery
- MCP server registration format for that vendor
- Hook format translation
- Whether the vendor supports an initial prompt pre-loaded into an interactive session (`supports_initial_prompt`)

None of that belongs in TermQ. If you find yourself about to hardcode a vendor name, CLI flag, or config path inside `Sources/TermQ/**`, stop — that almost certainly belongs in the YNH vendor adapter instead.

## What TermQ-side work actually looks like

Once YNH exposes a vendor via `ynh vendors --format json`, TermQ's real harness system needs **zero code changes** — it already renders whatever comes back. Before assuming otherwise, verify:

```bash
grep -rn "vendorID ==" Sources/TermQ --include="*.swift"
grep -rln "\bVendor\b" Sources/TermQ --include="*.swift"
```

If a PR is adding vendor-specific branching to any file in that list, that's a smell — the architecture is supposed to stay vendor-agnostic. Push the logic back into YNH.

The only legitimate TermQ-side touchpoints when a new vendor appears:

1. **`Sources/TermQ/Models/LLMVendor.swift`** — a legacy, hardcoded enum that predates the YNH vendor system. It feeds *only* the Card Editor's "init command" convenience field (`CardEditorViewModel.selectedLLMVendor`) — not the real harness launch path. If the new vendor should appear there too, add a case with the correct command template (check the vendor's actual non-interactive CLI invocation — don't guess, verify against current docs since CLI syntax for these tools changes fast). Update `Tests/TermQTests/LLMVendorTests.swift` to match.
2. **`Sources/TermQ/Services/EditorRegistry.swift`** — only relevant if the vendor also ships a standalone GUI editor app (like Cursor does). Most CLI-only harnesses (Copilot CLI, Aider) have no entry here and shouldn't get one.
3. Nothing else. If you think you need a fourth touchpoint, re-check the grep above first — you may be about to duplicate logic YNH already owns.

## Auditing for staleness

`LLMVendor.swift` is the one place hardcoded CLI invocations can silently rot, because it isn't exercised by the live YNH vendor pipeline and nothing forces it to stay in sync with a vendor's actual current CLI syntax. When auditing or extending harness support, check every case in that enum against the vendor's current docs — a stale template (e.g. an old `gh copilot suggest` invocation superseded by a plain `copilot` binary) can sit unnoticed for a long time.

## Process for evaluating a new LLM CLI as a harness vendor

1. Research the vendor's CLI: invocation modes (interactive/one-shot), auth model, custom-instructions file support (does it read `CLAUDE.md`/`AGENTS.md`?), MCP client support and config format, hooks, skills/subagents, permission/approval flags, structured output support.
2. Determine what's YNH work vs. TermQ work using the table above — assume YNH unless proven otherwise.
3. If TermQ-side work exists, scope it via `LLMVendor.swift`/`EditorRegistry.swift` only, per the touchpoints above.
4. Write/update tests for any TermQ-side change.
5. Do **not** create new abstractions in TermQ to special-case the vendor — if the existing vendor-agnostic path can't express something the new vendor needs, that's a signal to extend the `Vendor` schema (YNH + `TermQShared/Vendor.swift` decoding) generically, not to add vendor-specific branches in UI code.
