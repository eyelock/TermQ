import Foundation

/// Which seat cards are on the Wheelhouse stage, in what order.
///
/// The stage shows up to `maxSlots` cards side by side, in the order the human
/// arranged them. Pinned cards stay: bringing in another card replaces the
/// last unpinned one, in place, never a pinned card (unless every slot is
/// pinned, when the last one gives way).
public struct WheelhouseStageLayout: Equatable, Sendable {
    public static let defaultMaxSlots = 3

    /// Cards on stage, left to right.
    public private(set) var cards: [UUID]
    public private(set) var pinnedSet: Set<UUID>
    public private(set) var focused: UUID?
    public let maxSlots: Int

    public init(pinned: [UUID] = [], visitor: UUID? = nil, focused: UUID? = nil, maxSlots: Int = defaultMaxSlots) {
        self.maxSlots = max(1, maxSlots)
        var cards: [UUID] = []
        for card in pinned where !cards.contains(card) && cards.count < self.maxSlots { cards.append(card) }
        self.pinnedSet = Set(cards)
        if let visitor, !cards.contains(visitor), cards.count < self.maxSlots { cards.append(visitor) }
        self.cards = cards
        self.focused = focused
    }

    /// Pinned cards, in stage order.
    public var pinned: [UUID] { cards.filter { pinnedSet.contains($0) } }
    /// The first unpinned card on stage, if any.
    public var visitor: UUID? { cards.first { !pinnedSet.contains($0) } }
    public var visible: [UUID] { cards }

    public func isPinned(_ card: UUID) -> Bool { pinnedSet.contains(card) }
    public func isOnStage(_ card: UUID) -> Bool { cards.contains(card) }

    /// Brings `card` onto the stage and focuses it. A card already on stage is
    /// just focused. With a free slot it goes on the end; otherwise it takes
    /// the place of the last unpinned card (or the last card, if all are pinned).
    public mutating func show(_ card: UUID) {
        defer { focused = card }
        if isOnStage(card) { return }
        if cards.count < maxSlots {
            cards.append(card)
        } else {
            let index = cards.lastIndex { !pinnedSet.contains($0) } ?? cards.count - 1
            pinnedSet.remove(cards[index])
            cards[index] = card
        }
    }

    /// Pins `card`, bringing it on stage first if needed.
    public mutating func pin(_ card: UUID) {
        if !isOnStage(card) { show(card) }
        pinnedSet.insert(card)
    }

    /// Unpins `card`; it stays where it is on stage.
    public mutating func unpin(_ card: UUID) {
        pinnedSet.remove(card)
    }

    /// Takes `card` off the stage entirely.
    public mutating func remove(_ card: UUID) {
        cards.removeAll { $0 == card }
        pinnedSet.remove(card)
        if focused == card { focused = cards.first }
    }

    public mutating func focus(_ card: UUID) {
        guard isOnStage(card) else { return }
        focused = card
    }

    /// Puts `card` in `target`'s place, shifting `target` and those after it
    /// right: a drag onto a pane. A card not yet on stage comes on; when that
    /// overflows, the last unpinned card other than `card` leaves.
    public mutating func move(_ card: UUID, before target: UUID) {
        guard card != target, isOnStage(target) else { return }
        cards.removeAll { $0 == card }
        let index = cards.firstIndex(of: target) ?? cards.count
        cards.insert(card, at: index)
        if cards.count > maxSlots {
            let drop =
                cards.lastIndex { $0 != card && !pinnedSet.contains($0) }
                ?? cards.lastIndex { $0 != card } ?? cards.count - 1
            pinnedSet.remove(cards[drop])
            cards.remove(at: drop)
        }
        focused = card
    }

    /// Drops cards that no longer exist.
    public mutating func prune(keeping existing: Set<UUID>) {
        cards.removeAll { !existing.contains($0) }
        pinnedSet = pinnedSet.filter { existing.contains($0) }
        if let focused, !existing.contains(focused) { self.focused = cards.first }
    }
}

/// Orders the seats that need the human: oldest bell first.
public enum WheelhouseAttention {
    /// Cards from `candidates` that rang (have a time in `since`) and are not
    /// in `excluding`, oldest first; ties keep `candidates` order.
    public static func queue(candidates: [UUID], since: [UUID: Date], excluding: Set<UUID> = []) -> [UUID] {
        struct Entry {
            let card: UUID
            let time: Date
            let order: Int
        }
        return candidates.enumerated()
            .compactMap { offset, card -> Entry? in
                guard !excluding.contains(card), let time = since[card] else { return nil }
                return Entry(card: card, time: time, order: offset)
            }
            .sorted { lhs, rhs in lhs.time != rhs.time ? lhs.time < rhs.time : lhs.order < rhs.order }
            .map(\.card)
    }
}
