import Foundation
import TermQCore
import TermQShared

// MARK: - Review Checkout Lifecycle

/// Review checkouts ("Run with Focus" on a pull request that isn't checked out)
/// are disposable worktrees under `~/.termq/focus-worktrees/`. The rules for
/// what may be removed live in `ReviewCheckouts`; this extension runs them.
extension WorktreeSidebarViewModel {
    /// `host--org--repo` for `repo`, falling back to its folder name.
    func reviewRepoKey(for repo: ObservableRepository) async -> String {
        if let raw = try? await gitService.remoteURL(repoPath: repo.path),
            let key = ReviewCheckouts.repoKey(fromRemoteURL: raw)
        {
            return key
        }
        return URL(fileURLWithPath: repo.path).lastPathComponent
    }

    /// The stable review-checkout path for a pull request.
    ///
    /// Format: `~/.termq/focus-worktrees/termq-focus--<host>--<org>--<repo>--<branch>--<pr>`
    /// The `termq-focus-` prefix is what `refreshWorktrees` uses to keep these out of the
    /// Local tab and route them into `focusWorktrees[repo.id]`.
    func inferFocusWorktreePath(for repo: ObservableRepository, pr: GitHubPR) async -> String {
        let name = ReviewCheckouts.directoryName(
            repoKey: await reviewRepoKey(for: repo), headRefName: pr.headRefName, prNumber: pr.number)
        return reviewCheckoutBase.appendingPathComponent(name).path
    }

    /// Create (or reuse) a review checkout for a remote pull request, then return it.
    ///
    /// The checkout has a detached HEAD at the pull request's head
    /// (`gh pr checkout --detach`), so no local branch is created and it can't collide
    /// with a branch checked out elsewhere. Git is asked directly whether the checkout
    /// exists; a folder at the path that git doesn't list and that isn't a live
    /// worktree of another clone is cleared first.
    func checkoutPRForFocus(
        _ pr: GitHubPR,
        repo: ObservableRepository,
        ghPath: String
    ) async throws -> GitWorktree {
        let worktreePath = await inferFocusWorktreePath(for: repo, pr: pr)
        let listed = try await gitService.listWorktrees(repoPath: repo.path)
        if let existing = listed.first(where: { Self.samePath($0.path, worktreePath) }) {
            await refreshWorktrees(for: repo)
            return existing
        }
        let base = reviewCheckoutBase
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: worktreePath) else { return }
            guard !ReviewCheckouts.isLiveWorktree(at: worktreePath) else {
                throw GitHubPRError.commandFailed(
                    "\(URL(fileURLWithPath: worktreePath).lastPathComponent) belongs to another clone")
            }
            try Self.removeReviewFolder(worktreePath, base: base)
        }.value
        try? await gitService.pruneWorktrees(repoPath: repo.path)
        try await gitService.addDetachedWorktree(repoPath: repo.path, path: worktreePath)
        let result = try await CommandRunner.run(
            executable: ghPath,
            arguments: ["pr", "checkout", "\(pr.number)", "--detach"],
            currentDirectory: worktreePath
        )
        guard result.didSucceed else {
            try? await gitService.forceDeleteWorktree(repoPath: repo.path, worktreePath: worktreePath)
            throw GitHubPRError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
        guard let wt = focusWorktrees[repo.id]?.first(where: { Self.samePath($0.path, worktreePath) }) else {
            throw GitHubPRError.commandFailed("Review checkout not found after checkout")
        }
        return wt
    }

    /// The review checkout git listed for `prNumber` at the last refresh.
    func reviewCheckout(forPR prNumber: Int, repo: ObservableRepository) -> GitWorktree? {
        (focusWorktrees[repo.id] ?? []).first {
            ReviewCheckouts.prNumber(fromDirectoryName: URL(fileURLWithPath: $0.path).lastPathComponent) == prNumber
        }
    }

    /// Check `pr` out as a real worktree (`checkoutPR`), carry the review checkout's
    /// changes across, then remove the review checkout.
    ///
    /// The changes travel as a stash commit made with `git stash create`, which never
    /// touches the stash list other worktrees share. The review checkout is kept, and
    /// the returned note says why, when anything could be lost by removing it: commits
    /// made in it, changes made while the checkout ran, or a terminal working in it.
    /// If the changes don't apply, the new worktree is reset to the PR and the error
    /// says the changes are still in the review checkout.
    ///
    /// - Returns: the new worktree's path, and a note when the review checkout was kept.
    func checkoutPR(
        _ pr: GitHubPR, repo: ObservableRepository, ghPath: String, carryingChangesFrom review: GitWorktree
    ) async throws -> (path: String, note: String?) {
        let reviewName = URL(fileURLWithPath: review.path).lastPathComponent
        let before = try await Self.workingTree(of: review.path)
        let stash = try await Self.stashChanges(in: review.path)
        let path = try await checkoutPR(pr, repo: repo, ghPath: ghPath)
        if let stash {
            do {
                try await Self.applyStash(stash, in: path)
            } catch {
                // The worktree was made seconds ago, so resetting it loses nothing.
                _ = try? await GitServiceShared.runGitCommand(repoPath: path, args: ["reset", "--hard", "-q"])
                _ = try? await GitServiceShared.runGitCommand(repoPath: path, args: ["clean", "-fdq"])
                await refreshWorktrees(for: repo)
                throw GitHubPRError.commandFailed(
                    Strings.RemotePRs.carryFailed(reviewName, error.localizedDescription))
            }
        }
        let after = try? await Self.workingTree(of: review.path)
        if after != before {
            return (path, Strings.RemotePRs.reviewKeptChanged(reviewName))
        }
        if await Self.hasLocalCommits(worktreePath: review.path, prHeadOid: pr.headRefOid) {
            return (path, Strings.RemotePRs.reviewKeptCommits(reviewName))
        }
        let directories = BoardViewModel.shared.board.activeCards.map(\.workingDirectory)
        if ReviewCheckouts.hasOpenTerminal(at: review.path, cardDirectories: directories) {
            return (path, Strings.RemotePRs.reviewKeptInUse(reviewName))
        }
        await pruneFocusWorktrees(
            repo: repo, candidates: [FocusWorktreeCandidate(path: review.path)],
            isInUse: { ReviewCheckouts.hasOpenTerminal(at: $0, cardDirectories: directories) })
        return (path, nil)
    }

    /// Record every change in `worktreePath`, untracked files included, as a stash
    /// commit without touching the shared stash list. `nil` when there are none.
    nonisolated static func stashChanges(in worktreePath: String) async throws -> String? {
        _ = try await GitServiceShared.runGitCommand(repoPath: worktreePath, args: ["add", "-A"])
        let sha = try await GitServiceShared.runGitCommand(repoPath: worktreePath, args: ["stash", "create"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    /// A hash of everything in `worktreePath` (HEAD plus every change, untracked files
    /// included). Equal hashes mean nothing changed in between.
    nonisolated static func workingTree(of worktreePath: String) async throws -> String {
        _ = try await GitServiceShared.runGitCommand(repoPath: worktreePath, args: ["add", "-A"])
        let tree = try await GitServiceShared.runGitCommand(repoPath: worktreePath, args: ["write-tree"])
        let head = try await GitServiceShared.runGitCommand(repoPath: worktreePath, args: ["rev-parse", "HEAD"])
        return tree.trimmingCharacters(in: .whitespacesAndNewlines)
            + head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `worktreePath` has commits that are on no remote branch and not in the
    /// pull request. A review checkout is detached, so such commits live nowhere else.
    /// Anything git can't answer counts as yes.
    nonisolated static func hasLocalCommits(worktreePath: String, prHeadOid: String) async -> Bool {
        guard
            let count = try? await GitServiceShared.runGitCommand(
                repoPath: worktreePath, args: ["rev-list", "--count", "HEAD", "--not", "--remotes", prHeadOid])
        else { return true }
        return (Int(count.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1) > 0
    }

    /// Apply a stash commit from `stashChanges` in another worktree of the same repository.
    nonisolated static func applyStash(_ sha: String, in worktreePath: String) async throws {
        _ = try await GitServiceShared.runGitCommand(repoPath: worktreePath, args: ["stash", "apply", sha])
    }

    /// Every review checkout of `repo`, registered or orphaned, with the facts the
    /// prune rules need. Returns `nil` when git can't list the worktrees, so nothing
    /// is judged on a guess.
    ///
    /// - Parameters:
    ///   - openPRNumbers: the repository's open pull requests, or `nil` when they
    ///     couldn't be listed (every state is then unknown).
    ///   - listIsComplete: whether `openPRNumbers` is every open pull request.
    ///   - cardDirectories: the working directories of the board's terminals.
    func reviewCheckoutCandidates(
        repo: ObservableRepository,
        openPRNumbers: Set<Int>?,
        listIsComplete: Bool,
        cardDirectories: [String]
    ) async -> [FocusWorktreeCandidate]? {
        guard let listed = try? await gitService.listWorktrees(repoPath: repo.path) else { return nil }
        let registered = listed.filter {
            URL(fileURLWithPath: $0.path).lastPathComponent.hasPrefix(ReviewCheckouts.directoryPrefix)
        }
        let base = reviewCheckoutBase
        let repoKey = await reviewRepoKey(for: repo)
        let registeredPaths = Set(registered.map(\.path))
        let orphans = await Task.detached(priority: .utility) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
            return ReviewCheckouts.orphans(
                directoryNames: names, repoKey: repoKey, registeredPaths: registeredPaths, base: base
            ).filter { !ReviewCheckouts.isLiveWorktree(at: $0) }
        }.value

        func candidate(path: String, isOrphan: Bool) async -> FocusWorktreeCandidate {
            let number = ReviewCheckouts.prNumber(fromDirectoryName: URL(fileURLWithPath: path).lastPathComponent)
            let state: ReviewCheckouts.PRState =
                openPRNumbers.map {
                    ReviewCheckouts.state(of: number, openNumbers: $0, listIsComplete: listIsComplete)
                } ?? .unknown
            let dirty = isOrphan ? false : await Self.hasChanges(worktreePath: path)
            return FocusWorktreeCandidate(
                path: path,
                prNumber: number,
                prState: state,
                hasOpenTerminal: ReviewCheckouts.hasOpenTerminal(at: path, cardDirectories: cardDirectories),
                isDirty: dirty,
                isOrphan: isOrphan)
        }

        var result: [FocusWorktreeCandidate] = []
        for worktree in registered {
            result.append(await candidate(path: worktree.path, isOrphan: false))
        }
        for path in orphans {
            result.append(await candidate(path: path, isOrphan: true))
        }
        return result
    }

    /// Remove review checkouts, changes and all, and report the ones that couldn't be
    /// removed. A checkout is skipped if it has an open terminal, either when the
    /// candidates were collected or, through `isInUse`, right before it goes.
    ///
    /// Each removal is `git worktree remove --force`, then deleting the folder if git
    /// left it, then `git worktree prune`, so neither git nor the disk keeps a remnant.
    /// A locked worktree is reported, not removed. Checkouts made before they were
    /// detached may have left a local branch named after the pull request's head; it
    /// is deleted only when git says it is merged (`git branch -d`).
    @discardableResult
    func pruneFocusWorktrees(
        repo: ObservableRepository,
        candidates: [FocusWorktreeCandidate],
        isInUse: (String) -> Bool = { _ in false }
    ) async -> [String] {
        var failures: [String] = []
        let listed = (try? await gitService.listWorktrees(repoPath: repo.path)) ?? []
        var leftoverBranches: [String] = []
        let base = reviewCheckoutBase
        for candidate in candidates where candidate.canPrune {
            guard !Task.isCancelled else { break }
            guard !isInUse(candidate.path) else { continue }
            let worktree = listed.first { Self.samePath($0.path, candidate.path) }
            if worktree?.isLocked == true {
                failures.append(candidate.displayName)
                continue
            }
            if let worktree {
                if let branch = worktree.branch { leftoverBranches.append(branch) }
                try? await gitService.forceDeleteWorktree(repoPath: repo.path, worktreePath: candidate.path)
            }
            let path = candidate.path
            do {
                try await Task.detached(priority: .utility) {
                    try Self.removeReviewFolder(path, base: base)
                }.value
            } catch {
                failures.append(candidate.displayName)
            }
        }
        try? await gitService.pruneWorktrees(repoPath: repo.path)
        for branch in leftoverBranches {
            try? await gitService.deleteLocalBranch(repoPath: repo.path, branch: branch)
        }
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
        return failures
    }

    /// Remove the review checkouts a refresh may remove without asking
    /// (`ReviewCheckouts.canAutoPrune`). `cardDirectories` is read again right before
    /// each removal, so a terminal opened meanwhile keeps its checkout.
    func autoPruneReviewCheckouts(
        repo: ObservableRepository,
        openPRs: [GitHubPR],
        listIsComplete: Bool,
        cardDirectories: () -> [String]
    ) async {
        let base = reviewCheckoutBase
        let hasAny = await Task.detached(priority: .utility) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
            return names.contains { $0.hasPrefix(ReviewCheckouts.directoryPrefix) }
        }.value
        guard hasAny, !Task.isCancelled else { return }
        guard
            let candidates = await reviewCheckoutCandidates(
                repo: repo, openPRNumbers: Set(openPRs.map(\.number)), listIsComplete: listIsComplete,
                cardDirectories: cardDirectories()
            )?.filter(ReviewCheckouts.canAutoPrune),
            !candidates.isEmpty, !Task.isCancelled
        else { return }
        let failures = await pruneFocusWorktrees(
            repo: repo, candidates: candidates,
            isInUse: { ReviewCheckouts.hasOpenTerminal(at: $0, cardDirectories: cardDirectories()) })
        if !failures.isEmpty {
            TermQLogger.ui.warning("Review checkouts: auto-prune left \(failures.count) folder(s)")
        }
    }

    /// Whether a worktree has changes. A `git status` that fails counts as changed,
    /// so a checkout git can't read is never removed as clean.
    nonisolated private static func hasChanges(worktreePath: String) async -> Bool {
        guard
            let output = try? await GitServiceShared.runGitCommand(
                repoPath: worktreePath, args: ["status", "--porcelain"])
        else { return true }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated private static func samePath(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).standardizedFileURL.path == URL(fileURLWithPath: rhs).standardizedFileURL.path
    }

    /// Delete a review checkout folder from disk. Refuses any path that isn't a
    /// `termq-focus-` folder directly inside the review checkout folder.
    nonisolated private static func removeReviewFolder(_ path: String, base: URL) throws {
        guard ReviewCheckouts.isManaged(path: path, base: base) else {
            throw GitHubPRError.commandFailed("Refusing to delete \(URL(fileURLWithPath: path).lastPathComponent)")
        }
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(atPath: path)
    }
}
