import Foundation
import TermQShared

/// A provider operation paused on conflicts in a specific worktree, awaiting user
/// resolution (Continue) or cancellation (Abort).
struct StackConflictState: Equatable, Sendable {
    let worktree: String
    let operation: StackPausedOperation
}

/// Owns stacked-PR provider selection, per-repo stack graphs, and the mutation queue.
///
/// Mirrors `GhCliProbe`/`GitHubPRService`: `@MainActor` singleton, `@Published` state the
/// UI observes directly.
///
/// ## Mutation discipline
///
/// All mutations run through a per-repo serial queue — one stack mutation at a time per
/// repository. While a mutation is in flight the repo appears in `mutatingRepos`;
/// `WorktreeSidebarViewModel` uses that to suspend its repo monitor callbacks, dirty
/// polling, and remote fetches for the repo (git-spice's known concurrency issue:
/// background git processes can break `gs repo sync`; harmless caution for any provider).
///
/// A mutation that pauses on conflicts (provider reports a `StackPausedOperation`) does
/// not error — the repo enters `conflicts[repo]` and the UI offers Continue/Abort.
@MainActor
final class StackService: ObservableObject {
    static let shared = StackService()

    @Published private(set) var availability: StackProviderAvailability = .missing
    /// Stack graphs keyed by repo path. Absent entry means "not stacked" or "not yet
    /// fetched" — callers distinguish via `initializedRepos`.
    @Published private(set) var graphsByRepo: [String: StackGraph] = [:]
    @Published private(set) var initializedRepos: Set<String> = []
    @Published private(set) var loadingRepos: Set<String> = []
    @Published private(set) var errorByRepo: [String: String] = [:]
    /// Repos with a stack mutation currently in flight. Monitors/polls/fetches for
    /// these repos must be suspended by observers.
    @Published private(set) var mutatingRepos: Set<String> = []
    /// Repos whose last mutation paused on conflicts, keyed by repo path.
    @Published private(set) var conflicts: [String: StackConflictState] = [:]

    private let registry: StackProviderRegistry
    private var activeProvider: (any StackProvider)?
    /// Tail of the per-repo mutation chain; each new mutation awaits the previous one.
    private var mutationTail: [String: Task<Void, Never>] = [:]

    init(registry: StackProviderRegistry = .shared) {
        self.registry = registry
    }

    // MARK: - Probe

    /// Detect the active provider. Call once at app launch and on demand (e.g. a
    /// "re-check" affordance). Ship-safe: leaves `availability == .missing` with zero
    /// behavior change when no provider is installed.
    func probe() async {
        if let (provider, availability) = await registry.resolveProvider() {
            activeProvider = provider
            self.availability = availability
        } else {
            activeProvider = nil
            availability = .missing
        }
    }

    var isAvailable: Bool { availability.isReady }

    // MARK: - Stack graph

    /// Refresh the stack graph for `repo`. No-ops (clearing cached state) when no
    /// provider is active or the repo isn't stack-initialized.
    func refreshGraph(repo: String) async {
        guard let provider = activeProvider else {
            graphsByRepo.removeValue(forKey: repo)
            initializedRepos.remove(repo)
            return
        }
        loadingRepos.insert(repo)
        defer { loadingRepos.remove(repo) }

        // Uninitialized is a normal state for most repos — skip silently: no provider
        // invocation beyond the (non-mutating) check, no warning, no error entry.
        let initialized = await provider.isInitialized(repo: repo)
        guard initialized else {
            initializedRepos.remove(repo)
            graphsByRepo.removeValue(forKey: repo)
            errorByRepo.removeValue(forKey: repo)
            return
        }
        initializedRepos.insert(repo)

        do {
            let graph = try await provider.graph(repo: repo)
            graphsByRepo[repo] = graph
            errorByRepo.removeValue(forKey: repo)
        } catch StackProviderError.notInitialized {
            // Narrow race: initialization state changed between the check above and the
            // graph fetch. Still a normal state — clear, don't warn.
            initializedRepos.remove(repo)
            graphsByRepo.removeValue(forKey: repo)
            errorByRepo.removeValue(forKey: repo)
        } catch {
            // Warning only for repos that ARE initialized — this is a real failure.
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.ui.warning("StackService: graph fetch failed for \(repo): \(error)")
            } else {
                TermQLogger.ui.warning("StackService: graph fetch failed")
            }
            errorByRepo[repo] = error.localizedDescription
        }
    }

    func isStacked(repo: String) -> Bool {
        initializedRepos.contains(repo)
    }

    // MARK: - Enable stacking

    /// Run `gs repo init` (or the active provider's equivalent) for `repo`, then refresh
    /// its graph. Throws `StackProviderError.binaryMissing` if no provider is active —
    /// callers should already be gating this action on `isAvailable`.
    func enableStacking(repo: String, trunk: String) async throws {
        guard let provider = activeProvider else {
            throw StackProviderError.binaryMissing
        }
        try await provider.initialize(repo: repo, trunk: trunk)
        await refreshGraph(repo: repo)
    }

    // MARK: - Mutations

    func isMutating(repo: String) -> Bool {
        mutatingRepos.contains(repo)
    }

    func conflict(repo: String) -> StackConflictState? {
        conflicts[repo]
    }

    /// Switch the worktree's checked-out branch to another stack entry.
    /// Guards (dirty worktree, attached session) are the caller's responsibility —
    /// see `WorktreeSidebarViewModel.switchStackBranch`.
    func switchBranch(repo: String, worktree: String, to name: String) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.switchBranch(to: name, in: worktree)
        }
    }

    /// Create a new tracked branch stacked on `target` (or the current branch when nil).
    func createBranch(repo: String, worktree: String, name: String, target: String?) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.createBranch(name: name, target: target, in: worktree)
        }
    }

    /// Track an existing branch onto the stack with `base` as its downstack parent.
    func trackBranch(repo: String, worktree: String, name: String, base: String) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.trackBranch(name, base: base, in: worktree)
        }
    }

    /// Restack `scope`. A conflict pause is recorded in `conflicts` instead of throwing.
    func restack(repo: String, worktree: String, scope: StackScope) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.restack(scope: scope, in: worktree)
        }
    }

    /// Create or update change requests for `scope` (idempotent on the provider side).
    func submit(repo: String, worktree: String, scope: StackScope, options: StackSubmitOptions) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.submit(scope: scope, options: options, in: worktree)
        }
    }

    /// Provider-aware repo sync: pulls trunk, deletes merged local branches, and
    /// retargets/restacks upstack change requests after downstack merges. Replaces a
    /// plain fetch for stacked repos. A conflict pause is recorded like any mutation.
    func sync(repo: String, worktree: String) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.sync(repo: repo)
        }
    }

    /// Resume a conflict-paused operation after the user resolved the files.
    /// A further conflict re-enters the paused state.
    func continuePaused(repo: String, worktree: String) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.continueOperation(in: worktree)
        }
    }

    /// Abort a conflict-paused operation and clear the conflict state.
    func abortPaused(repo: String, worktree: String) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.abortOperation(in: worktree)
        }
    }

    /// Serialize a mutation on the repo's queue, flag the repo as mutating for the
    /// duration, and map a provider-reported paused operation onto `conflicts` instead
    /// of surfacing it as an error.
    private func runMutation(
        repo: String,
        worktree: String,
        _ operation: @escaping @MainActor (any StackProvider) async throws -> Void
    ) async throws {
        guard let provider = activeProvider else {
            throw StackProviderError.binaryMissing
        }
        let previous = mutationTail[repo]
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            self.mutatingRepos.insert(repo)
            defer { self.mutatingRepos.remove(repo) }
            do {
                try await operation(provider)
                self.conflicts.removeValue(forKey: repo)
            } catch {
                if let paused = await provider.pausedOperation(repo: repo) {
                    self.conflicts[repo] = StackConflictState(worktree: worktree, operation: paused)
                    TermQLogger.ui.warning("StackService: mutation paused on conflicts")
                    return
                }
                throw error
            }
        }
        mutationTail[repo] = Task { _ = try? await task.value }
        try await task.value
    }

    // MARK: - Eviction

    /// Remove all cached state for a repo (e.g. after it's removed from the sidebar).
    func evict(repo: String) {
        graphsByRepo.removeValue(forKey: repo)
        initializedRepos.remove(repo)
        loadingRepos.remove(repo)
        errorByRepo.removeValue(forKey: repo)
        mutatingRepos.remove(repo)
        conflicts.removeValue(forKey: repo)
        mutationTail.removeValue(forKey: repo)
    }

    #if DEBUG
        func setAvailabilityForTesting(_ availability: StackProviderAvailability) {
            self.availability = availability
        }
    #endif
}
