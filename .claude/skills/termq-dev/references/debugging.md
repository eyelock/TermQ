# Debugging

## TermQLogger

TermQ uses a structured logging system in `Sources/TermQ/Services/TermQLogger.swift`.

**Never use `print()` or `NSLog()`.** Always use `TermQLogger`.

### Usage

```swift
TermQLogger.tmux.debug("sizeChanged pane=\(id) \(cols)x\(rows)")
TermQLogger.session.info("connect session=\(name) existing=\(wasExisting)")
TermQLogger.focus.warning("makeFirstResponder called on nil window")
TermQLogger.session.error("connect() threw: \(error)")
```

### Categories

| Category | Covers |
|----------|--------|
| `tmux` | Control mode protocol, resize, layout changes, pane output, commands |
| `pane` | Pane lifecycle: creation, layout, border updates, cleanup |
| `session` | Terminal session lifecycle: connect, disconnect, backend switching |
| `focus` | Keyboard focus: first responder, tab switching, click-to-focus |
| `io` | Input/output routing: key events, raw pane output bytes |
| `ui` | SwiftUI/AppKit view lifecycle: appear, disappear, layout passes |

### Levels

| Level | When to use |
|-------|-------------|
| `debug` | High-frequency events: sizeChanged, output bytes, layout passes |
| `info` | Noteworthy state changes: session connected, pane added, focus granted |
| `warning` | Unexpected but recoverable: missing pane, skipped resize |
| `error` | Failures that affect functionality: connect threw, process died |

## Streaming Logs

Every log message goes to Apple Unified Logging (always on):

```bash
# All TermQ messages
log stream --predicate 'subsystem == "net.eyelock.termq"'

# Filter by category
log stream --predicate 'subsystem == "net.eyelock.termq" AND category == "tmux"'

# Show past session (last 10 minutes)
log show --predicate 'subsystem == "net.eyelock.termq"' --last 10m
```

Or browse in **Console.app** — search by subsystem `net.eyelock.termq`.

## File Logging (TERMQ_DEBUG=1)

Set `TERMQ_DEBUG=1` to also write to `/tmp/termq-debug.log`. The file is truncated at each launch.

```bash
TERMQ_DEBUG=1 open TermQDebug.app
tail -f /tmp/termq-debug.log

# Filter to a category
tail -f /tmp/termq-debug.log | grep '\[tmux\]'
tail -f /tmp/termq-debug.log | grep '\[focus\]'
```

The `io` category logs raw output bytes — verbose. Only enable when debugging input/output routing and filter aggressively.

## Privacy Boundary

Terminal output is user data. See `logging-rules` skill for the full privacy rules before adding any log point near terminal I/O.
