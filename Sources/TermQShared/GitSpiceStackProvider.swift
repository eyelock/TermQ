import Foundation

/// `StackProvider` implementation backed by the `gs` (git-spice) CLI.
///
/// git-spice is GPL-3.0 — TermQ never bundles it. This type only detects a
/// user-installed binary and shells out to it (mirrors the `gh`/`ynh` detect-never-bundle
/// pattern). State is read exclusively via `gs log short --json`; `refs/spice/data` is
/// never parsed directly (documented as an unstable internal format).
///
/// All mutation commands pass `--no-prompt` with explicit flags — TermQ never depends on
/// interactive prompts from a subprocess.
public struct GitSpiceStackProvider: StackProvider, Sendable {
    public static let id = StackProviderID.gitSpice

    public var capabilities: StackCapabilities {
        [.restack, .submit, .sync, .trackExisting, .conflictResume, .branchInsertion]
    }

    public init() {}

    // MARK: - Probe

    public func probe() async -> StackProviderAvailability {
        guard let gsPath = Self.findGsBinary() else {
            return .missing
        }
        guard let result = try? await Self.run(gsPath, ["--version"], cwd: nil) else {
            return .unusable(reason: "Failed to run \(gsPath) --version")
        }
        guard result.exitCode == 0 else {
            return .unusable(reason: "\(gsPath) --version exited \(result.exitCode)")
        }
        guard let version = Self.identifyGitSpice(versionOutput: result.stdout) else {
            // The binary name `gs` collides with Ghostscript — a `gs` on $PATH that
            // doesn't self-identify as git-spice must not be treated as available.
            return .unusable(reason: "\(gsPath) is not git-spice")
        }
        return .ready(version: version)
    }

    // MARK: - Initialization

    /// Non-mutating initialization check. MUST NOT invoke `gs`: read commands like
    /// `gs log` attempt to AUTO-INITIALIZE an uninitialized repo (observed live —
    /// "Repository not initialized. Initializing." — only `--no-prompt` aborted it when
    /// the trunk wasn't guessable). Instead this checks whether git-spice's state ref
    /// exists via plain git. Existence only — the ref's contents are a documented
    /// unstable format and are never read or parsed.
    public func isInitialized(repo: String) async -> Bool {
        await Self.hasSpiceDataRef(repo: repo)
    }

    /// `git rev-parse --verify --quiet refs/spice/data` — exit 0 iff the ref exists.
    static func hasSpiceDataRef(repo: String) async -> Bool {
        do {
            _ = try await GitServiceShared.runGitCommand(
                repoPath: repo,
                args: ["rev-parse", "--verify", "--quiet", "refs/spice/data"]
            )
            return true
        } catch {
            return false
        }
    }

    public func initialize(repo: String, trunk: String) async throws {
        let gsPath = try Self.requireGsBinary()
        let result = try await Self.run(
            gsPath, ["repo", "init", "--trunk", trunk, "--no-prompt"], cwd: repo)
        try Self.throwIfFailed(result, command: "gs repo init")
    }

    // MARK: - Read

    public func graph(repo: String) async throws -> StackGraph {
        // Gate BEFORE any gs invocation: `gs log` auto-initializes uninitialized repos,
        // which is a mutation this read path must never trigger. The ref check also
        // means an uninitialized repo never spawns gs at all.
        guard await isInitialized(repo: repo) else {
            throw StackProviderError.notInitialized(repo: repo)
        }
        let gsPath = try Self.requireGsBinary()
        let result = try await Self.run(gsPath, Self.graphLogArguments(), cwd: repo)
        guard result.exitCode == 0 else {
            if Self.isNotInitializedError(result.stderr) {
                throw StackProviderError.notInitialized(repo: repo)
            }
            throw StackProviderError.commandFailed(
                command: "gs log short --json", exitCode: result.exitCode, output: result.stderr)
        }
        return StackGraph(branches: Self.parseLogShortNDJSON(result.stdout))
    }

    // MARK: - Mutations (command construction validated now; not wired into UI until Phase 2)

    public func createBranch(name: String, target: String?, in worktree: String) async throws {
        try await createBranch(name: name, target: target, position: .onTop, in: worktree)
    }

    /// `position` gates on `.branchInsertion`: `.below`/`.above` act on whatever is
    /// currently checked out in `worktree` — the caller must check that branch out
    /// first (guarded). `.onTop` is the original "create on top of an explicit target"
    /// behavior.
    public func createBranch(
        name: String, target: String?, position: StackBranchPosition, in worktree: String
    ) async throws {
        let gsPath = try Self.requireGsBinary()
        var args = ["branch", "create", name, "--no-prompt"]
        switch position {
        case .onTop:
            if let target { args += ["--target", target] }
        case .below:
            args.append("--below")
        case .above:
            args.append("--insert")
        }
        let result = try await Self.run(gsPath, args, cwd: worktree)
        try Self.throwIfFailed(result, command: "gs branch create")
    }

    public func trackBranch(_ name: String, base: String, in worktree: String) async throws {
        let gsPath = try Self.requireGsBinary()
        let result = try await Self.run(
            gsPath, ["branch", "track", name, "-b", base, "--no-prompt"], cwd: worktree)
        try Self.throwIfFailed(result, command: "gs branch track")
    }

    public func switchBranch(to name: String, in worktree: String) async throws {
        let gsPath = try Self.requireGsBinary()
        let result = try await Self.run(
            gsPath, ["branch", "checkout", name, "--no-prompt"], cwd: worktree)
        try Self.throwIfFailed(result, command: "gs branch checkout")
    }

    public func restack(scope: StackScope, in worktree: String) async throws {
        let gsPath = try Self.requireGsBinary()
        let args = Self.restackArguments(for: scope)
        let result = try await Self.run(gsPath, args, cwd: worktree)
        try Self.throwIfFailed(result, command: args.joined(separator: " "))
    }

    public func submit(scope: StackScope, options: StackSubmitOptions, in worktree: String) async throws {
        let gsPath = try Self.requireGsBinary()
        let args = Self.submitArguments(for: scope, options: options)
        let result = try await Self.run(gsPath, args, cwd: worktree)
        try Self.throwIfFailed(result, command: args.joined(separator: " "))
    }

    public func sync(repo: String) async throws {
        let gsPath = try Self.requireGsBinary()
        let result = try await Self.run(gsPath, ["repo", "sync", "--no-prompt"], cwd: repo)
        try Self.throwIfFailed(result, command: "gs repo sync")
    }

    public func continueOperation(in worktree: String) async throws {
        let gsPath = try Self.requireGsBinary()
        // --no-edit keeps gs from opening an editor for the continued commit message.
        let result = try await Self.run(
            gsPath, ["rebase", "continue", "--no-edit", "--no-prompt"], cwd: worktree)
        try Self.throwIfFailed(result, command: "gs rebase continue")
    }

    public func abortOperation(in worktree: String) async throws {
        let gsPath = try Self.requireGsBinary()
        let result = try await Self.run(gsPath, ["rebase", "abort"], cwd: worktree)
        try Self.throwIfFailed(result, command: "gs rebase abort")
    }

    public func pausedOperation(repo: String) async -> StackPausedOperation? {
        // Never invoke gs on an uninitialized repo — `gs log` would auto-initialize it.
        guard await isInitialized(repo: repo) else { return nil }
        guard let gsPath = Self.findGsBinary() else { return nil }
        // `gs log short --json` fails while a rebase is paused; the conflicted-file list
        // comes from plain git, which stays queryable throughout.
        guard
            let logResult = try? await Self.run(
                gsPath, ["log", "short", "--json", "--no-prompt"], cwd: repo),
            logResult.exitCode != 0,
            Self.isRebaseInProgressError(logResult.stderr)
        else { return nil }
        let files = await Self.conflictedFiles(repo: repo)
        return StackPausedOperation(kind: .restack, conflictedFiles: files)
    }

    // MARK: - Pure helpers (unit-testable without a live `gs` binary)

    /// Extract a version string from `gs --version` output if it identifies itself as
    /// git-spice. Ghostscript's `-v`/`--version` output never contains "spice", so a
    /// binary named `gs` that doesn't mention it is treated as the wrong tool.
    static func identifyGitSpice(versionOutput: String) -> String? {
        let lower = versionOutput.lowercased()
        // Ghostscript's `-v`/`--version` output either names itself explicitly
        // ("GPL Ghostscript 10.03.1") or, in terse form, prints a bare version number
        // with no identifying text at all. git-spice always prefixes its version with
        // "gs version" (or mentions "git-spice"/"spice" outright) — require one of those
        // positive signals rather than just the absence of "ghostscript".
        if lower.contains("ghostscript") { return nil }
        guard lower.contains("gs version") || lower.contains("git-spice") || lower.contains("spice") else {
            return nil
        }
        // Typical output: "gs version 0.31.0" or "git-spice (gs) 0.31.0". Grab the first
        // token that looks like a semantic version.
        for token in versionOutput.split(whereSeparator: { $0.isWhitespace }) {
            let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "v()"))
            if trimmed.first?.isNumber == true, trimmed.contains(".") {
                return trimmed
            }
        }
        return "unknown"
    }

    /// Detect git-spice's "not initialized" error text so `isInitialized`/`graph` can
    /// distinguish "no stack here" from a real failure.
    static func isNotInitializedError(_ stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("has not been initialized") || lower.contains("repo init")
    }

    static func isRebaseInProgressError(_ stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("rebase") && (lower.contains("progress") || lower.contains("conflict"))
    }

    /// Decode `gs log short --json` NDJSON (one JSON object per tracked branch) into
    /// neutral `StackBranch` values. Decoding is lenient: unparseable lines are skipped
    /// rather than failing the whole graph, since the schema isn't a stable public
    /// contract (per git-spice docs) and a future field addition shouldn't break TermQ.
    static func parseLogShortNDJSON(_ output: String) -> [StackBranch] {
        let decoder = JSONDecoder()
        var branches: [StackBranch] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let dto = try? decoder.decode(GsLogBranchDTO.self, from: data) else { continue }
            branches.append(dto.toStackBranch())
        }
        return branches
    }

    /// Arguments for the graph fetch. `--all` is load-bearing: without it, `gs log`
    /// only reports the stack related to the CWD's current branch — run from the main
    /// worktree that silently shrinks a multi-stack repo to (at most) one stack
    /// (verified live: 4 branches without --all vs 44 with it). -S (--cr-status)
    /// includes change-request id/url/status; --no-prompt is belt-and-braces so any
    /// unexpected prompt aborts instead of hanging.
    static func graphLogArguments() -> [String] {
        ["log", "short", "--all", "--json", "-S", "--no-prompt"]
    }

    // Restack/submit commands target a non-current branch via the `--branch=NAME` flag
    // (they take no positional branch argument, per the git-spice CLI reference).

    static func restackArguments(for scope: StackScope) -> [String] {
        switch scope {
        case .branch(let name):
            return ["branch", "restack", "--branch=\(name)", "--no-prompt"]
        case .upstack(let name):
            var args = ["upstack", "restack"]
            if let name { args.append("--branch=\(name)") }
            args.append("--no-prompt")
            return args
        case .stack:
            return ["stack", "restack", "--no-prompt"]
        }
    }

    static func submitArguments(for scope: StackScope, options: StackSubmitOptions) -> [String] {
        var args: [String]
        switch scope {
        case .branch(let name):
            args = ["branch", "submit", "--branch=\(name)"]
        case .upstack(let name):
            args = ["upstack", "submit"]
            if let name { args.append("--branch=\(name)") }
        case .stack:
            args = ["stack", "submit"]
        }
        args += ["--fill", "--no-prompt"]
        if options.draft { args.append("--draft") }
        if options.updateOnly { args.append("--update-only") }
        return args
    }

    // MARK: - Binary discovery

    /// Public so the Settings > Tools card can display the detected binary path —
    /// path display is inherently git-spice-specific, like the gh card's path row.
    public static func findGsBinary() -> String? {
        let home = NSHomeDirectory()
        // Homebrew installs the binary as `git-spice` only (no `gs` symlink, to avoid
        // colliding with Ghostscript), so search that name first; a bare `gs` is only
        // trusted after the identity check in `identifyGitSpice`.
        let directories = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
        ]
        let candidates = ["git-spice", "gs"].flatMap { name in
            directories.map { "\($0)/\(name)" }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func requireGsBinary() throws -> String {
        guard let path = findGsBinary() else { throw StackProviderError.binaryMissing }
        return path
    }

    private static func throwIfFailed(_ result: ProcessResult, command: String) throws {
        guard result.exitCode == 0 else {
            throw StackProviderError.commandFailed(
                command: command, exitCode: result.exitCode, output: result.stderr)
        }
    }

    private static func conflictedFiles(repo: String) async -> [String] {
        guard let gitPath = GitServiceShared.findGitPath() else { return [] }
        guard
            let result = try? await run(gitPath, ["diff", "--name-only", "--diff-filter=U"], cwd: repo)
        else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Process execution

    /// Minimal Sendable process result. Not shared with `CommandRunner` (TermQ target) —
    /// this type must stay usable from MCPServerLib and the CLI, which don't depend on
    /// the app target.
    struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    static func run(_ executable: String, _ arguments: [String], cwd: String?) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                process.waitUntilExit()

                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(
                    returning: ProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: outData, encoding: .utf8) ?? "",
                        stderr: String(data: errData, encoding: .utf8) ?? ""
                    ))
            }
        }
    }
}

// MARK: - NDJSON DTOs

/// One line of `gs log short --json` output. All fields optional except `name` — the
/// schema is not a stable public contract, so decoding degrades gracefully rather than
/// failing the whole graph when a field is missing or renamed.
private struct GsLogBranchDTO: Decodable {
    let name: String
    let current: Bool?
    let worktree: String?
    let down: GsDownDTO?
    let ups: [GsUpDTO]?
    let change: GsChangeDTO?
    let push: GsPushDTO?

    func toStackBranch() -> StackBranch {
        StackBranch(
            name: name,
            isCurrent: current ?? false,
            checkedOutElsewhere: worktree,
            parent: down?.name,
            children: (ups ?? []).map(\.name),
            needsRestack: down?.needsRestack ?? false,
            changeRequest: change?.toChangeRequest(),
            push: push?.toPushState()
        )
    }
}

private struct GsDownDTO: Decodable {
    let name: String
    let needsRestack: Bool?
}

private struct GsUpDTO: Decodable {
    let name: String
}

/// `id` is emitted as a number by git-spice's GitHub integration (older builds) or as a
/// pre-formatted string like "#678" (observed live). It's treated as provider-opaque
/// above this boundary, so it's normalized here to a bare identifier — no "#" — and the
/// UI decides how to display it (badges prepend a single "#").
private struct GsChangeDTO: Decodable {
    let id: String?
    let url: String?
    let status: String?
    let comments: Int?

    enum CodingKeys: String, CodingKey {
        case id, url, status, comments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else if let rawId = try? c.decode(String.self, forKey: .id) {
            id = rawId.hasPrefix("#") ? String(rawId.dropFirst()) : rawId
        } else {
            id = nil
        }
        url = try? c.decode(String.self, forKey: .url)
        status = try? c.decode(String.self, forKey: .status)
        comments = try? c.decode(Int.self, forKey: .comments)
    }

    func toChangeRequest() -> StackChangeRequest? {
        guard let id else { return nil }
        let resolvedStatus: StackChangeRequest.Status
        switch status?.lowercased() {
        case "open": resolvedStatus = .open
        case "closed": resolvedStatus = .closed
        case "merged": resolvedStatus = .merged
        default: resolvedStatus = .unknown
        }
        return StackChangeRequest(id: id, url: url, status: resolvedStatus, commentCount: comments)
    }
}

private struct GsPushDTO: Decodable {
    let ahead: Int?
    let behind: Int?
    let needsPush: Bool?

    func toPushState() -> StackPushState {
        StackPushState(ahead: ahead ?? 0, behind: behind ?? 0, needsPush: needsPush ?? false)
    }
}
