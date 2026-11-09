import Foundation
import TermQCore
import TermQShared

/// The Wheelhouse stage: which seat cards are side by side in the main panel,
/// and whether Wheelhouse focus mode is on.
@MainActor
final class WheelhouseStage: ObservableObject {
    static let shared = WheelhouseStage()

    static let focusModeKey = "wheelhouse.focusMode"
    private static let pinnedKey = "wheelhouse.stage.pinned"

    @Published private(set) var layout: WheelhouseStageLayout
    @Published var focusMode: Bool {
        didSet { defaults.set(focusMode, forKey: Self.focusModeKey) }
    }

    static let quickTerminalPlacementKey = "wheelhouse.quickTerminalPlacement"

    /// Where Quick Terminals open: a setting in Settings' Wheelhouses section.
    @Published var quickTerminalPlacement: WheelhouseQuickTerminalPlacement {
        didSet { defaults.set(quickTerminalPlacement.rawValue, forKey: Self.quickTerminalPlacementKey) }
    }

    /// Split placement, per seat card: the Quick Terminal its panel shows,
    /// whether the panel is collapsed, and the panel's share of the height.
    @Published private(set) var splitSelected: [UUID: UUID] = [:]
    @Published private(set) var splitCollapsed: Set<UUID> = []
    @Published private(set) var splitFraction: [UUID: CGFloat] = [:]
    static let defaultSplitFraction: CGFloat = 0.35

    static let selectedRootKey = "wheelhouse.selected"

    /// The Wheelhouse picked in the sidebar, or "" for all of them.
    @Published var selectedRoot: String {
        didSet { defaults.set(selectedRoot, forKey: Self.selectedRootKey) }
    }

    /// The pane zoomed to fill the window (⌥⌘Z), if any. Not persisted: a
    /// relaunch comes back to the whole stage.
    @Published private(set) var zoomed: UUID?

    /// Cards whose close-out check is under way.
    private var closing: Set<UUID> = []

    /// ⌥⌘Z: zoom the focused pane, or come back to the whole stage. The inbox
    /// isn't zoomed.
    func toggleZoom() {
        if zoomed != nil {
            zoomed = nil
        } else if let card = focused, card != Self.inboxEntry {
            zoom(card)
        }
    }

    /// Zoom `card`'s pane, focusing it.
    func zoom(_ card: UUID) {
        guard card != Self.inboxEntry else { return }
        show(card)
        zoomed = card
    }

    func exitZoom() { zoomed = nil }

    /// Drops a zoom whose pane is no longer among `visible` (closed, or out of
    /// the Wheelhouse in view), so the stage never stays half-zoomed.
    func healZoom(visible: Set<UUID>) {
        if let zoomed, !visible.contains(zoomed) || !isOnStage(zoomed) { self.zoomed = nil }
    }

    /// The general terminal selected when the stage came up, to return to
    /// when it goes away. Not published: only read on that change.
    var cardBeforeStage: UUID?

    /// Pane weights by slot: a pinned card's own id, or `unpinnedSlot` for
    /// whichever unpinned card is up, so a split survives the visitor changing.
    @Published private(set) var paneWeights: [UUID: CGFloat] = [:]
    nonisolated static let unpinnedSlot = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xF0, 0x0D))

    func slot(for card: UUID) -> UUID { isPinned(card) ? card : Self.unpinnedSlot }

    func weight(for card: UUID) -> CGFloat {
        paneWeights[slot(for: card)] ?? WheelhousePaneSizing.defaultWeight
    }

    func setWeights(_ left: (card: UUID, weight: CGFloat), _ right: (card: UUID, weight: CGFloat)) {
        paneWeights[slot(for: left.card)] = left.weight
        paneWeights[slot(for: right.card)] = right.weight
    }

    /// Back to equal widths.
    func resetWeights() { paneWeights = [:] }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let pinned = (defaults.string(forKey: Self.pinnedKey) ?? "")
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
        self.layout = WheelhouseStageLayout(pinned: pinned, focused: pinned.first, anchor: Self.inboxEntry)
        self.focusMode = defaults.bool(forKey: Self.focusModeKey)
        self.selectedRoot = defaults.string(forKey: Self.selectedRootKey) ?? ""
        self.quickTerminalPlacement =
            defaults.string(forKey: Self.quickTerminalPlacementKey).flatMap(WheelhouseQuickTerminalPlacement.init)
            ?? .staged
    }

    // MARK: - Quick Terminal placement

    /// Shows a seat's Quick Terminal where the setting says: its own place on
    /// the stage, or (split) the panel beneath its seat's pane, which comes on
    /// stage with the panel open on it. Split falls back to staged when the
    /// seat has no terminal to sit beneath.
    func showQuickTerminal(_ quick: UUID, seatCard: UUID?) {
        guard quickTerminalPlacement == .split, let seatCard else {
            show(quick)
            return
        }
        splitSelected[seatCard] = quick
        splitCollapsed.remove(seatCard)
        show(seatCard)
    }

    /// The Quick Terminal a seat's panel shows among `quick` (the seat's
    /// open ones, in order): the one picked, else the first.
    func splitQuickTerminal(for seatCard: UUID, among quick: [UUID]) -> UUID? {
        if let picked = splitSelected[seatCard], quick.contains(picked) { return picked }
        return quick.first
    }

    func selectSplitQuickTerminal(_ quick: UUID, for seatCard: UUID) {
        splitSelected[seatCard] = quick
        splitCollapsed.remove(seatCard)
    }

    func toggleSplitCollapsed(_ seatCard: UUID) {
        if splitCollapsed.contains(seatCard) {
            splitCollapsed.remove(seatCard)
        } else {
            splitCollapsed.insert(seatCard)
        }
    }

    func splitFraction(for seatCard: UUID) -> CGFloat {
        splitFraction[seatCard] ?? Self.defaultSplitFraction
    }

    /// The panel's share of the pane's height, kept between a fifth and four
    /// fifths so neither terminal disappears.
    func setSplitFraction(_ fraction: CGFloat, for seatCard: UUID) {
        splitFraction[seatCard] = min(0.8, max(0.2, fraction))
    }

    /// The Wheelhouse whose seats the stage shows: the one picked, else the
    /// first in focus mode, else nil for all of them.
    func scopeRoot(in wheelhouses: [Wheelhouse]) -> String? {
        Self.scopeRoot(selected: selectedRoot, focusMode: focusMode, wheelhouses: wheelhouses)
    }

    nonisolated static func scopeRoot(selected: String, focusMode: Bool, wheelhouses: [Wheelhouse]) -> String? {
        if !selected.isEmpty, wheelhouses.contains(where: { $0.root == selected }) { return selected }
        return focusMode ? wheelhouses.first?.root : nil
    }

    var visible: [UUID] { layout.visible }
    var focused: UUID? { layout.focused }
    func isPinned(_ card: UUID) -> Bool { layout.isPinned(card) }
    func isOnStage(_ card: UUID) -> Bool { layout.isOnStage(card) }

    /// Brings `card` on stage and focuses it. Asking for another pane while
    /// one is zoomed comes back to the whole stage.
    func show(_ card: UUID) {
        if let zoomed, zoomed != card { self.zoomed = nil }
        mutate { $0.show(card) }
    }
    /// Pinning or unpinning keeps the pane's width: its weight moves with it
    /// between the unpinned slot and the card's own.
    func pin(_ card: UUID) {
        let weight = isOnStage(card) && !isPinned(card) ? paneWeights[Self.unpinnedSlot] : nil
        mutate { $0.pin(card) }
        if let weight { paneWeights[card] = weight }
    }
    func unpin(_ card: UUID) {
        let weight = paneWeights.removeValue(forKey: card)
        mutate { $0.unpin(card) }
        paneWeights[Self.unpinnedSlot] = weight
    }
    func remove(_ card: UUID) {
        if zoomed == card { zoomed = nil }
        mutate { $0.remove(card) }
    }
    /// Focusing another pane while one is zoomed comes back to the whole stage.
    func focus(_ card: UUID) {
        if let zoomed, zoomed != card { self.zoomed = nil }
        mutate { $0.focus(card) }
    }
    func move(_ card: UUID, before target: UUID) { mutate { $0.move(card, before: target) } }

    /// Drag payload for a seat card, so a drop can tell it from other strings.
    static func dragPayload(_ card: UUID) -> String { "wheelhouse-seat:" + card.uuidString }
    static func card(fromDragPayload payload: String) -> UUID? {
        guard payload.hasPrefix("wheelhouse-seat:") else { return nil }
        return UUID(uuidString: String(payload.dropFirst("wheelhouse-seat:".count)))
    }
    func prune(keeping existing: Set<UUID>) {
        let before = layout
        var next = layout
        next.prune(keeping: existing)
        if next != before { mutate { $0 = next } }
        if let zoomed, !next.isOnStage(zoomed) { self.zoomed = nil }
    }

    /// A click landed in a stage terminal: a pane's, or (Split) a Quick
    /// Terminal's beneath its seat `host`. Clicking answers that terminal's
    /// bell. Returns the pane to focus when it isn't focused yet.
    func paneClicked(_ card: UUID, host: UUID? = nil, tabs: TabManager) -> UUID? {
        let pane = isOnStage(card) ? card : host.flatMap { isOnStage($0) ? $0 : nil }
        guard let pane else { return nil }
        if pane != card || focused == pane { tabs.clearAttention(card) }
        return focused == pane ? nil : pane
    }

    /// Someone typed into a stage terminal (a pane's, or a split Quick
    /// Terminal's beneath `host`): that answers its bell.
    func paneTyped(_ card: UUID, host: UUID? = nil, tabs: TabManager) {
        guard isOnStage(card) || host.map(isOnStage) == true, tabs.needsAttention.contains(card) else { return }
        tabs.clearAttention(card)
    }

    /// After switching to Split: each Quick Terminal on stage whose seat has
    /// a card (`hostOf`) moves into that seat's panel, and its place goes.
    func moveQuickTerminalsIntoPanels(hostOf: (UUID) -> UUID?) {
        guard quickTerminalPlacement == .split else { return }
        for card in visible {
            guard let host = hostOf(card) else { continue }
            let wasFocused = focused == card
            splitSelected[host] = card
            remove(card)
            if wasFocused || !isOnStage(host) { show(host) }
        }
    }

    func togglePin(_ card: UUID) {
        if isPinned(card) { unpin(card) } else { pin(card) }
    }

    /// ⌘P: keep the focused pane on stage, or stop keeping it. The inbox is
    /// not pinned.
    func togglePinFocused() {
        guard let card = focused, card != Self.inboxEntry else { return }
        togglePin(card)
    }

    private func mutate(_ change: (inout WheelhouseStageLayout) -> Void) {
        var next = layout
        change(&next)
        layout = next
        defaults.set(next.pinned.map(\.uuidString).joined(separator: ","), forKey: Self.pinnedKey)
    }
}

/// Where a seat's Quick Terminals open on the stage.
enum WheelhouseQuickTerminalPlacement: String, CaseIterable, Sendable {
    /// Each takes its own place on the stage, like a seat.
    case staged
    /// In a panel beneath the seat's own pane.
    case split
}

/// Something the human asks of a seat from the Wheelhouse tab.
enum WheelhouseSeatAction: Equatable {
    /// Open the seat: its terminal if it has one, else a launch.
    case open
    /// Run one of the seat's harness focuses.
    case focus(WheelhouseFocus)
    /// Ask the seat to take a beat and hand off.
    case handoff
    /// Start the seat's first session with the birth skill.
    case birth
    /// Close the seat's terminal: a seat whose harness still runs only leaves
    /// the stage; one whose harness has exited is closed out (its session
    /// killed and its card removed), so the next open launches it afresh.
    case closeTerminal
    /// Show the seat's ynh harness on the harness detail page, to read or edit it.
    case harnessDetails
    /// Open a plain shell for the seat, where the seat is working. It does not
    /// start or touch the seat's own session.
    case quickTerminal
    /// Type a message into the seat's session (starting it if needed), such
    /// as a bead handed over from the human's inbox. The stage is left as is.
    case send(String)
}

extension WheelhouseStage {
    /// The inbox's place on the stage: it takes a slot like a card does.
    nonisolated static let inboxEntry = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x1B, 0x0C))

    /// Ends a seat's Quick Terminal: kills its shell and removes its card.
    func closeQuickTerminal(_ card: TerminalCard, board: BoardViewModel = .shared) {
        closeOut(card, board: board)
    }

    /// What closing a stage terminal does.
    enum CloseDecision: Equatable {
        /// Something still runs in it (or it can't be told): it only leaves
        /// the stage, so a needed session is never killed by a close.
        case takeOffStage
        /// Nothing but the shell is left: kill it and remove the card.
        case closeOut
    }

    nonisolated static func closeDecision(harnessRunning: Bool?) -> CloseDecision {
        harnessRunning == false ? .closeOut : .takeOffStage
    }

    /// The pane's ✕ and Close Terminal: the card leaves the stage at once, and
    /// is closed out too if nothing but its shell is running.
    func smartClose(_ card: TerminalCard, board: BoardViewModel = .shared) {
        remove(card.id)
        Task { @MainActor in
            await closeOutIfIdle(card, probe: TerminalSessionManager.shared) { self.closeOut($0, board: board) }
        }
    }

    /// Closes the card out when the probe finds only its shell, and only if
    /// it is still the same session afterwards: a reopen or restart while the
    /// probe ran must not be killed by an answer about the old session. One
    /// check per card at a time. Returns whether it closed the card out.
    @discardableResult
    func closeOutIfIdle(
        _ card: TerminalCard, probe: any TerminalForegroundProbing, closeOut: (TerminalCard) -> Void
    ) async -> Bool {
        guard !closing.contains(card.id) else { return false }
        closing.insert(card.id)
        defer { closing.remove(card.id) }
        let session = probe.sessionStart(for: card.id)
        let running = await probe.isForegroundProgramRunning(for: card)
        guard Self.closeDecision(harnessRunning: running) == .closeOut,
            card.deletedAt == nil, probe.sessionStart(for: card.id) == session
        else { return false }
        closeOut(card)
        return true
    }

    /// Kills the card's session and removes the card and its pane.
    func closeOut(_ card: TerminalCard, board: BoardViewModel = .shared) {
        board.killSession(for: card)
        board.deleteTabCard(card)
        remove(card.id)
    }
}
