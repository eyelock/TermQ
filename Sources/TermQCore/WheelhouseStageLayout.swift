import Foundation

/// Which seat cards are on the Wheelhouse stage, in what order.
///
/// The stage is the pinned cards plus at most one unpinned card, the one the
/// human last brought up, side by side in the order the human arranged them.
/// With nothing pinned that is a single, full-width card. Bringing up another
/// unpinned card replaces the unpinned one in place; bringing up a pinned card
/// sends the unpinned one away. Pinned cards never give way, unless every
/// slot is pinned, when the last one does.
///
/// An anchor card, such as the inbox, is always pinned and always rightmost
/// while it is on stage, and never gives way to another card.
public struct WheelhouseStageLayout: Equatable, Sendable {
    public static let defaultMaxSlots = 3

    /// Cards on stage, left to right.
    public private(set) var cards: [UUID]
    public private(set) var pinnedSet: Set<UUID>
    public private(set) var focused: UUID?
    public let maxSlots: Int
    /// The card kept pinned at the right, when on stage.
    public let anchor: UUID?

    public init(
        pinned: [UUID] = [], visitor: UUID? = nil, focused: UUID? = nil, maxSlots: Int = defaultMaxSlots,
        anchor: UUID? = nil
    ) {
        self.maxSlots = max(1, maxSlots)
        self.anchor = anchor
        var cards: [UUID] = []
        for card in pinned where !cards.contains(card) && cards.count < self.maxSlots { cards.append(card) }
        self.pinnedSet = Set(cards)
        if let visitor, !cards.contains(visitor), cards.count < self.maxSlots { cards.append(visitor) }
        self.cards = cards
        self.focused = focused
        keepAnchorRight()
    }

    /// Pinned cards, in stage order.
    public var pinned: [UUID] { cards.filter { pinnedSet.contains($0) } }
    /// The first unpinned card on stage, if any.
    public var visitor: UUID? { cards.first { !pinnedSet.contains($0) } }
    public var visible: [UUID] { cards }

    public func isPinned(_ card: UUID) -> Bool { pinnedSet.contains(card) }
    public func isOnStage(_ card: UUID) -> Bool { cards.contains(card) }

    /// Brings `card` up and focuses it. A pinned card sends the unpinned card
    /// away; the unpinned card is just focused. Any other card takes the
    /// unpinned card's place, or a free slot, or, when every slot is pinned,
    /// the last pinned card's place.
    public mutating func show(_ card: UUID) {
        defer {
            focused = card
            keepAnchorRight()
        }
        if card == anchor {
            if !isOnStage(card) {
                if cards.count >= maxSlots,
                    let drop = cards.lastIndex(where: { !pinnedSet.contains($0) }) ?? cards.indices.last
                {
                    pinnedSet.remove(cards[drop])
                    cards.remove(at: drop)
                }
                cards.append(card)
            }
            pinnedSet.insert(card)
            return
        }
        if isPinned(card) {
            cards.removeAll { !pinnedSet.contains($0) }
            return
        }
        if visitor == card { return }
        if let index = cards.firstIndex(where: { !pinnedSet.contains($0) }) {
            cards[index] = card
        } else if cards.count < maxSlots {
            cards.append(card)
        } else if let last = cards.lastIndex(where: { $0 != anchor }) {
            pinnedSet.remove(cards[last])
            cards[last] = card
        }
        // Otherwise the only card on a full stage is the anchor: nothing gives way.
    }

    /// Pins `card`, bringing it on stage first if needed.
    public mutating func pin(_ card: UUID) {
        if !isOnStage(card) { show(card) }
        pinnedSet.insert(card)
        keepAnchorRight()
    }

    /// Unpins `card`: it stays where it is as the unpinned card, and the
    /// card that was unpinned before leaves.
    public mutating func unpin(_ card: UUID) {
        guard card != anchor, pinnedSet.remove(card) != nil else { return }
        cards.removeAll { $0 != card && !pinnedSet.contains($0) }
        if let focused, !cards.contains(focused) { self.focused = card }
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
    /// right: a drag onto a pane. An unpinned card dragged in becomes the
    /// unpinned card, so the one before it leaves; when the stage is still
    /// over full, the last card other than `card` gives way.
    public mutating func move(_ card: UUID, before target: UUID) {
        guard card != target, card != anchor, isOnStage(target) else { return }
        defer {
            focused = card
            keepAnchorRight()
        }
        let cardPinned = pinnedSet.contains(card)
        if !cardPinned, !pinnedSet.contains(target) {
            // Onto the unpinned pane: it takes that pane's place.
            cards.removeAll { $0 == card }
            if let index = cards.firstIndex(of: target) { cards[index] = card }
            return
        }
        cards.removeAll { $0 == card || (!cardPinned && !pinnedSet.contains($0)) }
        guard let index = cards.firstIndex(of: target) else { return }
        cards.insert(card, at: index)
        if cards.count > maxSlots, let drop = cards.lastIndex(where: { $0 != card && $0 != anchor }) {
            pinnedSet.remove(cards[drop])
            cards.remove(at: drop)
        }
    }

    /// Keeps the anchor pinned and rightmost while it is on stage.
    private mutating func keepAnchorRight() {
        guard let anchor, let index = cards.firstIndex(of: anchor) else { return }
        cards.remove(at: index)
        cards.append(anchor)
        pinnedSet.insert(anchor)
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
