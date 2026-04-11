# Security

## Safe Paste

When you paste text into a terminal, TermQ scans it for content that could cause unintended harm and shows a warning before execution:

- **Multi-line pastes** — Could contain hidden commands after a seemingly safe first line
- **Sudo commands** — Elevated privilege operations
- **Destructive commands** — Commands like `rm -rf` that could cause data loss

Safe paste is enabled by default on all terminals. You can disable it per-terminal in the editor under **Terminal > Security > Safe Paste**.

## Clipboard access (OSC 52)

Terminal programs can write to your system clipboard using OSC 52 escape sequences — used by tools like tmux, vim, and remote `pbcopy` alternatives.

This is **enabled by default**. Disable it in **Settings > Data & Security > Allow OSC 52 Clipboard Access**.

## External modification protection

TermQ supports a URL scheme (`termq://`) that allows external tools to interact with your board. To prevent malicious scripts from injecting commands into your AI workflows, TermQ requires confirmation before any external process can modify `llmPrompt` or `llmNextAction`.

This protection is **enabled by default**. Configure in **Settings > Data & Security > Confirm External LLM Modifications**.

## Autorun permission model

Token injection substitutes `{{LLM_PROMPT}}` and `{{LLM_NEXT_ACTION}}` in the terminal's init command when it opens. It uses a two-level permission model — both must be enabled:

| Level | Setting | Default |
|---|---|---|
| Global | Settings > Data & Security > Enable LLM Prompt Auto-injection | Off |
| Per-Terminal | Terminal editor > Terminal tab > Security > Allow LLM Prompt Auto-injection | Off |

This means you can enable injection for your AI workflow terminals while keeping sensitive terminals (production, databases) permanently protected.

See [Tutorial 11: Autorun](tutorials/11-autorun.md) for the full model.

## Data storage

`board.json` stores all terminal metadata — names, descriptions, tags, LLM prompts, and queued actions — as plain JSON. If you store sensitive project context in LLM prompts, consider enabling FileVault for full-disk encryption at the macOS level.

**Secrets** (environment variables marked as secrets) are stored in your macOS Keychain with encryption, not in `board.json`. See [Tutorial 6](tutorials/06-terminal-context.md).

## Input validation

All input is validated at system boundaries:

| Field | Limit |
|---|---|
| General text fields | 1,000 characters |
| LLM context fields (`llmPrompt`, `llmNextAction`) | 50,000 characters |
| File paths | 4,096 characters |

Path traversal sequences (`../`) are blocked to prevent directory escape attacks. UUIDs are validated for correct format.

## App entitlements

TermQ requires certain permissions to function as a terminal emulator:

| Permission | Why |
|---|---|
| Filesystem access | Terminals need to read and write your files |
| Network access | Tools like git, npm, and curl require network |
| Unsigned executable memory | Required for PTY (pseudo-terminal) handling |
| Disabled app sandbox | Shell processes cannot run inside a sandbox |

These are standard requirements for any macOS terminal emulator. TermQ runs with your user privileges — the same as Terminal.app or iTerm2.

## Settings reference

| Setting | Location | Default |
|---|---|---|
| Safe Paste | Terminal Editor > Security | On |
| Allow LLM Prompt Auto-injection | Terminal editor > Terminal tab > Security | Off |
| Enable LLM Prompt Auto-injection | Settings > Data & Security | Off |
| Allow OSC 52 Clipboard | Settings > Data & Security | On |
| Confirm External Modifications | Settings > Data & Security | On |
