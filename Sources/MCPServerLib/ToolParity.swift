import Foundation

/// Single source of truth for the CLI ⇄ MCP parity policy described in audit §7.
///
/// Every MCP tool name appearing in `availableTools` must be classified here as either
/// `mandatoryCLI` (a matching `termqcli` subcommand must exist) or `omittedCLI` (a
/// `termqcli` equivalent is deliberately not shipped, with a stated reason).
///
/// Three consumers:
/// 1. A test in `Tests/MCPServerLibTests/` walks `availableTools` and asserts each
///    name appears in exactly one of the two lists. Adding a new tool without
///    classifying it fails CI.
/// 2. The same test asserts each `mandatoryCLI` entry has a real `termqcli`
///    subcommand registered (looks up the CLI's command list).
/// 3. The docs generator emits a "CLI Omissions" appendix in `Docs/Help/reference/mcp.md`
///    directly from `omittedCLI` — readers see the policy and rationale together,
///    no hand-maintained second copy.
///
/// Adding a tool means editing the tool definition *and* this registry in lockstep;
/// the test enforces the second edit.
public enum ToolParity {
    /// Tools that MUST have a matching `termqcli` subcommand. Reads, basic card writes,
    /// column CRUD, whoami, simple resource enumerations.
    public static let mandatoryCLI: [String] = [
        // Card reads
        "pending",
        "context",
        "list",
        "find",
        "open",
        "get",
        // Card writes
        "create",
        "set",
        "move",
        "delete",
        "restore",
        // Column CRUD — shell pipelines for board admin
        "create_column",
        "rename_column",
        "delete_column",
        // Identity
        "whoami",
    ]

    /// Tools deliberately not exposed on `termqcli`. Reason is required so the policy is
    /// legible — the docs generator surfaces these to readers.
    public static let omittedCLI: [(name: String, reason: String)] = [
        (
            "record_handshake",
            "MCP-only semantics — proof an LLM consumed a card's context doesn't translate to a shell prompt."
        ),
        (
            "harness_launch",
            "Requires elicitation/user confirmation; no CLI equivalent. Security gate — "
                + "launching a harness from a pipe bypasses the confirmation surface."
        ),
        (
            "create_worktree",
            "`git worktree add` already exists as a first-class CLI; re-wrapping in termqcli "
                + "is wrapper-on-wrapper. Revisit if a concrete CLI need appears."
        ),
        (
            "remove_worktree",
            "Same reasoning as create_worktree — defer to `git worktree remove`."
        ),
    ]

    /// All names known to the parity registry.
    public static var allKnownNames: Set<String> {
        Set(mandatoryCLI + omittedCLI.map { $0.name })
    }
}
