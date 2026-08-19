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
///
/// ## Provider resolution
///
/// More than one provider can be installed, and each repo is owned by exactly one of
/// them — decided by initialization evidence, not by global preference (see
/// `StackProviderRegistry.resolveProvider(forRepo:preferred:)`). This service therefore
/// caches a provider PER REPO rather than holding one app-wide `activeProvider`; every
/// mutation runs against the provider that actually owns the repo it targets.
@MainActor
final class StackService: ObservableObject {
    static let shared = StackService()

    /// Availability of every registered provider, ready or not — the Settings tab needs
    /// the `.missing`/`.unusable` cases in order to explain them.
    @Published private(set) var availabilityByProvider: [StackProviderID: StackProviderAvailability] = [:]
    /// Which provider owns each repo, for repos resolved so far. Published so the UI can
    /// label a repo's stack with the tool driving it.
    @Published private(set) var providerIDByRepo: [String: StackProviderID] = [:]
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
    /// Resolved provider instances keyed by repo path. Mirrors `providerIDByRepo`, which
    /// is the published (Sendable, comparable) projection of the same thing.
    private var providersByRepo: [String: any StackProvider] = [:]
    /// Tail of the per-repo mutation chain; each new mutation awaits the previous one.
    private var mutationTail: [String: Task<Void, Never>] = [:]

    /// Reads the user's preferred-provider setting. Injected rather than captured so
    /// tests can drive resolution without touching `UserDefaults`.
    private let preference: @MainActor () -> PreferredStackProvider

    /// Which provider to favour when a repo has no initialization evidence either way —
    /// i.e. when enabling stacking on a fresh repo, or when a repo somehow carries both
    /// tools' metadata. `nil` means "registry order".
    ///
    /// Read through on every resolution rather than cached, so changing the setting takes
    /// effect without anything having to push the new value in here.
    var preferredProviderID: StackProviderID? {
        switch preference() {
        case .automatic: return nil
        case .gitSpice: return .gitSpice
        case .gitHub: return .gitHub
        }
    }

    init(
        registry: StackProviderRegistry = .shared,
        preference: @escaping @MainActor () -> PreferredStackProvider = {
            SettingsStore.shared.preferredStackProvider
        }
    ) {
        self.registry = registry
        self.preference = preference
    }

    /// Re-resolve the repos whose owner was decided by preference rather than by
    /// evidence. Call when the preferred-provider setting changes.
    ///
    /// A repo with initialization evidence keeps its provider no matter what the setting
    /// says — evidence beats preference — so those cache entries are deliberately left
    /// alone. Only fallback resolutions can produce a different answer.
    func preferredProviderDidChange() async {
        for (repo, provider) in providersByRepo where !(await provider.isInitialized(repo: repo)) {
            providersByRepo.removeValue(forKey: repo)
            providerIDByRepo.removeValue(forKey: repo)
        }
    }

    // MARK: - Probe

    /// Probe every registered provider. Call once at app launch and on demand (e.g. a
    /// "re-check" affordance). Ship-safe: leaves nothing ready, with zero behavior
    /// change, when no provider is installed.
    ///
    /// Re-validates the per-repo provider cache rather than emptying it.
    ///
    /// A provider appearing or vanishing can change who owns a repo, so a cached entry is
    /// kept only while it still holds: the provider is still ready, and it still finds its
    /// own initialization evidence in that repo. Anything else is dropped and re-resolved
    /// on next use — which is where a newly installed provider gets its chance to claim a
    /// repo that nothing had evidence for.
    ///
    /// Clearing wholesale would be simpler and is wrong: `capabilities(forRepo:)` answers
    /// from this cache, and the sidebar gates every stack action on it. An empty cache
    /// reads as "this provider can do nothing", so a re-probe would blank the stack menus
    /// until some later graph refresh happened to repopulate them.
    func probe() async {
        availabilityByProvider = await registry.probeAll()
        for (repo, provider) in providersByRepo {
            let stillReady = availabilityByProvider[provider.providerID]?.isReady ?? false
            if stillReady, await provider.isInitialized(repo: repo) { continue }
            providersByRepo.removeValue(forKey: repo)
            providerIDByRepo.removeValue(forKey: repo)
        }
    }

    /// Availability of one specific provider — what the Settings card for that tool shows.
    func availability(for id: StackProviderID) -> StackProviderAvailability {
        availabilityByProvider[id] ?? .missing
    }

    /// Summary availability across all providers: ready if any provider is ready,
    /// otherwise the most informative failure (an `.unusable` reason beats a bare
    /// `.missing`). Backs the app-wide "is stacking available at all" gates.
    var availability: StackProviderAvailability {
        var fallback: StackProviderAvailability = .missing
        for id in orderedProviderIDs {
            guard let entry = availabilityByProvider[id] else { continue }
            switch entry {
            case .ready:
                return entry
            case .unusable:
                if case .missing = fallback { fallback = entry }
            case .missing:
                continue
            }
        }
        return fallback
    }

    /// Registry order, so `availability` and the Settings tab agree on precedence.
    private var orderedProviderIDs: [StackProviderID] {
        // Deterministic: preferred first (when set), then the rest sorted by raw value.
        let all = availabilityByProvider.keys.sorted { $0.rawValue < $1.rawValue }
        guard let preferredProviderID, all.contains(preferredProviderID) else { return all }
        return [preferredProviderID] + all.filter { $0 != preferredProviderID }
    }

    var isAvailable: Bool { availability.isReady }

    /// Capabilities of the provider that owns `repo`. Empty when the repo has no
    /// resolved provider — callers gate actions on this rather than assuming any
    /// particular tool's feature set.
    func capabilities(forRepo repo: String) -> StackCapabilities {
        providersByRepo[repo]?.capabilities ?? []
    }

    /// Resolve (and cache) the provider that owns `repo`.
    private func provider(forRepo repo: String) async -> (any StackProvider)? {
        if let cached = providersByRepo[repo] { return cached }
        guard
            let (provider, _) = await registry.resolveProvider(
                forRepo: repo, preferred: preferredProviderID)
        else {
            providerIDByRepo.removeValue(forKey: repo)
            return nil
        }
        providersByRepo[repo] = provider
        providerIDByRepo[repo] = provider.providerID
        return provider
    }

    // MARK: - Stack graph

    /// Refresh the stack graph for `repo`. No-ops (clearing cached state) when no
    /// provider is available or the repo isn't stack-initialized.
    ///
    /// `worktrees` lists the repo's worktree paths. Providers with repo-wide state
    /// ignore it; a provider whose tracking lives inside each worktree's git dir needs
    /// it to see the whole repo (see `StackProvider.graph(repo:worktrees:)`). Defaulted
    /// so callers without a worktree list still get whatever the provider can see.
    func refreshGraph(repo: String, worktrees: [String] = []) async {
        guard let provider = await provider(forRepo: repo) else {
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
            let graph = try await provider.graph(repo: repo, worktrees: worktrees)
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
    func enableStacking(repo: String, trunk: String, worktrees: [String] = []) async throws {
        // No repo has evidence yet at this point, so resolution falls through to
        // `preferredProviderID` / registry order — which is exactly the intent here.
        guard let provider = await provider(forRepo: repo) else {
            throw StackProviderError.binaryMissing
        }
        try await provider.initialize(repo: repo, trunk: trunk)
        await refreshGraph(repo: repo, worktrees: worktrees)
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

    /// Create a new tracked branch stacked on `target` (or the current branch when nil),
    /// or — with `position` `.below`/`.above` — relative to whatever is currently
    /// checked out in `worktree` (the caller must have checked that branch out first).
    func createBranch(
        repo: String, worktree: String, name: String, target: String?,
        position: StackBranchPosition = .onTop
    ) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.createBranch(name: name, target: target, position: position, in: worktree)
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
            // Worktree-scoped form: repo-wide providers ignore `worktree` via the protocol
            // default, but a provider whose sync targets the checked-out stack needs it as
            // the working directory (see `StackProvider.sync(repo:worktree:)`).
            try await provider.sync(repo: repo, worktree: worktree)
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

    /// Delete every branch in the stack checked out in `worktree` — both upstack and
    /// downstack from it. Destructive; the caller (view layer) is responsible for
    /// confirming with the user before calling this.
    func destroyStack(repo: String, worktree: String) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.destroyStack(in: worktree)
        }
    }

    /// Merge every change request in a stack. The most consequential thing this service
    /// does — callers MUST have confirmed with the user, naming each change request.
    func mergeStack(
        repo: String, worktree: String, remoteStackID: String, method: StackMergeMethod? = nil
    ) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.mergeStack(
                remoteStackID: remoteStackID, method: method, in: worktree)
        }
    }

    /// Adopt existing branches into a stack on the forge. CREATES change requests for
    /// branches that lack one — not a local-only operation.
    func linkStack(
        repo: String, worktree: String, branches: [String], base: String?
    ) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.linkStack(branches: branches, base: base, in: worktree)
        }
    }

    /// Check out a stack that exists on the forge.
    func checkoutStack(repo: String, worktree: String, remoteStackID: String) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.checkoutStack(remoteStackID: remoteStackID, in: worktree)
        }
    }

    /// Drop the stack from tracking WITHOUT deleting its branches. Distinct from
    /// `destroyStack` — gate on `.untrackStack`, not `.destroyStack`.
    func untrackStack(repo: String, worktree: String) async throws {
        try await runMutation(repo: repo, worktree: worktree) { provider in
            try await provider.untrackStack(in: worktree)
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
        // Resolved per repo: a mutation must run against the tool that actually owns
        // this repository, not whichever provider happens to be installed first.
        guard let provider = await provider(forRepo: repo) else {
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
        providersByRepo.removeValue(forKey: repo)
        providerIDByRepo.removeValue(forKey: repo)
    }

    #if DEBUG
        func setAvailabilityForTesting(
            _ availability: StackProviderAvailability,
            for id: StackProviderID = .gitSpice
        ) {
            availabilityByProvider[id] = availability
        }
    #endif
}
