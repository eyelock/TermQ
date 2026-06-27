import Foundation
import Observation
import TermQCore
import TermQShared

/// Pending launch request — captured before `HarnessRepository` may be loaded.
///
/// On a cold launch the user can click Launch from a worktree row before
/// `HarnessRepository.refresh()` has populated `harnesses`. Holding the
/// request lets us resolve it once the list lands without ever presenting an
/// empty-content sheet (the source of the white-pill bug).
struct PendingLaunch: Equatable {
    let harnessId: String
    let workingDirectory: String?
    let branch: String?
}

/// Fully resolved data for the harness launch sheet.
///
/// Constructed only when both the repository is `.loaded` and the requested
/// `harnessId` resolves to a `Harness`. The sheet is presented via
/// `.sheet(item:)` against this — when `nil`, no sheet is presented at all,
/// avoiding the SwiftUI empty-content footgun.
struct LaunchSheetTarget: Identifiable, Equatable {
    let harness: Harness
    let workingDirectory: String?
    let branch: String?
    let vendorOverride: String?

    var id: String { harness.id }
}

/// Owns the harness launch flow end-to-end. Extracted from `ContentView`
/// so launch state and coordination logic can be tested in isolation and
/// don't bloat the view's body.
///
/// **Pattern:** held by `ContentView` via `@State`, with the singleton
/// services it depends on injected at construction time. Sub-views that
/// need to participate in the flow receive the coordinator via
/// `@Environment(HarnessLaunchCoordinator.self)`.
@MainActor
@Observable
final class HarnessLaunchCoordinator {
    /// Pending launch request. Held until `harnessRepo` is `.loaded` and
    /// the id resolves; at that point it materializes into
    /// `launchSheetTarget` and the sheet presents.
    var pendingLaunch: PendingLaunch?

    /// Resolved data backing the launch sheet. The sheet uses
    /// `.sheet(item:)` against this — when `nil`, no sheet is presented.
    var launchSheetTarget: LaunchSheetTarget?

    /// Working-directory hint for the sheet (used by sub-Views that read
    /// it for context during launch).
    var launchWorkingDirectory: String?

    /// Branch hint for the sheet (used by sub-Views that read it for
    /// context during launch).
    var launchWorktreeBranch: String?

    /// Card that was selected before navigating to a harness detail.
    /// Restored on dismiss.
    var cardBeforeHarness: TerminalCard?

    @ObservationIgnored private let harnessRepo: HarnessRepository
    @ObservationIgnored private let vendorService: VendorService
    @ObservationIgnored private let boardViewModel: BoardViewModel
    @ObservationIgnored private let ynhPersistence: YNHPersistence

    init(
        harnessRepo: HarnessRepository = .shared,
        vendorService: VendorService = .shared,
        boardViewModel: BoardViewModel = .shared,
        ynhPersistence: YNHPersistence = .shared
    ) {
        self.harnessRepo = harnessRepo
        self.vendorService = vendorService
        self.boardViewModel = boardViewModel
        self.ynhPersistence = ynhPersistence
    }

    // MARK: - Launch flow

    /// Entry point for every launch path (worktree row, default-harness
    /// context menu, sidebar, command palette). Records the request and
    /// tries to resolve it immediately; if the repo isn't loaded yet,
    /// `tryResolvePendingLaunch()` (called from a `listState` observer in
    /// `ContentView`) will resolve it when data lands.
    func requestLaunch(harnessId: String, workingDirectory: String?, branch: String?) {
        pendingLaunch = PendingLaunch(
            harnessId: harnessId,
            workingDirectory: workingDirectory,
            branch: branch
        )
        launchWorkingDirectory = workingDirectory
        launchWorktreeBranch = branch
        Task { await vendorService.refresh() }
        // Reflect the selection in the repo so detail-view-driven UI (and
        // the existing fetchDetail flow) sees the new selection.
        harnessRepo.selectedHarnessId = harnessId
        tryResolvePendingLaunch()
    }

    /// Materialize `pendingLaunch` into `launchSheetTarget` when both the
    /// repo is `.loaded` and the harness id resolves. Idempotent.
    func tryResolvePendingLaunch() {
        guard let pending = pendingLaunch else { return }
        guard harnessRepo.listState.isLoaded else { return }
        // Tolerate ids and bare names (legacy worktree associations may
        // still hold a pre-migration value during the same session). The
        // repository selection above used the same string so this stays
        // consistent.
        let key = pending.harnessId
        let resolved =
            harnessRepo.harnesses.first { $0.id == key }
            ?? harnessRepo.harnesses.first { $0.name == key }
        guard let harness = resolved else {
            // Repo loaded but the requested id isn't installed — drop the
            // request silently rather than holding it forever.
            pendingLaunch = nil
            return
        }
        launchSheetTarget = LaunchSheetTarget(
            harness: harness,
            workingDirectory: pending.workingDirectory,
            branch: pending.branch,
            vendorOverride: ynhPersistence.vendorOverride(for: harness.id)
        )
        pendingLaunch = nil
    }

    /// Launch a harness by creating a persistent card with `ynh run` as
    /// the init command. If `reuseExisting` is true and a matching card
    /// already exists (same harness + working directory), switches to it
    /// instead of creating a duplicate.
    func launchHarness(_ config: HarnessLaunchConfig, reuseExisting: Bool = true) {
        if reuseExisting,
            let existing = boardViewModel.allTerminals.first(where: { card in
                card.workingDirectory == config.workingDirectory
                    && card.tags.contains(where: { tag in
                        tag.key == "harness" && tag.value == config.harnessID
                    })
            })
        {
            cardBeforeHarness = nil
            harnessRepo.selectedHarnessId = nil
            boardViewModel.tabManager.addTab(existing.id)
            boardViewModel.objectWillChange.send()
            boardViewModel.selectedCard = existing
            return
        }

        let column: TermQCore.Column
        if let current = boardViewModel.selectedCard,
            let currentColumn = boardViewModel.board.columns.first(where: {
                $0.id == current.columnId
            })
        {
            column = currentColumn
        } else if let firstColumn = boardViewModel.board.columns.first {
            column = firstColumn
        } else {
            return
        }

        let cardID = UUID()
        let sessionName = "termq-\(cardID.uuidString.prefix(8).lowercased())"
        let shell =
            ProcessInfo.processInfo.environment["SHELL"]
            .map { URL(fileURLWithPath: $0).lastPathComponent } ?? "sh"
        var allTags = config.tags.map { TermQCore.Tag(key: $0.key, value: $0.value) }
        allTags.append(TermQCore.Tag(key: "backend", value: config.backend.tagValue))
        allTags.append(TermQCore.Tag(key: "shell", value: shell))
        if config.backend.usesTmux {
            allTags.append(TermQCore.Tag(key: "session", value: sessionName))
            allTags.append(TermQCore.Tag(key: "window", value: "0"))
        }

        let store = SettingsStore.shared
        let card = TerminalCard(
            id: cardID,
            title: config.cardTitle ?? config.branch ?? config.harnessID,
            tags: allTags,
            columnId: column.id,
            workingDirectory: config.workingDirectory,
            initCommand: config.command(sessionName: sessionName),
            safePasteEnabled: nil,
            allowOscClipboard: store.allowOscClipboard,
            confirmExternalModifications: store.confirmExternalLLMModifications,
            backend: config.backend
        )
        card.allowAutorun = true
        card.workspaceId = boardViewModel.newCardWorkspaceId

        boardViewModel.board.cards.append(card)
        boardViewModel.save()

        if let current = boardViewModel.selectedCard {
            boardViewModel.tabManager.insertTab(card.id, after: current.id)
        } else {
            boardViewModel.tabManager.addTab(card.id)
        }

        // Clear harness selection and switch to the new card.
        cardBeforeHarness = nil
        harnessRepo.selectedHarnessId = nil
        boardViewModel.objectWillChange.send()
        boardViewModel.selectedCard = card
    }

    // MARK: - Reuse-in-place (existing card)

    /// Rewrite an existing card's launch (init command + harness tags) from
    /// `config` and open it, instead of creating a new card. Backs the card
    /// menu's Launch / Run with Focus / Quick Launch Focus actions — the fix
    /// for the delete-and-recreate workflow.
    ///
    /// Preserves the card's identity tags (`backend`, `shell`, `session`,
    /// `window`) and its title/backend; only the launch-describing tags and
    /// the init command change.
    func applyLaunchToCard(_ card: TerminalCard, config: HarnessLaunchConfig) {
        rewriteCardLaunch(card, config: config)
        openFresh(card)
    }

    /// Pure reuse-in-place mutation: rewrite the card's launch tags + init
    /// command from `config`, preserving identity tags (`backend`, `shell`,
    /// `session`, `window`). Separated from the open side effect so the rewrite
    /// is unit-testable without driving the session/tab machinery.
    func rewriteCardLaunch(_ card: TerminalCard, config: HarnessLaunchConfig) {
        // Identity tags that outlive a launch change. `repository` is included
        // because `HarnessLaunchConfig.tags` never emits it, so a card that
        // started as a plain terminal would otherwise lose its repo association.
        let preservedKeys: Set<String> = ["backend", "shell", "session", "window", "repository"]
        let preserved = card.tags.filter { preservedKeys.contains($0.key) }
        let launchTags = config.tags.map { TermQCore.Tag(key: $0.key, value: $0.value) }
        card.tags = launchTags + preserved

        // Bind to the card's stable tmux session name (matches the new-card
        // launch path, which derives the same name from the card id).
        card.initCommand = config.command(sessionName: card.tmuxSessionName)
        card.allowAutorun = true

        boardViewModel.save()
    }

    /// Build a minimal `ynh run` config for `card`'s effective harness and apply
    /// it in place. Backs the card menu's "Launch `<harness>`" (focus == nil) and
    /// "Quick Launch Focus" (focus set) items.
    func applyHarness(_ harnessId: String, focus: String?, branch: String?, to card: TerminalCard) {
        let harness = harnessRepo.harnesses.first { $0.id == harnessId || $0.name == harnessId }
        let config = HarnessLaunchConfig(
            harnessID: harness?.id ?? harnessId,
            vendorID: "",
            defaultVendor: harness?.defaultVendor ?? "",
            focus: focus,
            profile: nil,
            workingDirectory: card.workingDirectory,
            prompt: nil,
            instructions: nil,
            backend: SettingsStore.shared.backend,
            branch: branch,
            interactive: false,
            cardTitle: nil
        )
        applyLaunchToCard(card, config: config)
    }

    /// Open a fresh plain "Quick Terminal" at the card's working directory — a
    /// new throwaway card with its own session, mirroring the sidebar's Quick
    /// Terminal. Backs the card menu's "Quick Terminal" item.
    ///
    /// Deliberately does *not* reuse the card's own session: a card's tmux
    /// session (named from its id) may be stale from a prior harness run, so
    /// re-attaching to it shows a blank/dead pane. A brand-new card always gets
    /// a clean session.
    func openQuickTerminal(_ card: TerminalCard) {
        let branch = card.tags.first { $0.key == "branch" }?.value
        let repoName = card.tags.first { $0.key == "repository" }?.value
        boardViewModel.newTerminal(at: card.workingDirectory, branch: branch, repoName: repoName)
    }

    /// Force a fresh terminal session for `card` (so a rewritten init command
    /// takes effect) and open it. A stale session entry is marked for restart so
    /// the manager tears it down and recreates on next access.
    private func openFresh(_ card: TerminalCard) {
        let manager = TerminalSessionManager.shared
        if manager.sessionExists(for: card.id) {
            manager.restartSession(for: card.id)
        }
        harnessRepo.selectedHarnessId = nil
        boardViewModel.selectCard(card)
    }

    // MARK: - Sheet/detail dismiss

    /// Called from the launch sheet's `onDismiss`. Clears the working-dir
    /// and branch hints plus any unresolved pending request.
    func dismissLaunchSheet() {
        launchWorkingDirectory = nil
        launchWorktreeBranch = nil
        pendingLaunch = nil
    }

    /// Called from the harness detail view's dismiss path. Restores the
    /// previously-selected card if one was captured.
    func dismissHarnessDetail() {
        harnessRepo.selectedHarnessId = nil
        if let card = cardBeforeHarness {
            boardViewModel.selectCard(card)
            cardBeforeHarness = nil
        }
    }

    /// Called from the toolbar back button to clear both selections.
    func clearAllSelection() {
        cardBeforeHarness = nil
        harnessRepo.selectedHarnessId = nil
    }

    /// Called when the repo's `selectedHarnessId` transitions from nil to
    /// a value — captures the previously-selected card so dismiss can
    /// restore it.
    func captureCardBeforeHarness() {
        cardBeforeHarness = boardViewModel.selectedCard
    }
}
