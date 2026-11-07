import Foundation

/// Links Wheelhouse seats to the terminal cards they run in.
///
/// A seat launched from the Wheelhouses tab gets a card tagged
/// `wheelhouse=<root>` and `seat=<command>`. Those tags let TermQ find the
/// seat's card again after a restart or a relaunch.
public enum WheelhouseCardMatcher {
    public static let wheelhouseTagKey = "wheelhouse"
    public static let seatTagKey = "seat"

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

    /// Cards for the general tab strip: seat cards are left out while the
    /// Wheelhouses feature is on (they live on the stage), and kept when it is
    /// off, so turning the feature off never strands a seat's terminal.
    public static func generalTabCards(_ cards: [TerminalCard], wheelhouseEnabled: Bool) -> [TerminalCard] {
        guard wheelhouseEnabled else { return cards }
        return cards.filter { !isSeatCard($0) }
    }

    /// The seat's card, if one exists among `cards`.
    public static func card(
        in cards: [TerminalCard], wheelhouseRoot: String, seatCommand: String
    ) -> TerminalCard? {
        cards.first { matches($0, wheelhouseRoot: wheelhouseRoot, seatCommand: seatCommand) }
    }
}
