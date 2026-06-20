import Foundation
import SwiftUI
import TermQCore
import TermQShared

/// Resolved launch context for a terminal card whose session is not live.
///
/// Drives the card's right-click "open" family — the menu mirrors the sidebar
/// worktree menu, but is keyed off whatever a card can be matched back to.
///
/// Produced on the main actor; deliberately a plain (non-isolated) value type so
/// `RunWithFocusContext`'s plain initializer can read its fields. Not required to
/// be Sendable — it never crosses a concurrency boundary.
struct CardLaunchOptions {
    let workingDirectory: String
    let branch: String?
    /// Owning registered repo, if the card's path resolves to one.
    let repo: ObservableRepository?
    /// Tracked worktree at the card's exact path, if any.
    let worktree: GitWorktree?
    /// Effective harness id resolved via the ladder (used to launch).
    let effectiveHarnessId: String?
    /// Human-readable harness name for the menu label (falls back to the id).
    let effectiveHarnessName: String?
    /// Whether the card already carries a baked `harness` tag (`source: harness`).
    let hasBakedHarness: Bool
    /// Focus names for the effective harness (from cached detail), sorted.
    let focuses: [String]

    /// A harness resolved at all — enables "Run with Focus…".
    var canLaunchHarness: Bool { effectiveHarnessId != nil }

    /// Show a dedicated "Launch `<harness>`" item only for cards *without* a
    /// baked harness. Baked-harness cards already relaunch via plain "Open",
    /// so a separate Launch item would be redundant.
    var showsLaunchItem: Bool { !hasBakedHarness && effectiveHarnessId != nil }

    /// Path used for run/focus persistence + the card title slug. Nil when the
    /// card doesn't resolve to a registered repo (launch still works off the
    /// card's own harness tag; persistence is simply skipped).
    var repoPath: String? { repo?.path }
}

/// Maps a `TerminalCard` back to its harness / worktree / repo so a non-live
/// card can offer the same launch options the sidebar offers for a worktree.
///
/// Resolution ladder for the effective harness:
/// 1. the card's own `harness` tag (cards born from a harness),
/// 2. else a worktree-level harness override for the card's path,
/// 3. else the owning repo's default harness.
///
/// Pure value type with injected lookups so the path-matching and ladder
/// ordering are unit-testable without the live singletons.
@MainActor
struct CardLaunchResolver {
    var repositories: [ObservableRepository]
    var worktrees: [UUID: [GitWorktree]]
    var worktreeHarness: (String) -> String?
    var repoDefaultHarness: (String) -> String?
    var harnessByIdOrName: (String) -> Harness?
    var focusesForHarness: (String) -> [String]

    /// Live wiring — reads the shared sidebar/persistence/harness state.
    init(
        sidebar: WorktreeSidebarViewModel = .shared,
        ynh: YNHPersistence = .shared,
        harnessRepository: HarnessRepository = .shared
    ) {
        self.repositories = sidebar.repositories
        self.worktrees = sidebar.worktrees
        self.worktreeHarness = { ynh.harness(for: $0) }
        self.repoDefaultHarness = { ynh.repoDefaultHarness(for: $0) }
        self.harnessByIdOrName = { id in
            harnessRepository.harnesses.first { $0.id == id || $0.name == id }
        }
        self.focusesForHarness = { id in
            harnessRepository.cachedDetail(for: id)?.composition.focuses?.keys.sorted() ?? []
        }
    }

    /// Injectable wiring for tests.
    init(
        repositories: [ObservableRepository],
        worktrees: [UUID: [GitWorktree]],
        worktreeHarness: @escaping (String) -> String? = { _ in nil },
        repoDefaultHarness: @escaping (String) -> String? = { _ in nil },
        harnessByIdOrName: @escaping (String) -> Harness? = { _ in nil },
        focusesForHarness: @escaping (String) -> [String] = { _ in [] }
    ) {
        self.repositories = repositories
        self.worktrees = worktrees
        self.worktreeHarness = worktreeHarness
        self.repoDefaultHarness = repoDefaultHarness
        self.harnessByIdOrName = harnessByIdOrName
        self.focusesForHarness = focusesForHarness
    }

    func resolve(_ card: TerminalCard) -> CardLaunchOptions {
        let wd = card.workingDirectory
        let cardBranch = card.tags.first { $0.key == "branch" }?.value
        let bakedHarness = card.tags.first { $0.key == "harness" }?.value

        let (repo, worktree) = locate(workingDirectory: wd)

        // Ladder: card tag → worktree override → repo default.
        let effectiveId =
            bakedHarness
            ?? worktreeHarness(wd)
            ?? repo.flatMap { repoDefaultHarness($0.path) }

        let harness = effectiveId.flatMap { harnessByIdOrName($0) }
        let name = harness?.name ?? effectiveId
        let focuses = effectiveId.map { focusesForHarness($0) } ?? []

        return CardLaunchOptions(
            workingDirectory: wd,
            branch: cardBranch ?? worktree?.branch,
            repo: repo,
            worktree: worktree,
            effectiveHarnessId: effectiveId,
            effectiveHarnessName: name,
            hasBakedHarness: bakedHarness != nil,
            focuses: focuses
        )
    }

    /// Find the registered repo owning `workingDirectory` and the tracked
    /// worktree at that exact path, if any. Exact-worktree match wins; else
    /// the repo is matched by path containment (repo root or its worktree base).
    private func locate(workingDirectory wd: String) -> (ObservableRepository?, GitWorktree?) {
        for repo in repositories {
            if let wt = worktrees[repo.id]?.first(where: { $0.path == wd }) {
                return (repo, wt)
            }
        }
        let owning = repositories.first { repo in
            wd == repo.path
                || Self.isDescendant(wd, of: repo.path)
                || (repo.worktreeBasePath.map { Self.isDescendant(wd, of: $0) } ?? false)
        }
        return (owning, nil)
    }

    private static func isDescendant(_ path: String, of base: String) -> Bool {
        guard !base.isEmpty else { return false }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return path.hasPrefix(prefix)
    }
}

/// Card-launch callbacks threaded from `ContentView` down to `TerminalCardView`,
/// so the card menu can drive the reuse-in-place launch flow without each
/// intermediate view needing the launch coordinator.
@MainActor
struct CardLaunchActions {
    /// Launch the card's effective harness (no focus) in place.
    let launchHarness: (TerminalCard) -> Void
    /// Present the Run-with-Focus sheet seeded for the card.
    let runWithFocus: (TerminalCard) -> Void
    /// Launch the card's effective harness with the named focus in place.
    let quickLaunchFocus: (TerminalCard, String) -> Void
    /// Open a fresh plain Quick Terminal at the card's directory (new card).
    let quickTerminal: (TerminalCard) -> Void

    /// Live wiring: resolves each card on demand and drives the reuse-in-place
    /// flow through `coordinator`. `runWithFocusContext` is the presenter's
    /// sheet binding (set to seed the Run-with-Focus sheet for a card).
    static func live(
        coordinator: HarnessLaunchCoordinator,
        runWithFocusContext: Binding<RunWithFocusContext?>
    ) -> CardLaunchActions {
        CardLaunchActions(
            launchHarness: { card in
                let opts = CardLaunchResolver().resolve(card)
                guard let id = opts.effectiveHarnessId else { return }
                coordinator.applyHarness(id, focus: nil, branch: opts.branch, to: card)
            },
            runWithFocus: { card in
                runWithFocusContext.wrappedValue = RunWithFocusContext(
                    card: card, options: CardLaunchResolver().resolve(card))
            },
            quickLaunchFocus: { card, focusName in
                let opts = CardLaunchResolver().resolve(card)
                guard let id = opts.effectiveHarnessId else { return }
                coordinator.applyHarness(id, focus: focusName, branch: opts.branch, to: card)
            },
            quickTerminal: { card in coordinator.openQuickTerminal(card) }
        )
    }
}
