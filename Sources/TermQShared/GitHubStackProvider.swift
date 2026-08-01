import Foundation

/// `StackProvider` implementation backed by GitHub's native stacked PRs — the
/// `github/gh-stack` extension for the `gh` CLI.
///
/// TermQ never bundles it; this type detects a user-installed extension and shells out,
/// mirroring the `gh`/`ynh`/git-spice detect-never-bundle pattern.
///
/// ## Why the graph is read from disk rather than from the CLI
///
/// `gh stack view --json` looks like the obvious read, but it is not a pure one: it calls
/// `syncStackPRs`, which hits the GitHub API (a stack lookup plus a per-branch PR
/// lookup), and then writes the tracking file back. Fanning that out across every
/// worktree on each sidebar refresh would mean a burst of API calls — and writes to
/// `.git` — every time the worktree list refreshes.
///
/// So the graph comes from gh-stack's tracking file, which is a pure local read, sees
/// every stack (not just the one the current branch happens to be in), and costs nothing.
/// `refreshChangeRequests` is the opt-in path that spends the network call to freshen PR
/// state, and is only invoked on explicit user action.
///
/// Reading another tool's state file is a deliberate exception to the rule that kept
/// TermQ out of `refs/spice/data`. It is defensible here because the file carries an
/// explicit `schemaVersion`, gh-stack itself refuses to run against a version it does not
/// understand, and this type does the same rather than guessing.
///
/// ## Why state is per worktree
///
/// gh-stack resolves its tracking file against `git rev-parse --git-dir`, which inside a
/// linked worktree is `.git/worktrees/<name>/` rather than the common directory. Each
/// worktree therefore carries an independent stack, and the source has no worktree
/// awareness at all. This type reassembles a repo-wide view by reading every worktree's
/// file and unioning the result.
public struct GitHubStackProvider: StackProvider, Sendable {
    public static let id = StackProviderID.gitHub

    /// Highest `schemaVersion` of the tracking file this type knows how to read.
    /// A newer file means gh-stack was upgraded past us — refuse rather than
    /// misinterpret, which is what gh-stack does in the same situation.
    static let supportedSchemaVersion = 1

    /// Deliberately narrower than git-spice's set:
    ///
    /// - no `.branchInsertion` — gh-stack can only restructure through the interactive
    ///   `modify` TUI, which TermQ must never spawn
    /// - no `.trackExisting` — `init <branches...>` adopts a whole set, and `link` also
    ///   creates PRs; neither is "track this one branch onto this base"
    /// - no `.destroyStack` — `unstack` leaves every branch in place, so it is
    ///   `.untrackStack`, not the destructive operation of the same shape
    /// - no `.scopedRestack` — `rebase` always pivots on the checked-out branch; its
    ///   positional argument picks a stack, not a starting point
    /// - no `.scopedSubmit` — `submit` has no scoping flag and always covers the whole stack
    /// - `.syncPushes` because `gh stack sync` force-pushes every branch and mutates the
    ///   stack object on GitHub, unlike git-spice's local-only `repo sync`
    public var capabilities: StackCapabilities {
        [
            .restack,
            .submit,
            .sync,
            .syncPushes,
            .conflictResume,
            .untrackStack,
            .mergeStack,
            .remoteDiscovery,
            .linkExisting,
        ]
    }

    public init() {}

    // MARK: - Probe

    public func probe() async -> StackProviderAvailability {
        guard let ghPath = Self.findGhBinary() else {
            return .missing
        }
        guard let versionResult = try? await Self.run(ghPath, ["stack", "--version"], cwd: nil) else {
            return .unusable(reason: "Failed to run \(ghPath) stack --version")
        }
        guard versionResult.exitCode == 0 else {
            // `gh` is present but the extension is not: gh prints an install hint and
            // exits non-zero. That is "not installed", not "broken".
            return .missing
        }
        guard let version = Self.identifyGhStack(versionOutput: versionResult.stdout) else {
            return .unusable(reason: "\(ghPath) stack did not report a gh-stack version")
        }
        // Unlike git-spice, every remote operation here goes through gh's credentials.
        // An unauthenticated gh yields a tool that detects fine and then fails on the
        // first submit, so surface it up front as a reason the user can act on.
        guard let authResult = try? await Self.run(ghPath, ["auth", "status"], cwd: nil),
            authResult.exitCode == 0
        else {
            return .unusable(reason: "gh is not authenticated — run `gh auth login`")
        }
        return .ready(version: version)
    }

    // MARK: - Initialization

    /// Non-mutating: pure filesystem. A repo counts as initialized when the main
    /// worktree's git dir, or ANY linked worktree's git dir, holds a tracking file —
    /// stacking may have been set up only inside a worktree, and missing that would make
    /// the registry hand the repo to the wrong provider.
    public func isInitialized(repo: String) async -> Bool {
        guard let commonDir = await Self.gitCommonDirectory(repo: repo) else { return false }
        return !Self.trackingFilePaths(commonDirectory: commonDir).isEmpty
    }

    /// `gh stack init --base <trunk> <branch>`.
    ///
    /// Unlike `gs repo init` — which only records a trunk and leaves the repo empty of
    /// stacks — gh-stack has no repo-level "enabled" state at all: the tracking file comes
    /// into existence when the first stack does. So enabling stacking here means creating
    /// that first stack, and a stack needs a branch.
    ///
    /// The branch is the one already checked out, adopted as the stack's first entry
    /// (`init` adopts existing branches automatically). Standing ON the trunk there is
    /// nothing to adopt, and inventing a branch name on the user's behalf would leave them
    /// with a branch they never asked for — so that case reports what to do instead.
    ///
    /// Passing the branch explicitly is also what keeps this non-interactive: with no
    /// positional argument `init` demands a TTY and exits 5.
    public func initialize(repo: String, trunk: String) async throws {
        let ghPath = try Self.requireGhBinary()
        guard let current = await Self.currentBranch(in: repo), !current.isEmpty else {
            throw StackProviderError.preconditionFailed(
                "GitHub stacking needs a branch to start the stack from, and \(repo) has a "
                    + "detached HEAD. Check out a branch and try again.")
        }
        guard current != trunk else {
            throw StackProviderError.preconditionFailed(
                "GitHub stacking starts from the checked-out branch, but \(repo) is on the "
                    + "trunk (\(trunk)). Create or check out a branch to stack, then try again.")
        }
        let result = try await Self.run(
            ghPath, ["stack", "init", "--base", trunk, current], cwd: repo)
        try Self.throwIfFailed(result, command: "gh stack init")
    }

    // MARK: - Read

    public func graph(repo: String) async throws -> StackGraph {
        try await graph(repo: repo, worktrees: [])
    }

    /// Branch resolution comes from `git worktree list --porcelain`, which is
    /// authoritative and also yields each worktree's checked-out branch — something the
    /// caller's path list does not carry.
    ///
    /// `worktrees` still matters, though: it scopes which paths may appear as
    /// `checkedOutElsewhere`. That field is a jump target in the sidebar, so pointing it
    /// at a worktree git knows about but TermQ does not would render a control that
    /// navigates nowhere. An empty list means "no restriction".
    ///
    /// One subprocess plus a file read per worktree — no network, no writes.
    public func graph(repo: String, worktrees: [String]) async throws -> StackGraph {
        guard let commonDir = await Self.gitCommonDirectory(repo: repo) else {
            throw StackProviderError.notInitialized(repo: repo)
        }
        let checkouts = Self.restrict(
            await Self.worktreeCheckouts(repo: repo), toKnownPaths: worktrees)
        let files = Self.trackingFilePaths(commonDirectory: commonDir)
        guard !files.isEmpty else {
            throw StackProviderError.notInitialized(repo: repo)
        }

        var stacks: [GhStackDTO] = []
        for path in files {
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            let file = try Self.decodeTrackingFile(data)
            stacks.append(contentsOf: file.stacks)
        }

        let currentBranch = checkouts.first { $0.isMain }?.branch
        var branches = Self.branches(
            from: Self.dedupe(stacks), currentBranch: currentBranch, checkouts: checkouts)
        branches = await Self.applyNeedsRestack(branches, repo: repo)
        return StackGraph(branches: branches)
    }

    // MARK: - Mutations

    /// `gh stack add <name>` — creates `name` on top of the stack containing whatever is
    /// checked out in `worktree`.
    ///
    /// gh-stack can only extend a stack at its top (mid-stack insertion is the interactive
    /// `modify` TUI, which is why `.branchInsertion` is not advertised). `target` is
    /// therefore only honoured when it names the branch already checked out; anything else
    /// would have to check that branch out first, which is the caller's decision to make,
    /// not a side effect to bury in "create a branch".
    ///
    /// No `-m`/`-A`/`-u`: passing an explicit name with no staging flags is the one `add`
    /// path that neither prompts for a name nor opens an editor.
    public func createBranch(name: String, target: String?, in worktree: String) async throws {
        let ghPath = try Self.requireGhBinary()
        if let target {
            let current = await Self.currentBranch(in: worktree)
            guard target == current else {
                throw StackProviderError.preconditionFailed(
                    "GitHub stacking adds branches on top of the checked-out branch. "
                        + "Check out \(target) first, then add the branch.")
            }
        }
        let result = try await Self.run(ghPath, ["stack", "add", name], cwd: worktree)
        try Self.throwIfFailed(result, command: "gh stack add")
    }

    public func trackBranch(_ name: String, base: String, in worktree: String) async throws {
        // `init <branches...>` adopts a whole set and `link` also creates PRs; neither is
        // "track this one branch onto this base". `.trackExisting` is not advertised.
        throw StackProviderError.unsupported(operation: "tracking an existing branch")
    }

    /// Plain `git checkout`. gh-stack's own `switch` is a full-screen picker with no
    /// non-interactive form, and `next`/`prev` only move one step relative to HEAD.
    ///
    /// Checking out with git directly is not a shortcut around gh-stack: the tracking file
    /// records the stack's branch list, never which one is checked out, so nothing in it
    /// needs updating. `graph` derives the current branch from git for the same reason.
    public func switchBranch(to name: String, in worktree: String) async throws {
        guard let gitPath = GitServiceShared.findGitPath() else {
            throw StackProviderError.binaryMissing
        }
        let result = try await Self.run(gitPath, ["checkout", name], cwd: worktree)
        try Self.throwIfFailed(result, command: "git checkout")
    }

    public func restack(scope: StackScope, in worktree: String) async throws {
        let ghPath = try Self.requireGhBinary()
        let args = try await Self.restackArguments(
            for: scope, currentBranch: Self.currentBranch(in: worktree))
        let result = try await Self.run(ghPath, args, cwd: worktree)
        try Self.throwIfFailed(result, command: args.joined(separator: " "))
    }

    public func submit(scope: StackScope, options: StackSubmitOptions, in worktree: String) async throws {
        let ghPath = try Self.requireGhBinary()
        let args = try Self.submitArguments(for: scope, options: options)
        let result = try await Self.run(ghPath, args, cwd: worktree)
        try Self.throwIfFailed(result, command: args.joined(separator: " "))
    }

    /// Repo-level entry point. gh-stack's sync is scoped to the stack that is checked out,
    /// so "the repo" means the main worktree; `sync(repo:worktree:)` is the form callers
    /// should reach for.
    public func sync(repo: String) async throws {
        try await sync(repo: repo, worktree: repo)
    }

    /// `gh stack sync --prune`.
    ///
    /// `--prune` is not an extra: without it, sync PROMPTS to delete merged branches when
    /// it thinks it has a terminal. Passing it makes the answer explicit and matches
    /// `gs repo sync`, which deletes merged locals unconditionally.
    ///
    /// This also force-pushes every branch and updates the stack on GitHub — the reason
    /// this provider advertises `.syncPushes` and the UI confirms before calling it.
    public func sync(repo: String, worktree: String) async throws {
        let ghPath = try Self.requireGhBinary()
        let result = try await Self.run(ghPath, ["stack", "sync", "--prune"], cwd: worktree)
        try Self.throwIfFailed(result, command: "gh stack sync")
    }

    public func continueOperation(in worktree: String) async throws {
        let ghPath = try Self.requireGhBinary()
        let result = try await Self.run(ghPath, ["stack", "rebase", "--continue"], cwd: worktree)
        try Self.throwIfFailed(result, command: "gh stack rebase --continue")
    }

    public func abortOperation(in worktree: String) async throws {
        let ghPath = try Self.requireGhBinary()
        let result = try await Self.run(ghPath, ["stack", "rebase", "--abort"], cwd: worktree)
        try Self.throwIfFailed(result, command: "gh stack rebase --abort")
    }

    public func destroyStack(in worktree: String) async throws {
        // Never silently substitute `unstack` here: it does not delete branches, so a
        // caller expecting "Destroy Stack" would get something with a totally different
        // blast radius. `.destroyStack` is not advertised for exactly this reason.
        throw StackProviderError.unsupported(operation: "deleting every branch in a stack")
    }

    /// `gh stack unstack --local` — drops the stack from the tracking file and leaves
    /// every branch exactly where it is.
    ///
    /// `--local` is load-bearing, not a conservative default: without it, `unstack` calls
    /// the GitHub API to dissolve the stack object and unstack its pull requests. That is
    /// a remote mutation, and this operation is offered as the non-destructive counterpart
    /// to Destroy Stack.
    public func untrackStack(in worktree: String) async throws {
        let ghPath = try Self.requireGhBinary()
        let result = try await Self.run(ghPath, ["stack", "unstack", "--local"], cwd: worktree)
        try Self.throwIfFailed(result, command: "gh stack unstack --local")
    }

    /// `gh stack merge <stack-number> --yes`.
    ///
    /// The stack number is always passed. Without an argument `merge` targets "the active
    /// stack", resolved from the working directory — an unacceptable way to decide which
    /// pull requests get merged.
    ///
    /// `--yes` skips gh-stack's own confirmation. That is not a bypass of review: TermQ
    /// has already shown the user every pull request with its review and check state, and
    /// without the flag the command would try to open a full-screen TUI. `--admin` is
    /// never passed, so branch protection still applies and an unmergeable stack fails.
    ///
    /// No method flag when `method` is nil: gh-stack then resolves the repository's own
    /// default and falls back to the first method the repo allows. Choosing here instead
    /// would risk naming a method the repository forbids.
    public func mergeStack(
        remoteStackID: String, method: StackMergeMethod?, in worktree: String
    ) async throws {
        let ghPath = try Self.requireGhBinary()
        let args = try Self.mergeArguments(remoteStackID: remoteStackID, method: method)
        let result = try await Self.run(ghPath, args, cwd: worktree)
        try Self.throwIfFailed(result, command: "gh stack merge")
    }

    /// `gh stack link <branch>...`, bottom of the stack first.
    ///
    /// Creates a pull request for any branch that lacks one — which is exactly why this is
    /// not `trackBranch`, and why the UI names it for what it does.
    ///
    /// No `--open`: linking adopts existing pull requests, and silently flipping someone's
    /// draft to ready-for-review is not part of "link these together".
    public func linkStack(branches: [String], base: String?, in worktree: String) async throws {
        let ghPath = try Self.requireGhBinary()
        guard branches.count >= 2 else {
            throw StackProviderError.preconditionFailed(
                "Linking a stack needs at least two branches; \(branches.count) selected.")
        }
        var args = ["stack", "link"]
        if let base { args += ["--base", base] }
        args += branches
        let result = try await Self.run(ghPath, args, cwd: worktree)
        try Self.throwIfFailed(result, command: "gh stack link")
    }

    /// `gh stack checkout <stack-number>`.
    ///
    /// The number is always passed: with no argument `checkout` opens an interactive
    /// picker of every local and remote stack, which TermQ must never spawn — the same
    /// hazard as `init` with no branch.
    public func checkoutStack(remoteStackID: String, in worktree: String) async throws {
        let ghPath = try Self.requireGhBinary()
        let number = try Self.stackNumber(from: remoteStackID)
        let result = try await Self.run(
            ghPath, ["stack", "checkout", String(number)], cwd: worktree)
        try Self.throwIfFailed(result, command: "gh stack checkout")
    }

    public func pausedOperation(repo: String) async -> StackPausedOperation? {
        guard let commonDir = await Self.gitCommonDirectory(repo: repo) else { return nil }
        // gh-stack parks interrupted rebases in a sibling of the tracking file. Presence
        // is the signal; the contents are an internal format this type does not read.
        let hasRebaseState = Self.gitDirectories(commonDirectory: commonDir).contains {
            FileManager.default.fileExists(atPath: ($0 as NSString).appendingPathComponent("gh-stack-rebase-state"))
        }
        guard hasRebaseState else { return nil }
        return StackPausedOperation(kind: .restack, conflictedFiles: await Self.conflictedFiles(repo: repo))
    }

    // MARK: - Pure helpers (unit-testable without a live `gh stack`)

    /// Extract a version from `gh stack --version`. gh-stack prints
    /// "gh stack version 1.2.3"; anything that does not name itself is not trusted.
    static func identifyGhStack(versionOutput: String) -> String? {
        let lower = versionOutput.lowercased()
        guard lower.contains("gh stack") || lower.contains("gh-stack") else { return nil }
        for token in versionOutput.split(whereSeparator: { $0.isWhitespace }) {
            let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "v()"))
            if trimmed.first?.isNumber == true, trimmed.contains(".") {
                return trimmed
            }
        }
        return "unknown"
    }

    /// Decode a tracking file, refusing a schema newer than we understand rather than
    /// silently misreading it — the same stance gh-stack takes.
    static func decodeTrackingFile(_ data: Data) throws -> GhStackFileDTO {
        let decoder = JSONDecoder()
        guard let file = try? decoder.decode(GhStackFileDTO.self, from: data) else {
            throw StackProviderError.decodingFailed("gh-stack tracking file is not readable JSON")
        }
        guard file.schemaVersion <= supportedSchemaVersion else {
            throw StackProviderError.decodingFailed(
                "gh-stack tracking file uses schema version \(file.schemaVersion); "
                    + "this version of TermQ supports up to \(supportedSchemaVersion)")
        }
        return file
    }

    /// Union stacks read from every worktree, dropping exact duplicates. Two worktrees
    /// can legitimately reference the same stack (same remote number, or an identical
    /// branch chain), and it must appear once in the sidebar.
    static func dedupe(_ stacks: [GhStackDTO]) -> [GhStackDTO] {
        var seen = Set<String>()
        var result: [GhStackDTO] = []
        for stack in stacks {
            // Prefer the remote identity when present; fall back to the shape of the
            // chain, which is what makes two local-only stacks the same stack.
            let key =
                stack.number.map { "number:\($0)" }
                ?? "chain:\(stack.trunk.branch)>\(stack.branches.map(\.branch).joined(separator: ">"))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(stack)
        }
        return result
    }

    /// Map gh-stack's per-stack branch LISTS onto the neutral parent/child graph.
    ///
    /// Parent comes from array ORDER, never from `BranchRef.base` — that field holds the
    /// parent's HEAD *SHA* at last sync, not a branch name, in both the tracking file and
    /// `gh stack view --json`. Index 0 is the bottom of the stack (closest to trunk).
    ///
    /// The trunk is a sibling field rather than a member of `branches`, but
    /// `StackGraph.isTrunk` / `rootBranch` / `stackRoots` all identify the trunk as "a
    /// tracked entry with no parent" (which is how git-spice reports it). So it is
    /// synthesized as a parentless entry here — without that, `isTrunk(trunk)` answers
    /// false and the Stacks inventory misbehaves.
    static func branches(
        from stacks: [GhStackDTO],
        currentBranch: String?,
        checkouts: [WorktreeCheckout]
    ) -> [StackBranch] {
        var result: [StackBranch] = []
        var trunkNames = Set<String>()

        for stack in stacks {
            let names = stack.branches.map(\.branch)
            for (index, branch) in stack.branches.enumerated() {
                let parent = index == 0 ? stack.trunk.branch : names[index - 1]
                let children = index + 1 < names.count ? [names[index + 1]] : []
                result.append(
                    StackBranch(
                        name: branch.branch,
                        isCurrent: branch.branch == currentBranch,
                        checkedOutElsewhere: checkouts.first {
                            !$0.isMain && $0.branch == branch.branch
                        }?.path,
                        parent: parent,
                        children: children,
                        needsRestack: false,  // filled in by applyNeedsRestack
                        changeRequest: branch.pullRequest?.toChangeRequest(),
                        push: nil,  // not recorded in the tracking file
                        // `Queued` is json:"-" — transient, populated from the API on
                        // each gh-stack run and never persisted. Always false from disk.
                        isQueued: false,
                        // Present only once the stack has been submitted; every branch of
                        // one stack reports the same value.
                        remoteStackID: stack.number.map(String.init)
                    ))
            }
            trunkNames.insert(stack.trunk.branch)
        }

        // Synthesize the trunk(s) last, and only when not already present as a stack
        // member, so a real branch is never shadowed by the synthetic entry.
        let existing = Set(result.map(\.name))
        for trunk in trunkNames.sorted() where !existing.contains(trunk) {
            result.append(
                StackBranch(
                    name: trunk,
                    isCurrent: trunk == currentBranch,
                    checkedOutElsewhere: checkouts.first { !$0.isMain && $0.branch == trunk }?.path,
                    parent: nil,
                    children: result.filter { $0.parent == trunk }.map(\.name),
                    needsRestack: false,
                    changeRequest: nil,
                    push: nil))
        }
        return result
    }

    /// Build `gh stack merge` arguments. Separated out so the flag set is testable
    /// without a live `gh` — particularly that `--admin` never appears.
    static func mergeArguments(
        remoteStackID: String, method: StackMergeMethod?
    ) throws -> [String] {
        let number = try stackNumber(from: remoteStackID)
        var args = ["stack", "merge", String(number), "--yes"]
        if let method { args += ["--merge-method", method.rawValue] }
        return args
    }

    /// gh-stack addresses stacks by an integer number. The neutral model carries the
    /// identifier opaquely, so this is where it comes back to a number — and where a
    /// value that never came from this provider is rejected rather than coerced.
    static func stackNumber(from remoteStackID: String) throws -> Int {
        guard let number = Int(remoteStackID), number > 0 else {
            throw StackProviderError.preconditionFailed(
                "This stack has no GitHub stack number yet — submit it first.")
        }
        return number
    }

    /// Map a neutral restack scope onto `gh stack rebase` flags.
    ///
    /// The pivot is always `HEAD`. `rebase`'s positional argument only selects WHICH STACK
    /// to load when a branch belongs to more than one — `--upstack`/`--downstack` are still
    /// measured from the checked-out branch. So a scope naming some other branch cannot be
    /// honoured, and is refused rather than silently rebasing a different range. This is
    /// what `.scopedRestack` gates, and why this provider does not advertise it.
    ///
    /// - `.stack` → `rebase` (fetches trunk and rebases the whole stack onto it)
    /// - `.upstack(from: nil)` → `rebase --upstack` (checked-out branch and everything above)
    /// - `.upstack(from: x)` → the same, but only when `x` IS the checked-out branch
    /// - `.branch(x)` → refused: gh-stack has no single-branch rebase. `--no-trunk` skips
    ///   the trunk, not the other branches, so it is not a substitute.
    static func restackArguments(for scope: StackScope, currentBranch: String?) throws -> [String] {
        switch scope {
        case .stack:
            return ["stack", "rebase"]
        case .upstack(let name):
            guard let name, name != currentBranch else {
                return ["stack", "rebase", "--upstack"]
            }
            throw StackProviderError.preconditionFailed(
                "GitHub stacking restacks from the checked-out branch. Check out \(name) "
                    + "first, then restack from there.")
        case .branch(let name):
            throw StackProviderError.unsupported(
                operation: "restacking the single branch \(name) — it rebases whole stacks")
        }
    }

    /// Map a neutral submit scope onto `gh stack submit` flags.
    ///
    /// `submit` takes no scope flag at all: it always pushes every unmerged branch in the
    /// stack and creates or updates each one's PR. A partial scope is therefore refused
    /// rather than quietly widened — `.scopedSubmit` gates that in the UI.
    ///
    /// `--auto` skips the PR-authoring TUI and uses generated titles and bodies. On that
    /// path new PRs are created as drafts, so `--open` is what marks them ready for
    /// review — which makes it the inverse of `options.draft`, not an extra.
    static func submitArguments(for scope: StackScope, options: StackSubmitOptions) throws -> [String] {
        switch scope {
        case .stack:
            break
        case .branch(let name):
            throw StackProviderError.unsupported(
                operation: "submitting only \(name) — it submits the whole stack")
        case .upstack(let name):
            throw StackProviderError.unsupported(
                operation: "submitting from \(name ?? "here") upward — it submits the whole stack")
        }
        guard !options.updateOnly else {
            // gh-stack always creates a PR for a branch that lacks one; there is no
            // "update what exists and skip the rest" mode to map onto.
            throw StackProviderError.unsupported(
                operation: "updating existing pull requests without creating new ones")
        }
        var args = ["stack", "submit", "--auto"]
        if !options.draft { args.append("--open") }
        return args
    }

    /// Map gh-stack's documented exit codes onto neutral errors.
    ///
    /// The extension assigns a distinct code per failure class, which is more reliable
    /// than matching on message text (git-spice offers no such thing, hence the string
    /// sniffing in that provider). Codes not listed here fall through to
    /// `.commandFailed`, which carries the code and stderr for display.
    static func mapExitCode(_ result: StackProcessResult, command: String) -> StackProviderError {
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        switch result.exitCode {
        case 2:  // not in a stack / stack not found
            return .preconditionFailed(
                detail.isEmpty
                    ? "\(command): the branch is not part of a GitHub stack." : detail)
        case 5:  // invalid arguments or flags — includes "can only add to the top"
            return .preconditionFailed(
                detail.isEmpty ? "\(command) rejected the request." : detail)
        case 6:  // multiple stacks or remotes, cannot auto-select
            return .preconditionFailed(
                detail.isEmpty
                    ? "\(command): more than one stack or remote matched, and TermQ cannot "
                        + "pick one for you." : detail)
        case 7:  // a rebase is already in progress
            return .preconditionFailed(
                detail.isEmpty
                    ? "A stack rebase is already in progress. Resolve or abort it first."
                    : detail)
        case 9:  // stacked PRs not enabled for this repository
            return .preconditionFailed(
                detail.isEmpty
                    ? "Stacked pull requests are not available for this repository." : detail)
        case 10:  // interrupted `modify` session needs recovery
            return .preconditionFailed(
                detail.isEmpty
                    ? "An interrupted `gh stack modify` session must be recovered in the "
                        + "terminal before TermQ can change this stack." : detail)
        default:
            // Notably exit 3 (rebase conflict): a conflict is NOT an error here. It is
            // reported through `pausedOperation`, which the service consults on any
            // mutation failure, and surfaces as the conflict banner rather than an alert.
            return .commandFailed(
                command: command, exitCode: result.exitCode, output: result.stderr)
        }
    }

    /// Every path that may hold a tracking file: the common dir (main worktree) plus each
    /// linked worktree's private git dir.
    static func gitDirectories(commonDirectory: String) -> [String] {
        var directories = [commonDirectory]
        let worktreesRoot = (commonDirectory as NSString).appendingPathComponent("worktrees")
        let entries =
            (try? FileManager.default.contentsOfDirectory(atPath: worktreesRoot)) ?? []
        for entry in entries.sorted() {
            directories.append((worktreesRoot as NSString).appendingPathComponent(entry))
        }
        return directories
    }

    static func trackingFilePaths(commonDirectory: String) -> [String] {
        gitDirectories(commonDirectory: commonDirectory)
            .map { ($0 as NSString).appendingPathComponent("gh-stack") }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// One worktree and the branch it currently has checked out.
    struct WorktreeCheckout: Sendable, Equatable {
        let path: String
        let branch: String?
        /// The main worktree — the one `repo` itself points at.
        let isMain: Bool
    }

    /// Drop non-main worktrees the caller does not know about, and re-spell the survivors
    /// using the caller's own paths, so `checkedOutElsewhere` can only ever name a
    /// worktree the sidebar can actually navigate to. The main worktree is always kept —
    /// it supplies `isCurrent` and is never a jump target. An empty `knownPaths` means the
    /// caller has no opinion; keep everything.
    ///
    /// The re-spelling is not cosmetic. `git worktree list` reports fully resolved paths,
    /// so a worktree under a symlinked root comes back as `/private/var/…` where TermQ
    /// recorded it as `/var/…`. Both name the same directory, but every consumer compares
    /// these paths as STRINGS: the switch guard would decide a branch is checked out
    /// somewhere else when it is checked out right here, and refuse the switch while
    /// naming the user's own worktree as the obstacle.
    static func restrict(
        _ checkouts: [WorktreeCheckout], toKnownPaths knownPaths: [String]
    ) -> [WorktreeCheckout] {
        guard !knownPaths.isEmpty else { return checkouts }
        // Two spellings per known path — as written and with symlinks resolved — both
        // pointing at the caller's own (tidied) spelling. Matching has to consider
        // resolved forms because git reports them; the RESULT has to use the caller's
        // because that is the vocabulary every consumer compares against.
        var canonical: [String: String] = [:]
        for path in knownPaths {
            canonical[canonicalPath(path)] = (path as NSString).standardizingPath
        }
        return checkouts.compactMap { checkout in
            if let display = canonical[canonicalPath(checkout.path)] {
                return WorktreeCheckout(
                    path: display, branch: checkout.branch, isMain: checkout.isMain)
            }
            return checkout.isMain ? checkout : nil
        }
    }

    /// A comparison-only form of `path`: tidied, symlinks resolved, and with macOS's
    /// `/private` prefix removed.
    ///
    /// Never shown to anyone — it exists purely so two spellings of the same directory
    /// compare equal. `resolvingSymlinksInPath` alone is not enough: it only rewrites
    /// paths that actually exist, so a worktree that has since been removed would stop
    /// matching the moment it was deleted. `/var` and `/tmp` are symlinks into
    /// `/private` on every macOS install, which is the aliasing that shows up here —
    /// git reports `/private/var/...` where TermQ recorded `/var/...`.
    static func canonicalPath(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: (path as NSString).standardizingPath)
            .resolvingSymlinksInPath().path
        guard resolved.hasPrefix("/private/") else { return resolved }
        return String(resolved.dropFirst("/private".count))
    }

    /// Parse `git worktree list --porcelain`. The first record is always the main
    /// worktree. Detached HEADs have no `branch` line and yield a nil branch.
    static func parseWorktreeList(_ output: String) -> [WorktreeCheckout] {
        var result: [WorktreeCheckout] = []
        var path: String?
        var branch: String?

        func flush() {
            guard let path else { return }
            result.append(WorktreeCheckout(path: path, branch: branch, isMain: result.isEmpty))
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("worktree ") {
                flush()
                path = String(line.dropFirst("worktree ".count))
                branch = nil
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            }
        }
        flush()
        return result
    }

    // MARK: - Git interrogation

    static func worktreeCheckouts(repo: String) async -> [WorktreeCheckout] {
        guard let gitPath = GitServiceShared.findGitPath(),
            let result = try? await run(gitPath, ["worktree", "list", "--porcelain"], cwd: repo),
            result.exitCode == 0
        else { return [] }
        return parseWorktreeList(result.stdout)
    }

    /// `--git-common-dir` (not `--git-dir`): from inside a linked worktree the latter
    /// points at that worktree's private directory, and we want the shared root so every
    /// worktree's tracking file can be enumerated from one place.
    static func gitCommonDirectory(repo: String) async -> String? {
        guard let gitPath = GitServiceShared.findGitPath(),
            let result = try? await run(
                gitPath, ["rev-parse", "--path-format=absolute", "--git-common-dir"], cwd: repo),
            result.exitCode == 0
        else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// `needsRestack` is not recorded in the tracking file; gh-stack recomputes it as
    /// "the parent is no longer an ancestor of this branch". Mirrored here with the same
    /// check, skipping merged branches exactly as gh-stack does.
    static func applyNeedsRestack(_ branches: [StackBranch], repo: String) async -> [StackBranch] {
        guard let gitPath = GitServiceShared.findGitPath() else { return branches }
        var result: [StackBranch] = []
        for branch in branches {
            guard let parent = branch.parent, branch.changeRequest?.status != .merged else {
                result.append(branch)
                continue
            }
            // Exit 1 means "not an ancestor" — a legitimate answer, not a failure, which
            // is why this uses raw exit codes rather than a throwing git helper.
            let outcome = try? await run(
                gitPath, ["merge-base", "--is-ancestor", parent, branch.name], cwd: repo)
            let needsRestack = outcome?.exitCode == 1
            result.append(
                StackBranch(
                    name: branch.name, isCurrent: branch.isCurrent,
                    checkedOutElsewhere: branch.checkedOutElsewhere, parent: branch.parent,
                    children: branch.children, needsRestack: needsRestack,
                    changeRequest: branch.changeRequest, push: branch.push,
                    isQueued: branch.isQueued))
        }
        return result
    }

    /// The branch checked out in `directory`, or nil on a detached HEAD (where
    /// `--abbrev-ref HEAD` prints "HEAD") or when git is unavailable.
    static func currentBranch(in directory: String) async -> String? {
        guard let gitPath = GitServiceShared.findGitPath(),
            let result = try? await run(
                gitPath, ["rev-parse", "--abbrev-ref", "HEAD"], cwd: directory),
            result.exitCode == 0
        else { return nil }
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return (branch.isEmpty || branch == "HEAD") ? nil : branch
    }

    static func conflictedFiles(repo: String) async -> [String] {
        guard let gitPath = GitServiceShared.findGitPath(),
            let result = try? await run(
                gitPath, ["diff", "--name-only", "--diff-filter=U"], cwd: repo)
        else { return [] }
        return result.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    // MARK: - Binary discovery

    /// Public so the Settings > Tools card can show the detected `gh` path, matching the
    /// git-spice card. Mirrors `GhCliProbe`'s search order.
    public static func findGhBinary() -> String? {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin/gh",
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Environment applied to every `gh stack` invocation.
    ///
    /// gh-stack has no global `--no-prompt`; it decides interactivity by sniffing for a
    /// TTY, and pipes its non-JSON output through a pager. Closing stdin (in
    /// `StackProcessRunner`) covers the prompt half; these cover the rest — a pager would
    /// otherwise hold the pipe open forever, and colour codes would corrupt parsing.
    static var commandEnvironment: [String: String] {
        [
            "GH_PAGER": "cat",
            "PAGER": "cat",
            "NO_COLOR": "1",
            "CLICOLOR": "0",
            // Detection can misfire without a terminal; pin it so gh-stack never probes
            // the (absent) terminal background.
            "GH_STACK_THEME": "dark",
        ]
    }

    static func run(
        _ executable: String, _ arguments: [String], cwd: String?
    ) async throws -> StackProcessResult {
        try await StackProcessRunner.run(executable, arguments, cwd: cwd, env: commandEnvironment)
    }

    private static func requireGhBinary() throws -> String {
        guard let path = findGhBinary() else { throw StackProviderError.binaryMissing }
        return path
    }

    private static func throwIfFailed(_ result: StackProcessResult, command: String) throws {
        guard result.exitCode == 0 else {
            throw mapExitCode(result, command: command)
        }
    }
}

// MARK: - Tracking file DTOs

/// `.git/**/gh-stack`, gh-stack's local tracking file. Field names mirror the Go structs
/// in `internal/stack/stack.go`. Everything except `schemaVersion` decodes leniently —
/// this is another tool's file, and a field appearing or moving must not blank the
/// sidebar.
struct GhStackFileDTO: Decodable {
    let schemaVersion: Int
    let stacks: [GhStackDTO]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, stacks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A file with no version predates versioning; treat it as v1 rather than failing.
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 1
        stacks = (try? container.decode([GhStackDTO].self, forKey: .stacks)) ?? []
    }
}

struct GhStackDTO: Decodable {
    let id: String?
    let number: Int?
    let trunk: GhBranchRefDTO
    let branches: [GhBranchRefDTO]

    enum CodingKeys: String, CodingKey {
        case id, number, trunk, branches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decode(String.self, forKey: .id)
        number = try? container.decode(Int.self, forKey: .number)
        trunk = try container.decode(GhBranchRefDTO.self, forKey: .trunk)
        branches = (try? container.decode([GhBranchRefDTO].self, forKey: .branches)) ?? []
    }
}

/// NOTE: `base` is the parent's HEAD **SHA** at last sync, not a branch name. It is
/// deliberately not decoded — reading it as a parent would produce a plausible-looking
/// but wrong graph.
struct GhBranchRefDTO: Decodable {
    let branch: String
    let pullRequest: GhPullRequestRefDTO?
}

struct GhPullRequestRefDTO: Decodable {
    let number: Int
    let url: String?
    let merged: Bool?

    func toChangeRequest() -> StackChangeRequest? {
        guard number != 0 else { return nil }
        return StackChangeRequest(
            id: String(number),
            url: url,
            // The file records only whether the PR merged. "Closed but not merged" is
            // indistinguishable from open here, so anything unmerged reads as open until
            // an explicit refresh fetches the real state.
            status: (merged ?? false) ? .merged : .open,
            commentCount: nil)
    }
}
