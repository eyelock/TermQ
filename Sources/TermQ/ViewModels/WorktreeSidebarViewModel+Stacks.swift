import Foundation
import TermQCore
import TermQShared

// MARK: - Stack Switch Error

/// Reasons a guarded stack-branch switch is refused. The worktree must be safe to
/// rewrite before the provider checks anything out.
enum StackSwitchBlockedError: Error, LocalizedError, Sendable {
    case worktreeDirty
    case worktreeInUse
    case checkedOutElsewhere(path: String)

    var errorDescription: String? {
        switch self {
        case .worktreeDirty:
            return Strings.Stacks.switchBlockedDirty
        case .worktreeInUse:
            return Strings.Stacks.switchBlockedInUse
        case .checkedOutElsewhere(let path):
            return Strings.Stacks.switchBlockedElsewhere(path)
        }
    }
}

// MARK: - Restack Outcome

/// What a restack actually did — derived by diffing the graph's needsRestack set
/// before/after, since gs output isn't structured. Drives the completion toast.
enum StackRestackOutcome: Equatable {
    /// Nothing had diverged; restack was a no-op.
    case upToDate
    /// N branches that needed a restack no longer do.
    case restacked(Int)
    /// The restack paused on conflicts — the banner reports it; no toast.
    case paused
}

/// A stale branch the cross-worktree orchestration refused to touch, and why.
/// The needsRestack badge stays on as the persistent indicator.
struct StackSkippedRestack: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case dirty
        case inUse
    }

    let branch: String
    let worktreePath: String
    let reason: Reason

    /// One line for the notice toast, e.g.
    /// "feat/x (checked out in ~/wt with uncommitted changes)".
    var noticeLine: String {
        switch reason {
        case .dirty: return Strings.Stacks.skippedDirty(branch, worktreePath)
        case .inUse: return Strings.Stacks.skippedInUse(branch, worktreePath)
        }
    }
}

/// Combined result of a restack plus the cross-worktree follow-up sweep.
struct StackRestackReport: Equatable {
    let outcome: StackRestackOutcome
    let skipped: [StackSkippedRestack]
}

/// Combined result of a provider sync plus the cross-worktree follow-up sweep.
struct StackSyncReport: Equatable {
    let removedBranches: [String]
    let skipped: [StackSkippedRestack]
}

// MARK: - Stack Groups

/// One tracked stack for the sidebar's Stacks inventory section: the chain of branches
/// from the stack bottom (parent = trunk) upward.
struct StackGroup: Identifiable, Equatable {
    /// The bottom branch of the stack — the group's title and stable identity.
    let rootName: String
    /// The chain bottom → top.
    let branches: [StackBranch]

    var id: String { rootName }
}

// MARK: - Stacks

extension WorktreeSidebarViewModel {
    /// All tracked stacks in the repo's graph — anchored to a worktree or not — for the
    /// Stacks inventory section. Groups come from `StackGraph.stackRoots`, which
    /// excludes the trunk (a fan-out point for multiple stacks, never a member or a
    /// title) and lone tracked branches sitting directly on trunk (they stay in Local
    /// Branches). Sorted by root name for stable presentation.
    func stackGroups(for repo: ObservableRepository) -> [StackGroup] {
        guard let graph = stacks[repo.id] else { return [] }
        return graph.stackRoots
            .map { StackGroup(rootName: $0.name, branches: graph.chain(containing: $0.name)) }
            .filter { $0.branches.count > 1 }
            .sorted { $0.rootName.localizedCaseInsensitiveCompare($1.rootName) == .orderedAscending }
    }

    /// The worktree that has `branch` checked out, if any — drives the worktree
    /// indicator on Stacks-section entries (a jump target, not a duplicate action
    /// surface).
    func worktree(forBranch branch: String, repo: ObservableRepository) -> GitWorktree? {
        worktrees[repo.id]?.first { $0.branch == branch }
    }

    /// Expand everything between the sidebar root and a worktree row so a reveal can
    /// scroll to it. Collapsed rows are NOT EMITTED (the phantom-gap rule), so
    /// `scrollTo` has nothing to find until the repo and its Worktrees section are
    /// expanded — callers expand first, give SwiftUI a tick to emit rows, then scroll.
    /// Both expansions persist like their manual counterparts.
    func prepareRevealWorktree(for repo: ObservableRepository) {
        setExpanded(repo.id, expanded: true)
        setWorktreeSectionExpanded(repo.id, expanded: true)
    }

    /// The bottom branch of the stack containing `worktree`'s checked-out branch, or
    /// `nil` when it isn't part of a stack — drives the persistent stack glyph on
    /// worktree rows and its "Part of stack …" help text.
    func stackRootName(for worktree: GitWorktree, repo: ObservableRepository) -> String? {
        guard let branch = worktree.branch, let graph = stacks[repo.id],
            graph.isStacked(branch)
        else { return nil }
        return graph.rootBranch(for: branch)?.name
    }

    /// The repo's main worktree — the execution CWD for inventory-initiated stack
    /// mutations. gs targets branches via `--branch` without requiring a checkout, so
    /// operations launched from the Stacks section run against the main worktree and
    /// go through the same per-repo mutation queue as everything else.
    func mainWorktree(for repo: ObservableRepository) -> GitWorktree? {
        worktrees[repo.id]?.first(where: \.isMainWorktree)
    }

    /// Local branches for the Local Branches section, excluding branches that already
    /// appear inside a stack group — a branch should be listed in exactly one place.
    func displayedLocalBranches(for repo: ObservableRepository) -> [String] {
        let branches = availableBranches[repo.id] ?? []
        let stacked = Set(stackGroups(for: repo).flatMap { $0.branches.map(\.name) })
        guard !stacked.isEmpty else { return branches }
        return branches.filter { !stacked.contains($0) }
    }

    /// Refresh stack graphs for every registered repo. Called once after the initial
    /// provider probe; per-repo refreshes afterward piggyback on `refreshWorktrees`.
    func refreshAllStacks() async {
        guard stackService.isAvailable else { return }
        for repo in repositories {
            await refreshStack(for: repo)
        }
    }

    /// Refresh the stack graph for a single repo and mirror it into `stacks`, keyed by
    /// repo id (like `worktrees`). No-ops when no provider is available.
    func refreshStack(for repo: ObservableRepository) async {
        guard stackService.isAvailable else {
            stacks.removeValue(forKey: repo.id)
            return
        }
        await stackService.refreshGraph(repo: repo.path)
        stacks[repo.id] = stackService.graphsByRepo[repo.path]
    }

    /// Enable stacking (`gs repo init`) for `repo` against its default branch, then
    /// refresh the graph. Errors surface via `operationError` like other sidebar actions.
    func enableStacking(for repo: ObservableRepository) async {
        let trunk = await gitService.defaultBranch(repoPath: repo.path)
        do {
            try await stackService.enableStacking(repo: repo.path, trunk: trunk)
            stacks[repo.id] = stackService.graphsByRepo[repo.path]
        } catch {
            operationError = Strings.Stacks.enableStackingFailed(error.localizedDescription)
        }
    }

    // MARK: Guarded switch

    /// Switch `worktree` to another branch of its stack — the "simple and guarded"
    /// model: refused while the worktree is dirty, while any terminal card is attached
    /// to it, or when the target branch is checked out in another worktree.
    func switchStackBranch(
        repo: ObservableRepository, worktree: GitWorktree, to branch: String
    ) async throws {
        if await isWorktreeDirtyForSwitch(worktree.path) {
            throw StackSwitchBlockedError.worktreeDirty
        }
        if isWorktreeInUse(worktree.path) {
            throw StackSwitchBlockedError.worktreeInUse
        }
        // Prefer the live local-worktree lookup for "checked out elsewhere" — the
        // graph's field is relative to wherever gs log ran. The alert names the
        // owning worktree so the user knows where to go instead.
        if let owner = self.worktree(forBranch: branch, repo: repo), owner.path != worktree.path {
            throw StackSwitchBlockedError.checkedOutElsewhere(path: owner.path)
        }
        if let target = stacks[repo.id]?.branch(named: branch),
            let elsewhere = target.checkedOutElsewhere,
            elsewhere != worktree.path
        {
            throw StackSwitchBlockedError.checkedOutElsewhere(path: elsewhere)
        }
        try await stackService.switchBranch(repo: repo.path, worktree: worktree.path, to: branch)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    private func isWorktreeDirtyForSwitch(_ path: String) async -> Bool {
        if let worktreeDirtyCheckOverride {
            return await worktreeDirtyCheckOverride(path)
        }
        return await GitServiceShared.isWorktreeDirty(worktreePath: path)
    }

    /// Whether any terminal card (persistent or transient) lives inside `path`.
    /// Mirrors the containment rule used by the sidebar's terminal badges.
    private func isWorktreeInUse(_ path: String) -> Bool {
        if let worktreeInUseCheckOverride {
            return worktreeInUseCheckOverride(path)
        }
        let boardVM = BoardViewModel.shared
        let cards = boardVM.board.cards + Array(boardVM.tabManager.transientCards.values)
        return cards.contains { card in
            guard !card.isDeleted else { return false }
            let wd = card.workingDirectory
            return wd == path || wd.hasPrefix(path + "/")
        }
    }

    // MARK: Stack mutations

    /// Add a branch to the stack in `worktree`. If `name` already exists as a local
    /// branch it is tracked onto the stack (base = `target` or the worktree's current
    /// branch); otherwise a new branch is created stacked on `target`/current.
    func addBranchToStack(
        repo: ObservableRepository, worktree: GitWorktree, name: String, target: String?
    ) async throws {
        let existing = (try? await gitService.listBranches(repoPath: repo.path)) ?? []
        if existing.contains(name) {
            let base: String
            if let explicit = target ?? worktree.branch {
                base = explicit
            } else {
                base = await gitService.defaultBranch(repoPath: repo.path)
            }
            try await stackService.trackBranch(
                repo: repo.path, worktree: worktree.path, name: name, base: base)
        } else {
            try await stackService.createBranch(
                repo: repo.path, worktree: worktree.path, name: name, target: target)
        }
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    /// Restack `scope` in `worktree` and report what happened — gs prints nothing
    /// structured, so the outcome is derived by diffing the graph's needsRestack set
    /// before/after. A conflict pause is not an error — the sidebar shows the conflict
    /// banner from `stackService.conflicts` and the outcome is `.paused`.
    ///
    /// After the restack, stale branches owned by OTHER worktrees (which git can't
    /// rebase from here, so gs silently skips them) get a follow-up orchestration
    /// sweep; branches it couldn't touch are reported in `skipped`.
    @discardableResult
    func restack(
        repo: ObservableRepository, worktree: GitWorktree, scope: StackScope
    ) async throws -> StackRestackReport {
        let needingBefore = Set(
            stacks[repo.id]?.branches.filter(\.needsRestack).map(\.name) ?? [])
        try await stackService.restack(repo: repo.path, worktree: worktree.path, scope: scope)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
        if stackService.conflicts[repo.path] != nil {
            return StackRestackReport(outcome: .paused, skipped: [])
        }
        let skipped = await orchestrateCrossWorktreeRestacks(for: repo, excluding: worktree.path)
        if stackService.conflicts[repo.path] != nil {
            return StackRestackReport(outcome: .paused, skipped: skipped)
        }
        guard !needingBefore.isEmpty else {
            return StackRestackReport(outcome: .upToDate, skipped: skipped)
        }
        let needingAfter = Set(
            stacks[repo.id]?.branches.filter(\.needsRestack).map(\.name) ?? [])
        let resolved = needingBefore.subtracting(needingAfter).count
        return StackRestackReport(
            outcome: resolved == 0 ? .upToDate : .restacked(resolved), skipped: skipped)
    }

    /// Cross-worktree restack orchestration.
    ///
    /// git can't rebase a branch checked out in another worktree, so gs SKIPS such
    /// branches during restack/sync — silently leaving them stale. After a restack or
    /// sync, this sweeps the fresh graph for branches that still need a restack and
    /// are owned by some other worktree: if the owning worktree is clean and has no
    /// attached terminal (the exact guards used for switching), a single-branch
    /// restack runs with the owning worktree as CWD, serialized through the same
    /// per-repo mutation queue. Dirty or in-use worktrees are left untouched and
    /// reported. Capped at two sweeps so a branch that never converges can't
    /// ping-pong.
    ///
    /// - Parameter excluding: the worktree the triggering operation ran in — its own
    ///   branch was already handled and must not be re-touched.
    @discardableResult
    func orchestrateCrossWorktreeRestacks(
        for repo: ObservableRepository, excluding excludedWorktreePath: String? = nil
    ) async -> [StackSkippedRestack] {
        guard stackService.isAvailable else { return [] }
        var skipped: [StackSkippedRestack] = []
        for _ in 0..<2 {
            guard stackService.conflicts[repo.path] == nil else { break }
            guard let graph = stacks[repo.id] else { break }

            // Stale branches owned by a worktree other than the one that triggered us.
            var candidates: [(branch: String, owner: GitWorktree)] = []
            for entry in graph.branches where entry.needsRestack && !graph.isTrunk(entry.name) {
                guard let owner = worktree(forBranch: entry.name, repo: repo),
                    owner.path != excludedWorktreePath
                else { continue }
                candidates.append((entry.name, owner))
            }
            guard !candidates.isEmpty else { break }

            skipped = []
            var didWork = false
            for (branch, owner) in candidates {
                guard stackService.conflicts[repo.path] == nil else { break }
                if await isWorktreeDirtyForSwitch(owner.path) {
                    skipped.append(
                        StackSkippedRestack(branch: branch, worktreePath: owner.path, reason: .dirty))
                    continue
                }
                if isWorktreeInUse(owner.path) {
                    skipped.append(
                        StackSkippedRestack(branch: branch, worktreePath: owner.path, reason: .inUse))
                    continue
                }
                do {
                    try await stackService.restack(
                        repo: repo.path, worktree: owner.path, scope: .branch(branch))
                    didWork = true
                } catch {
                    // Leave the needsRestack badge as the persistent indicator.
                    TermQLogger.ui.warning("Stack orchestration: follow-up restack failed")
                }
            }
            guard didWork else { break }
            await refreshStack(for: repo)
        }
        return skipped
    }

    /// Submit (create/update) change requests for `scope`, then refresh worktrees and
    /// PR data so the new CRs appear in the sidebar immediately.
    func submitStack(
        repo: ObservableRepository, worktree: GitWorktree, scope: StackScope,
        options: StackSubmitOptions
    ) async throws {
        try await stackService.submit(
            repo: repo.path, worktree: worktree.path, scope: scope, options: options)
        await refreshWorktrees(for: repo)
        await prService.refresh(repoPath: repo.path, force: true)
    }

    /// Provider-aware repo sync (pull trunk, delete merged locals, retarget upstack CRs).
    /// Returns the names of tracked branches the sync removed, so callers can surface
    /// what happened — sync deleting merged locals silently would look like data loss.
    @discardableResult
    func syncStackRepo(
        for repo: ObservableRepository, worktree: GitWorktree
    ) async throws -> StackSyncReport {
        let before = Set(stacks[repo.id]?.branches.map(\.name) ?? [])
        try await stackService.sync(repo: repo.path, worktree: worktree.path)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
        // Sync restacks upstack branches but skips any checked out in other worktrees
        // — sweep them like a restack does.
        var skipped: [StackSkippedRestack] = []
        if stackService.conflicts[repo.path] == nil {
            skipped = await orchestrateCrossWorktreeRestacks(for: repo, excluding: worktree.path)
        }
        await prService.refresh(repoPath: repo.path, force: true)
        let after = Set(stacks[repo.id]?.branches.map(\.name) ?? [])
        return StackSyncReport(
            removedBranches: before.subtracting(after).sorted(), skipped: skipped)
    }

    /// Resume the repo's conflict-paused operation after manual resolution.
    func continueStackOperation(repo: ObservableRepository, worktree: String) async throws {
        try await stackService.continuePaused(repo: repo.path, worktree: worktree)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }

    /// Abort the repo's conflict-paused operation.
    func abortStackOperation(repo: ObservableRepository, worktree: String) async throws {
        try await stackService.abortPaused(repo: repo.path, worktree: worktree)
        monitors[repo.id]?.resetWatches()
        await refreshWorktrees(for: repo)
    }
}
