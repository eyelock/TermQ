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

    public func initialize(repo: String, trunk: String) async throws {
        throw StackProviderError.unsupported(operation: "enabling GitHub stacking (not yet wired)")
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

    // MARK: - Mutations (Phase 3)

    public func createBranch(name: String, target: String?, in worktree: String) async throws {
        throw StackProviderError.unsupported(operation: "creating a branch (not yet wired)")
    }

    public func trackBranch(_ name: String, base: String, in worktree: String) async throws {
        throw StackProviderError.unsupported(operation: "tracking an existing branch")
    }

    public func switchBranch(to name: String, in worktree: String) async throws {
        throw StackProviderError.unsupported(operation: "switching branches (not yet wired)")
    }

    public func restack(scope: StackScope, in worktree: String) async throws {
        throw StackProviderError.unsupported(operation: "restacking (not yet wired)")
    }

    public func submit(scope: StackScope, options: StackSubmitOptions, in worktree: String) async throws {
        throw StackProviderError.unsupported(operation: "submitting (not yet wired)")
    }

    public func sync(repo: String) async throws {
        throw StackProviderError.unsupported(operation: "syncing (not yet wired)")
    }

    public func continueOperation(in worktree: String) async throws {
        throw StackProviderError.unsupported(operation: "continuing a rebase (not yet wired)")
    }

    public func abortOperation(in worktree: String) async throws {
        throw StackProviderError.unsupported(operation: "aborting a rebase (not yet wired)")
    }

    public func destroyStack(in worktree: String) async throws {
        // Never silently substitute `unstack` here: it does not delete branches, so a
        // caller expecting "Destroy Stack" would get something with a totally different
        // blast radius. `.destroyStack` is not advertised for exactly this reason.
        throw StackProviderError.unsupported(operation: "deleting every branch in a stack")
    }

    public func untrackStack(in worktree: String) async throws {
        throw StackProviderError.unsupported(operation: "untracking a stack (not yet wired)")
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
                        isQueued: false
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

    /// Drop non-main worktrees the caller does not know about, so `checkedOutElsewhere`
    /// can only ever name a worktree the sidebar can actually navigate to. The main
    /// worktree is always kept — it supplies `isCurrent` and is never a jump target.
    /// An empty `knownPaths` means the caller has no opinion; keep everything.
    static func restrict(
        _ checkouts: [WorktreeCheckout], toKnownPaths knownPaths: [String]
    ) -> [WorktreeCheckout] {
        guard !knownPaths.isEmpty else { return checkouts }
        let known = Set(knownPaths.map { ($0 as NSString).standardizingPath })
        return checkouts.filter {
            $0.isMain || known.contains(($0.path as NSString).standardizingPath)
        }
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
