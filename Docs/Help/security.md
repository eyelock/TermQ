# Security

TermQ is designed with security in mind while giving you full control over your terminal workflow. This page explains the protections TermQ provides and the settings you can configure.

## Safe Paste Protection

When you paste text into a terminal, TermQ analyzes it for potentially dangerous content and warns you before execution:

- **Multi-line pastes** - Could contain hidden commands after innocuous-looking first lines
- **Sudo commands** - Elevated privilege operations require extra care
- **Destructive commands** - Commands like `rm -rf` that could cause data loss

This feature is enabled by default on all terminals and can be adjusted per-terminal in the terminal editor under Terminal > Security.

## Clipboard Access Control

Terminal applications can request clipboard access using OSC 52 escape sequences. This allows programs running in your terminal to copy text to your system clipboard - useful for tools like `tmux`, `vim`, and remote `pbcopy` alternatives.

By default, OSC 52 clipboard access is **enabled**. You can disable it in:

**Settings > Data & Security > Allow OSC 52 Clipboard Access**

When disabled, terminal programs cannot write to your clipboard via escape sequences.

## External Modification Protection

TermQ supports a URL scheme (`termq://`) that allows external tools and scripts to interact with your terminals. While this enables powerful automation, it also means external processes could modify your terminal configuration.

TermQ protects sensitive fields by requiring confirmation when external applications attempt to modify:

- **LLM Prompt** - Your persistent AI context
- **LLM Next Action** - Queued commands for autorun

When an external process tries to modify these fields, TermQ shows a confirmation dialog before applying the change. This prevents malicious scripts from injecting commands into your AI workflows.

This protection is enabled by default. Configure in:

**Settings > Data & Security > Confirm External LLM Modifications**

## Autorun Permission Model

TermQ's autorun feature lets LLM assistants queue commands that execute when you open a terminal. This powerful feature uses a **two-level permission model** to ensure safety:

| Level | Setting | Default |
|-------|---------|---------|
| Global | Settings > Tools > Enable Terminal Autorun | Off |
| Per-Terminal | Terminal Editor > Security > Allow Autorun | Off |

**Both** must be enabled for autorun to work on any terminal. This ensures:

- You explicitly opt-in to automatic command execution
- Individual terminals can remain protected even when global autorun is enabled
- Sensitive terminals (production, databases) stay secure

## Input Validation

All user input and data from external sources is validated:

- **String lengths** - General fields limited to 1,000 characters, LLM context fields to 50,000 characters, paths to 4,096 characters
- **Path validation** - Path traversal sequences (`../`) are blocked to prevent directory escape attacks
- **UUID validation** - Identifiers are validated for proper format

## Data Storage Security

See [Configuration & Data](configuration.md) for data file locations.

### Concurrent Access Protection

TermQ uses **file coordination** (NSFileCoordinator) to ensure safe concurrent access when multiple processes (app, CLI, MCP server) read or write simultaneously. This prevents data corruption from race conditions.

### Sensitive Data Considerations

The board.json file stores terminal metadata including LLM prompts and queued actions as plain JSON. If you store sensitive information in terminal descriptions or LLM prompts, consider enabling FileVault (full-disk encryption) at the macOS level.

Secrets added via the [Environment Variables](environment-variables.md) feature are stored securely in your macOS Keychain, not in board.json.

## App Entitlements

TermQ requires certain system permissions to function as a terminal application:

| Permission | Why It's Needed |
|------------|-----------------|
| Filesystem access | Terminals need to access your files |
| Network access | Tools like git, npm, and curl require network |
| Unsigned executable memory | Terminal emulation requires this for PTY handling |
| Disabled app sandbox | Shell processes cannot run inside a sandbox |

These are standard requirements for terminal emulators. TermQ runs with your user privileges, same as Terminal.app or iTerm2.

## MCP Server Security

The MCP server (`termqmcp`) is designed for **local use only**:

- **Stdio mode** (default) - Communicates via standard input/output with Claude Code
- **HTTP mode** - Not implemented; the server exits if attempted
- **No network exposure** - The server cannot be accessed over the network

See [MCP Server](mcp-server.md) for more details.

## Shell Command Safety

TermQ properly escapes all shell arguments to prevent command injection:

- Working directories
- Session names
- Shell paths
- Environment variable values

## Best Practices

1. **Keep Safe Paste enabled** for terminals where you paste from untrusted sources
2. **Disable autorun** for sensitive terminals (production, databases)
3. **Review external modifications** before approving them
4. **Use secrets** instead of hardcoding credentials in environment variables
5. **Enable FileVault** if your LLM prompts contain sensitive project context

## Settings Reference

| Setting | Location | Default | Purpose |
|---------|----------|---------|---------|
| Safe Paste | Terminal Editor > Security | On | Warn about dangerous pastes |
| Allow Autorun | Terminal Editor > Security | Off | Per-terminal autorun permission |
| Enable Terminal Autorun | Settings > Tools | Off | Global autorun permission |
| Allow OSC 52 Clipboard | Settings > Data & Security | On | Clipboard access from terminals |
| Confirm External Modifications | Settings > Data & Security | On | Protect LLM fields from external changes |

## Related

- [MCP Server](mcp-server.md) - LLM integration security
- [Environment Variables & Secrets](environment-variables.md) - Secure credential management
- [CLI Tool](cli-tool.md) - Command-line interface
