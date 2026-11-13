import Foundation

/// Splits installed harnesses into each Wheelhouse's seat harnesses and the
/// rest, so the Harnesses list can keep seats in their own group instead of
/// mixing them in with everything else.
public enum WheelhouseHarnessGrouping {
    /// One Wheelhouse and the installed harnesses its seats run, in the
    /// order `harnesses` lists them.
    public struct SeatGroup: Equatable, Sendable {
        public let wheelhouse: Wheelhouse
        public let harnesses: [Harness]
    }

    /// A seat's harness is the one whose name is the seat's command. A
    /// harness several Wheelhouses share goes to the first of them, so it is
    /// listed once. Wheelhouses with no installed seat harness get no group.
    public static func split(
        _ harnesses: [Harness], wheelhouses: [Wheelhouse]
    ) -> (seatGroups: [SeatGroup], others: [Harness]) {
        var owner: [String: Int] = [:]
        for (index, wheelhouse) in wheelhouses.enumerated() {
            for seat in wheelhouse.seats where owner[seat.command] == nil {
                owner[seat.command] = index
            }
        }
        var grouped = Array(repeating: [Harness](), count: wheelhouses.count)
        var others: [Harness] = []
        for harness in harnesses {
            if let index = owner[harness.name] {
                grouped[index].append(harness)
            } else {
                others.append(harness)
            }
        }
        let seatGroups = zip(wheelhouses, grouped)
            .filter { !$0.1.isEmpty }
            .map { SeatGroup(wheelhouse: $0.0, harnesses: $0.1) }
        return (seatGroups, others)
    }

    /// The Wheelhouse whose group lists `harness`, if any.
    public static func wheelhouse(of harness: Harness, in wheelhouses: [Wheelhouse]) -> Wheelhouse? {
        wheelhouses.first { $0.seats.contains { $0.command == harness.name } }
    }
}
