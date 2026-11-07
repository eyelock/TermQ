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

    /// The Wheelhouse seat whose harness the detail page is showing, when it
    /// was opened from a seat. Launch then opens the seat itself, and the page
    /// says edits apply when the seat restarts.
    var seatDetailContext: SeatDetailContext?

    /// One-off seat launch state awaiting restore, per card: the card's own
    /// init command, and the task that puts it back.
    @ObservationIgnored private var pendingInitCommand: [UUID: String] = [:]
    @ObservationIgnored private var restoreTasks: [UUID: Task<Void, Never>] = [:]

    struct SeatDetailContext: Equatable {
        let wheelhouse: Wheelhouse
        let seat: WheelhouseSeat
    }

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

    /// The phrase the wheelhouse plugin's handoff skill answers to.
    static let handoffRequest = "Let's take a beat, and hand off."
    /// Asks a seat on its first session to run the birth skill.
    static let birthPrompt = "This is your first session in this seat. Use the birth skill."

    /// Opens a Wheelhouse seat and returns its card.
    ///
    /// - With no `focus` or `prompt`: selects the seat's card if it has one,
    ///   else launches its harness (which runs the harness's launch focus).
    /// - With a `focus` or `prompt` and a running card: types the focus's
    ///   prompt (or the prompt) into the seat, so the same session acts on it.
    /// - With a `focus` or `prompt` and no card: launches the harness with it.
    ///
    /// New cards start at the Wheelhouse root, tagged with the Wheelhouse and
    /// the seat so they are found again later.
    @discardableResult
    func launchSeat(
        _ seat: WheelhouseSeat, in wheelhouse: Wheelhouse, focus: WheelhouseFocus? = nil, prompt: String? = nil
    ) -> UUID? {
        let config = seatLaunchConfig(seat, in: wheelhouse, focus: focus, prompt: prompt)
        if let existing = seatCard(seat, in: wheelhouse) {
            let running = TerminalSessionManager.shared.hasActiveSession(for: existing.id)
            if running, let text = focus?.prompt ?? prompt {
                // The same session acts on it.
                send(text, toCard: existing.id)
            } else if !running, focus != nil || prompt != nil {
                // Not running: start it with the focus this once, then put the
                // card's own command back so later opens don't repeat it.
                startOnce(existing, with: config)
            }
            boardViewModel.selectCard(existing)
            return existing.id
        }
        launchHarness(config)
        return seatCard(seat, in: wheelhouse)?.id
    }

    private func seatLaunchConfig(
        _ seat: WheelhouseSeat, in wheelhouse: Wheelhouse, focus: WheelhouseFocus?, prompt: String?
    ) -> HarnessLaunchConfig {
        let harness = harnessRepo.harnesses.first { $0.name == seat.command }
        return HarnessLaunchConfig(
            harnessID: harness?.id ?? "local/\(seat.command)",
            vendorID: "",
            defaultVendor: harness?.defaultVendor ?? "",
            focus: focus?.name,
            profile: nil,
            workingDirectory: wheelhouse.root,
            prompt: focus == nil ? prompt : nil,
            instructions: nil,
            backend: SettingsStore.shared.backend,
            branch: nil,
            interactive: focus != nil || prompt != nil,
            cardTitle: seat.name,
            extraTags: WheelhouseCardMatcher.tags(wheelhouseRoot: wheelhouse.root, seatCommand: seat.command)
        )
    }

    /// Gives a card a one-off init command (a focus or prompt launch) for its
    /// next session start, and restores the original once that session is up.
    private func startOnce(_ card: TerminalCard, with config: HarnessLaunchConfig) {
        // If a one-off is already pending, keep the original it captured.
        let original = pendingInitCommand[card.id] ?? card.initCommand
        let sessionName =
            card.tags.first { $0.key == "session" }?.value
            ?? Self.sessionName(inCommand: original)
        card.initCommand = config.command(sessionName: sessionName)
        // The focus or prompt is new intent: start cold, don't resume past it.
        card.resumeOverrideForNextLaunch = false
        pendingInitCommand[card.id] = original
        restoreTasks[card.id]?.cancel()
        restoreTasks[card.id] = restoreWhenRunning(card) { [weak self] in
            card.initCommand = original
            self?.pendingInitCommand[card.id] = nil
        }
    }

    /// Restarts a seat's card as a new session, not a resumed one: after a
    /// handoff the seat should wake on its own notes (and on an edited
    /// harness), not carry on the old conversation.
    func restartFresh(_ card: TerminalCard) {
        // One-shot: this restart starts cold; later reopens resume as usual.
        card.resumeOverrideForNextLaunch = false
        boardViewModel.restartSession(for: card)
    }

    /// Waits (up to ~30s) for the card's session to start, then restores the
    /// temporary change. Restores even on timeout, and skips a card that has
    /// since been deleted. A newer call for the same card cancels this one.
    private func restoreWhenRunning(
        _ card: TerminalCard, restore: @escaping @MainActor () -> Void
    ) -> Task<
        Void, Never
    > {
        let cardId = card.id
        return Task { @MainActor in
            for _ in 0..<120 {
                if Task.isCancelled { return }
                if TerminalSessionManager.shared.hasActiveSession(for: cardId) { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, card.deletedAt == nil else { return }
            restore()
        }
    }

    /// The `--session-name` value in a stored `ynh run` command.
    static func sessionName(inCommand command: String) -> String? {
        let parts = command.split(separator: " ")
        guard let index = parts.firstIndex(of: "--session-name"), index + 1 < parts.count else { return nil }
        return String(parts[index + 1])
    }

    /// Carries out a seat action from the Wheelhouse tab and returns the
    /// seat's card, to bring onto the stage.
    @discardableResult
    func perform(_ action: WheelhouseSeatAction, seat: WheelhouseSeat, in wheelhouse: Wheelhouse) -> UUID? {
        switch action {
        case .open:
            return launchSeat(seat, in: wheelhouse)
        case .focus(let focus):
            return launchSeat(seat, in: wheelhouse, focus: focus)
        case .handoff:
            guard let card = seatCard(seat, in: wheelhouse) else { return nil }
            send(Self.handoffRequest, toCard: card.id)
            return card.id
        case .birth:
            return launchSeat(seat, in: wheelhouse, prompt: Self.birthPrompt)
        case .harnessDetails:
            showHarnessDetails(for: seat, in: wheelhouse)
            return nil
        case .closeTerminal:
            guard let card = seatCard(seat, in: wheelhouse) else { return nil }
            boardViewModel.killSession(for: card)
            boardViewModel.deleteTabCard(card)
            return card.id
        }
    }

    /// Opens the harness detail page for a seat's harness, refreshing the
    /// installed harnesses first if it isn't among them yet.
    private func showHarnessDetails(for seat: WheelhouseSeat, in wheelhouse: Wheelhouse) {
        seatDetailContext = SeatDetailContext(wheelhouse: wheelhouse, seat: seat)
        let find = { [harnessRepo] in harnessRepo.harnesses.first { $0.name == seat.command } }
        if let harness = find() {
            harnessRepo.selectedHarnessId = harness.id
            return
        }
        Task { [harnessRepo] in
            await harnessRepo.refresh()
            if let harness = find() { harnessRepo.selectedHarnessId = harness.id }
        }
    }

    /// The seat's card, if it has one.
    func seatCard(_ seat: WheelhouseSeat, in wheelhouse: Wheelhouse) -> TerminalCard? {
        WheelhouseCardMatcher.card(
            in: boardViewModel.allTerminals, wheelhouseRoot: wheelhouse.root, seatCommand: seat.command)
    }

    /// Types `text` into a card's running terminal and submits it. Does
    /// nothing when the card has no live terminal.
    func send(_ text: String, toCard cardId: UUID) {
        guard let terminal = TerminalSessionManager.shared.getTerminalView(for: cardId) else { return }
        terminal.send(txt: text)
        // Submit separately: TUIs treat a newline inside pasted text as part of the text.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            // Look it up again: the session may have gone in the meantime.
            TerminalSessionManager.shared.getTerminalView(for: cardId)?.send(txt: "\r")
        }
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
        // Harness cards resume on reopen/restart by default. The first launch is
        // NOT implicitly cold: YNH resumes the newest session in the working
        // directory, which could belong to someone else, so the first launch's
        // behaviour is set explicitly from the sheet's toggle (off by default).
        card.autoResumeSession = true
        card.resumeOverrideForNextLaunch = config.resumeSession
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
        // A rewrite carries new intent (focus/prompt), so it starts cold unless
        // the config explicitly asks to resume.
        card.resumeOverrideForNextLaunch = config.resumeSession

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
        seatDetailContext = nil
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
