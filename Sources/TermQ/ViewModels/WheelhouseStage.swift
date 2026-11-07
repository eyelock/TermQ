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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let pinned = (defaults.string(forKey: Self.pinnedKey) ?? "")
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
        self.layout = WheelhouseStageLayout(pinned: pinned, focused: pinned.first)
        self.focusMode = defaults.bool(forKey: Self.focusModeKey)
    }

    var visible: [UUID] { layout.visible }
    var focused: UUID? { layout.focused }
    func isPinned(_ card: UUID) -> Bool { layout.isPinned(card) }
    func isOnStage(_ card: UUID) -> Bool { layout.isOnStage(card) }

    func show(_ card: UUID) { mutate { $0.show(card) } }
    func pin(_ card: UUID) { mutate { $0.pin(card) } }
    func unpin(_ card: UUID) { mutate { $0.unpin(card) } }
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
}
