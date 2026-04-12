---
name: logging-rules
description: TermQ logging privacy rules. Load when writing or reviewing any code that logs data. Terminal output is user data — treat it as sensitive regardless of context.
---

# Logging Privacy Rules

## The Core Constraint

**Terminal output is user data. It can contain passwords, API keys, tokens, and secrets.**

TermQ is a terminal emulator. Every byte flowing through a pane could be sensitive. Treat it accordingly — across the entire app, not just the terminal rendering layer.

## Two Log Destinations

| Destination | When active | May contain terminal content? |
|---|---|---|
| `os.Logger` (Apple Unified Logging) | Always | **NO** |
| `/tmp/termq-debug.log` | `TERMQ_DEBUG=1` only | Yes — explicit developer opt-in |

`os.Logger` writes to Apple Unified Logging, which is:
- Readable by anyone who can run `log stream` on the machine
- Potentially included in system diagnostics and crash reports
- Persistent across app restarts until the OS rotates logs

A password typed into a terminal that lands in Unified Logging is a security incident.

## What May Be Logged Unconditionally (os.Logger)

Metadata only — nothing derived from terminal content:

- Session/pane identifiers (UUIDs, tmux IDs like `%0`)
- Layout geometry (column/row counts)
- Connection lifecycle events (connect, disconnect, session name)
- Focus and UI state transitions
- Error conditions and stack context (no content in the message)

## What Must NEVER Go to os.Logger

- Terminal output bytes or pane content
- Shell commands typed by the user
- Any string that contains or is derived from terminal I/O

## The `io` Category Rule

`TermQLogger.io` exists for terminal byte-stream debugging. It **must always** be gated behind `fileLoggingEnabled`:

```swift
// CORRECT — gated, only active when TERMQ_DEBUG=1
if TermQLogger.fileLoggingEnabled {
    TermQLogger.io.debug("output pane=\(paneId) len=\(data.count) «\(preview)»")
}

// WRONG — reaches os.Logger unconditionally for all users
TermQLogger.io.debug("output pane=\(paneId) len=\(data.count) «\(preview)»")
```

`fileLoggingEnabled` is only `true` when `TERMQ_DEBUG=1` is set.

## Decision Rule for Every Log Point

Before calling any `TermQLogger.*` method, ask:

> "Does the string I'm logging contain or derive from anything the user typed or any terminal output?"

**Yes** → gate it behind `TermQLogger.fileLoggingEnabled`
**No** → log freely at the appropriate level
