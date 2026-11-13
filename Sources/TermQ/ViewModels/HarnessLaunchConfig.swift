import Foundation
import TermQCore

/// Configuration for launching a harness, passed from the launch sheet to the launcher.
struct HarnessLaunchConfig {
    let harnessID: String
    /// Explicit vendor override. Empty means "use harness default".
    let vendorID: String
    /// The harness's declared default vendor (for tagging).
    let defaultVendor: String
    let focus: String?
    /// Explicit profile override. Mutually exclusive with `focus` (YNH rejects both).
    /// Empty / nil means use the harness default profile.
    let profile: String?
    let workingDirectory: String
    let prompt: String?
    /// Per-invocation context injected after harness instructions via `--instructions`.
    /// Vendor-neutral: YNH translates to `--append-system-prompt` (Claude),
    /// `-c developer_instructions=` (Codex), or file append (Cursor).
    let instructions: String?
    let backend: TerminalBackend
    /// Branch name of the worktree this harness was launched from, if any.
    let branch: String?
    /// When true, passes `--interactive` to `ynh run` so the session stays open
    /// after the LLM responds to the initial prompt.
    let interactive: Bool
    /// Optional override for the terminal card title. Falls back to branch ?? harnessID when nil.
    let cardTitle: String?
    /// Additional tags for the created card, such as a Wheelhouse seat's
    /// `wheelhouse` and `seat` tags.
    var extraTags: [(key: String, value: String)] = []
    /// Whether this launch should continue the vendor's most recent session in
    /// the working directory. Declared with a default so existing memberwise
    /// call sites keep compiling.
    var resumeSession: Bool = false

    // Note: `--resume` is deliberately *not* emitted here. The init command is
    // persisted on the card and replayed on every open, so baking the flag in
    // would mean rewriting a stored (possibly hand-edited) command string every
    // time the card's resume setting changed. It is applied at send time
    // instead — see ResumeFlagInjector and TerminalSessionManager. This
    // launch's `resumeSession` choice travels as the card's one-shot
    // `resumeOverrideForNextLaunch`, not in the command string.

    /// Build the `ynh run` command string.
    /// Pass `sessionName` to bind the session to a specific tmux session name.
    func command(sessionName: String? = nil) -> String {
        var parts = ["ynh", "run", harnessID]
        if !vendorID.isEmpty {
            parts.append(contentsOf: ["-v", vendorID])
        }
        if let focus, !focus.isEmpty {
            parts.append(contentsOf: ["--focus", focus])
        } else if let profile, !profile.isEmpty {
            parts.append(contentsOf: ["--profile", profile])
        }
        if let instructions, !instructions.isEmpty {
            parts.append(contentsOf: ["--instructions", shellQuote(instructions)])
        }
        if interactive {
            parts.append("--interactive")
        }
        if let sessionName {
            parts.append(contentsOf: ["--session-name", sessionName])
        }
        if let prompt, !prompt.isEmpty {
            parts.append("--")
            parts.append(shellQuote(prompt))
        }
        return parts.joined(separator: " ")
    }

    private func shellQuote(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Tags to apply to the created Card (excluding runtime-derived tags added in launchHarness).
    var tags: [(key: String, value: String)] {
        let vendorTag = vendorID.isEmpty ? defaultVendor : vendorID
        var result: [(key: String, value: String)] = [
            ("source", "harness"),
            ("harness", harnessID),
        ]
        if !vendorTag.isEmpty {
            result.append(("vendor", vendorTag))
        }
        if let focus, !focus.isEmpty {
            result.append(("focus", focus))
        }
        if let branch, !branch.isEmpty {
            result.append(("branch", branch))
        }
        result.append(contentsOf: extraTags)
        return result
    }
}
