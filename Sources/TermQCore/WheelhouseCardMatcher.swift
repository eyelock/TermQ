import Foundation

/// Links Wheelhouse seats to the terminal cards they run in.
///
/// A seat launched from the Wheelhouses tab gets a card tagged
/// `wheelhouse=<root>` and `seat=<command>`. Those tags let TermQ find the
/// seat's card again after a restart or a relaunch.
public enum WheelhouseCardMatcher {
    public static let wheelhouseTagKey = "wheelhouse"
    public static let seatTagKey = "seat"
    /// A Quick Terminal opened for a seat: `seat-terminal=<command>`. Not a
    /// `seat` tag, so the card is never taken for the seat itself.
    public static let quickTerminalTagKey = "seat-terminal"
    /// The Quick Terminal's number among its seat's, shown on its badge.
    public static let quickTerminalNumberTagKey = "seat-terminal-number"

    /// Tags to put on a seat's card.
    public static func tags(wheelhouseRoot: String, seatCommand: String) -> [(key: String, value: String)] {
        [(key: wheelhouseTagKey, value: wheelhouseRoot), (key: seatTagKey, value: seatCommand)]
    }

    /// Whether `card` belongs to the seat.
    public static func matches(_ card: TerminalCard, wheelhouseRoot: String, seatCommand: String) -> Bool {
        card.deletedAt == nil
            && card.tags.contains { $0.key == wheelhouseTagKey && $0.value == wheelhouseRoot }
            && card.tags.contains { $0.key == seatTagKey && $0.value == seatCommand }
    }

    /// Whether `card` is any Wheelhouse seat's card.
    public static func isSeatCard(_ card: TerminalCard) -> Bool {
        card.tags.contains { $0.key == wheelhouseTagKey } && card.tags.contains { $0.key == seatTagKey }
    }

    /// Whether `card` is a Quick Terminal opened for a seat.
    public static func isQuickTerminal(_ card: TerminalCard) -> Bool {
        card.tags.contains { $0.key == wheelhouseTagKey } && card.tags.contains { $0.key == quickTerminalTagKey }
    }

    /// Whether `card` lives in the Wheelhouse view: a seat's card or one of
    /// its Quick Terminals.
    public static func isWheelhouseCard(_ card: TerminalCard) -> Bool {
        isSeatCard(card) || isQuickTerminal(card)
    }

    /// Tags to put on a seat's Quick Terminal.
    public static func quickTerminalTags(
        wheelhouseRoot: String, seatCommand: String, number: Int
    ) -> [(key: String, value: String)] {
        [
            (key: wheelhouseTagKey, value: wheelhouseRoot), (key: quickTerminalTagKey, value: seatCommand),
            (key: quickTerminalNumberTagKey, value: String(number)),
        ]
    }

    public static func quickTerminalNumber(_ card: TerminalCard) -> Int? {
        card.tags.first { $0.key == quickTerminalNumberTagKey }.flatMap { Int($0.value) }
    }

    /// The seat's Quick Terminals among `cards`, by number.
    public static func quickTerminals(
        in cards: [TerminalCard], wheelhouseRoot: String, seatCommand: String
    ) -> [TerminalCard] {
        cards.filter { card in
            card.deletedAt == nil
                && card.tags.contains { $0.key == wheelhouseTagKey && $0.value == wheelhouseRoot }
                && card.tags.contains { $0.key == quickTerminalTagKey && $0.value == seatCommand }
        }
        .sorted { (quickTerminalNumber($0) ?? .max) < (quickTerminalNumber($1) ?? .max) }
    }

    /// The lowest number not taken by `existing`, from 1.
    public static func nextQuickTerminalNumber(existing: [TerminalCard]) -> Int {
        let taken = Set(existing.compactMap(quickTerminalNumber))
        var number = 1
        while taken.contains(number) { number += 1 }
        return number
    }

    /// Cards for the general tab strip and the board columns: seat cards and
    /// their Quick Terminals are left out while the Wheelhouses feature is on
    /// (they live on the stage), and kept when it is off, so turning the
    /// feature off never strands a seat's terminal.
    public static func generalCards(_ cards: [TerminalCard], wheelhouseEnabled: Bool) -> [TerminalCard] {
        guard wheelhouseEnabled else { return cards }
        return cards.filter { !isWheelhouseCard($0) }
    }

    /// The seat's card, if one exists among `cards`.
    public static func card(
        in cards: [TerminalCard], wheelhouseRoot: String, seatCommand: String
    ) -> TerminalCard? {
        cards.first { matches($0, wheelhouseRoot: wheelhouseRoot, seatCommand: seatCommand) }
    }
}
