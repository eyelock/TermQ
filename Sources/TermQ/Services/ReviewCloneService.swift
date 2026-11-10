import Foundation
import TermQShared

/// Review checkouts for pull requests in repositories TermQ doesn't have.
///
/// Each such repository gets one hidden clone, made with `gh repo clone` the first
/// time it's needed, at `~/.termq/focus-repos/<host>/<owner>/<name>`. Its review
/// checkouts are ordinary review checkouts (detached worktrees in
/// `~/.termq/focus-worktrees`), so a harness opened in one starts with the PR's code.
/// The `<owner>/<name>` ending also makes the harness's PR slug come out right.
@MainActor
final class ReviewCloneService: ObservableObject {
    static let shared = ReviewCloneService()

    /// Review checkouts by `owner/name#number`, from the last `refresh`.
    @Published private(set) var checkouts: [String: GitWorktree] = [:]
    /// Pull requests with a checkout in progress, by `owner/name#number`. A refresh
    /// never removes one of these.
    @Published private(set) var busy: Set<String> = []
    private var inFlight: [String: Task<GitWorktree, Error>] = [:]
    /// When gh last said a PR was open, so a refresh doesn't ask every time.
    private var seenOpen: [String: Date] = [:]

    let host = "github.com"
    var cloneBase: URL
    var reviewBase: URL

    init(
        cloneBase: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            ".termq/focus-repos", isDirectory: true),
        reviewBase: URL = ReviewCheckouts.baseDirectory()
    ) {
        self.cloneBase = cloneBase
        self.reviewBase = reviewBase
    }

    /// `owner/name#number`, lowercased: GitHub names are case-insensitive, and a
    /// remote URL may not use the API's casing.
    static func key(repository: String, number: Int) -> String { "\(repository.lowercased())#\(number)" }

    /// The hidden clone's path for `owner/name`.
    func clonePath(for repository: String) -> String {
        cloneBase.appendingPathComponent(host).appendingPathComponent(repository).path
    }

    func checkout(for request: ReviewRequest) -> GitWorktree? {
        checkouts[Self.key(repository: request.repository, number: request.number)]
    }

    /// Make (or reuse) the review checkout for `request`. A second call for the same
    /// PR while one is running waits for it rather than starting another.
    func checkout(_ request: ReviewRequest, ghPath: String) async throws -> GitWorktree {
        let key = Self.key(repository: request.repository, number: request.number)
        if let running = inFlight[key] { return try await running.value }
        let task = Task { try await self.makeCheckout(request, key: key, ghPath: ghPath) }
        inFlight[key] = task
        busy.insert(key)
        defer {
            inFlight[key] = nil
            busy.remove(key)
        }
        return try await task.value
    }

    private func makeCheckout(_ request: ReviewRequest, key: String, ghPath: String) async throws -> GitWorktree {
        let clone = clonePath(for: request.repository)
        try await ensureClone(request.repository, at: clone, ghPath: ghPath)
        let head = try await Self.prHead(request, ghPath: ghPath, clone: clone)
        let repoKey = ([host] + request.repository.split(separator: "/").map(String.init)).joined(separator: "--")
        let path = reviewBase.appendingPathComponent(
            ReviewCheckouts.directoryName(repoKey: repoKey, headRefName: head.name, prNumber: request.number)
        ).path

        let listed = try await GitServiceShared.listWorktrees(repoPath: clone)
        if let existing = listed.first(where: { ReviewCheckouts.canonical($0.path) == ReviewCheckouts.canonical(path) })
        {
            // Bring a clean checkout up to the PR's head: it may be behind new pushes,
            // or half made if TermQ quit mid-checkout. One with changes is left alone.
            if existing.commitHash != head.oid, !(await Self.hasChanges(existing.path)) {
                try await Self.ghCheckout(request.number, at: existing.path, ghPath: ghPath)
            }
            let current = try await Self.listed(path, in: clone) ?? existing
            checkouts[key] = current
            return current
        }
        let base = reviewBase
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: path) else { return }
            guard !ReviewCheckouts.isLiveWorktree(at: path), ReviewCheckouts.isManaged(path: path, base: base) else {
                throw GitHubPRError.commandFailed("\(URL(fileURLWithPath: path).lastPathComponent) is in use")
            }
            try FileManager.default.removeItem(atPath: path)
        }.value
        _ = try? await GitServiceShared.runGitCommand(repoPath: clone, args: ["worktree", "prune"])
        _ = try await GitServiceShared.runGitCommand(repoPath: clone, args: ["worktree", "add", "--detach", path])
        do {
            try await Self.ghCheckout(request.number, at: path, ghPath: ghPath)
        } catch {
            _ = try? await GitServiceShared.runGitCommand(
                repoPath: clone, args: ["worktree", "remove", "--force", path])
            throw error
        }
        let worktree =
            try await Self.listed(path, in: clone)
            ?? GitWorktree(path: path, branch: nil, commitHash: head.oid, isMainWorktree: false, isLocked: false)
        checkouts[key] = worktree
        return worktree
    }

    private static func ghCheckout(_ number: Int, at path: String, ghPath: String) async throws {
        let result = try await CommandRunner.run(
            executable: ghPath, arguments: ["pr", "checkout", "\(number)", "--detach"], currentDirectory: path)
        guard result.didSucceed else {
            throw GitHubPRError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func listed(_ path: String, in clone: String) async throws -> GitWorktree? {
        try await GitServiceShared.listWorktrees(repoPath: clone).first {
            ReviewCheckouts.canonical($0.path) == ReviewCheckouts.canonical(path)
        }
    }

    /// Re-read every hidden clone's review checkouts, then remove the ones a refresh
    /// may remove on its own (`ReviewCheckouts.canAutoPrune`): PR closed, no changes,
    /// no commits of their own, nothing open in them. A PR still asking for review
    /// is open; any other PR's state is asked of gh.
    func refresh(openRequests: [ReviewRequest], ghPath: String?, cardDirectories: () -> [String]) async {
        let found = await Self.scan(cloneBase: cloneBase, host: host)
        var map: [String: GitWorktree] = [:]
        for (repository, worktrees) in found {
            for worktree in worktrees {
                guard
                    let number = ReviewCheckouts.prNumber(
                        fromDirectoryName: URL(fileURLWithPath: worktree.path).lastPathComponent)
                else { continue }
                map[Self.key(repository: repository, number: number)] = worktree
            }
        }
        checkouts = map

        guard let ghPath else { return }
        let open = Set(openRequests.map { Self.key(repository: $0.repository, number: $0.number) })
        for (key, worktree) in map where !open.contains(key) && !busy.contains(key) {
            guard !Task.isCancelled else { return }
            // A PR gh said was open a little while ago isn't asked about again yet.
            if let seen = seenOpen[key], Date().timeIntervalSince(seen) < 600 { continue }
            let parts = key.split(separator: "#")
            guard parts.count == 2, let number = Int(parts[1]) else { continue }
            let repository = String(parts[0])
            guard let state = await Self.prState(repository: repository, number: number, ghPath: ghPath) else {
                continue
            }
            guard state.closed else {
                seenOpen[key] = Date()
                continue
            }
            guard !busy.contains(key), !Task.isCancelled else { continue }
            let dirty = await Self.hasChanges(worktree.path)
            let committed = await WorktreeSidebarViewModel.hasLocalCommits(
                worktreePath: worktree.path, prHeadOid: state.headOid)
            let candidate = FocusWorktreeCandidate(
                path: worktree.path, prNumber: number, prState: .closed,
                hasOpenTerminal: ReviewCheckouts.hasOpenTerminal(at: worktree.path, cardDirectories: cardDirectories()),
                isDirty: dirty || committed)
            guard ReviewCheckouts.canAutoPrune(candidate) else { continue }
            _ = try? await remove(worktree, repository: repository)
        }
    }

    /// Remove a review checkout: `git worktree remove --force`, then the folder if
    /// git left it, then `git worktree prune`.
    func remove(_ worktree: GitWorktree, repository: String) async throws {
        let clone = clonePath(for: repository)
        _ = try? await GitServiceShared.runGitCommand(
            repoPath: clone, args: ["worktree", "remove", "--force", worktree.path])
        let base = reviewBase
        let path = worktree.path
        try await Task.detached(priority: .utility) {
            guard ReviewCheckouts.isManaged(path: path, base: base) else {
                throw GitHubPRError.commandFailed("Refusing to delete \(URL(fileURLWithPath: path).lastPathComponent)")
            }
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
        }.value
        _ = try? await GitServiceShared.runGitCommand(repoPath: clone, args: ["worktree", "prune"])
        checkouts = checkouts.filter { ReviewCheckouts.canonical($0.value.path) != ReviewCheckouts.canonical(path) }
    }

    // MARK: - Helpers

    /// Make sure a usable clone of `repository` is at `clone`: fetch an existing one,
    /// or clone afresh, first clearing a folder there that isn't a working repository
    /// (an interrupted clone). Only folders inside the hidden-clone folder are cleared.
    private func ensureClone(_ repository: String, at clone: String, ghPath: String) async throws {
        if (try? await GitServiceShared.runGitCommand(repoPath: clone, args: ["rev-parse", "--git-dir"])) != nil {
            if (try? await GitServiceShared.runGitCommand(repoPath: clone, args: ["fetch", "--quiet", "origin"])) == nil
            {
                TermQLogger.ui.warning("ReviewCloneService: fetch failed; using the clone as it is")
            }
            return
        }
        let base = cloneBase
        let parent = try await Task.detached(priority: .userInitiated) { () throws -> URL in
            let cloneURL = URL(fileURLWithPath: clone)
            let inside = ReviewCheckouts.canonical(clone).hasPrefix(
                base.standardizedFileURL.resolvingSymlinksInPath().path + "/")
            if FileManager.default.fileExists(atPath: clone) {
                // A clone that review checkouts point into is never deleted, even if
                // git can't read it right now.
                let hasCheckouts = FileManager.default.fileExists(atPath: clone + "/.git/worktrees")
                guard inside, !hasCheckouts else {
                    throw GitHubPRError.commandFailed("\(cloneURL.lastPathComponent) can't be read by git")
                }
                try FileManager.default.removeItem(at: cloneURL)
            }
            let parent = cloneURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            return parent
        }.value
        let result = try await CommandRunner.run(
            executable: ghPath,
            arguments: ["repo", "clone", repository, clone, "--", "--filter=blob:none", "--quiet"],
            currentDirectory: parent.path)
        guard result.didSucceed else {
            throw GitHubPRError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private struct Head: Decodable {
        let headRefName: String
        let headRefOid: String
        var name: String { headRefName }
        var oid: String { headRefOid }
    }

    private static func prHead(_ request: ReviewRequest, ghPath: String, clone: String) async throws -> Head {
        let result = try await CommandRunner.run(
            executable: ghPath,
            arguments: [
                "pr", "view", "\(request.number)", "--repo", request.repository, "--json", "headRefName,headRefOid",
            ],
            currentDirectory: clone)
        guard result.didSucceed, let head = try? JSONDecoder().decode(Head.self, from: Data(result.stdout.utf8)) else {
            throw GitHubPRError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return head
    }

    struct State: Decodable {
        let state: String
        let headRefOid: String
        var closed: Bool { state != "OPEN" }
        var headOid: String { headRefOid }
    }

    static func prState(repository: String, number: Int, ghPath: String) async -> State? {
        guard
            let result = try? await CommandRunner.run(
                executable: ghPath,
                arguments: ["pr", "view", "\(number)", "--repo", repository, "--json", "state,headRefOid"],
                currentDirectory: NSHomeDirectory()),
            result.didSucceed
        else { return nil }
        return try? JSONDecoder().decode(State.self, from: Data(result.stdout.utf8))
    }

    /// A failed `git status` counts as changed.
    private static func hasChanges(_ path: String) async -> Bool {
        guard let output = try? await GitServiceShared.runGitCommand(repoPath: path, args: ["status", "--porcelain"])
        else { return true }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Every hidden clone (`<host>/<owner>/<name>`) and its review checkouts.
    private static func scan(cloneBase: URL, host: String) async -> [String: [GitWorktree]] {
        let hostDir = cloneBase.appendingPathComponent(host)
        let repositories: [String] = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let owners = (try? fm.contentsOfDirectory(atPath: hostDir.path)) ?? []
            return owners.flatMap { owner in
                ((try? fm.contentsOfDirectory(atPath: hostDir.appendingPathComponent(owner).path)) ?? [])
                    .filter { fm.fileExists(atPath: hostDir.appendingPathComponent("\(owner)/\($0)/.git").path) }
                    .map { "\(owner)/\($0)" }
            }
        }.value
        var result: [String: [GitWorktree]] = [:]
        for repository in repositories {
            let clone = hostDir.appendingPathComponent(repository).path
            guard let listed = try? await GitServiceShared.listWorktrees(repoPath: clone) else { continue }
            result[repository] = listed.filter {
                URL(fileURLWithPath: $0.path).lastPathComponent.hasPrefix(ReviewCheckouts.directoryPrefix)
            }
        }
        return result
    }
}
