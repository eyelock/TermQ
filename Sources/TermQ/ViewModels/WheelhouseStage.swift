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
    }

    var visible: [UUID] { layout.visible }
    var focused: UUID? { layout.focused }
    func isPinned(_ card: UUID) -> Bool { layout.isPinned(card) }
    func isOnStage(_ card: UUID) -> Bool { layout.isOnStage(card) }

    func show(_ card: UUID) { mutate { $0.show(card) } }
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
    func remove(_ card: UUID) { mutate { $0.remove(card) } }
    func focus(_ card: UUID) { mutate { $0.focus(card) } }
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
    }

    /// A click landed in a stage pane's terminal. Clicking answers the pane's
    /// bell. Returns true when the pane should now be focused (it wasn't).
    func paneClicked(_ card: UUID, tabs: TabManager) -> Bool {
        guard isOnStage(card) else { return false }
        guard focused == card else { return true }
        tabs.clearAttention(card)
        return false
    }

    /// Someone typed into a stage pane's terminal: that answers its bell.
    func paneTyped(_ card: UUID, tabs: TabManager) {
        guard isOnStage(card), tabs.needsAttention.contains(card) else { return }
        tabs.clearAttention(card)
    }

    func togglePin(_ card: UUID) {
        if isPinned(card) { unpin(card) } else { pin(card) }
    }

    private func mutate(_ change: (inout WheelhouseStageLayout) -> Void) {
        var next = layout
        change(&next)
        layout = next
        defaults.set(next.pinned.map(\.uuidString).joined(separator: ","), forKey: Self.pinnedKey)
    }
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
    /// End the seat's terminal: kill its session and remove its card.
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
        board.killSession(for: card)
        board.deleteTabCard(card)
        remove(card.id)
    }
}
