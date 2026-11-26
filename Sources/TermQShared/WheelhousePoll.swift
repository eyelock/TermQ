import Foundation

/// How TermQ reads a Wheelhouse's work graph without crowding its seats.
///
/// A Wheelhouse's `bd` keeps its database embedded, behind one lock: every
/// `bd` call, the seats' and TermQ's, waits its turn. So TermQ reads one
/// round at a time, gives up on a read that waits too long, and reads less
/// often while `bd` is slow.
public enum WheelhousePoll {
    /// The wait between reads while `bd` answers promptly.
    public static let baseInterval: TimeInterval = 120
    /// The longest wait between reads, however slow `bd` gets.
    public static let maxInterval: TimeInterval = 600
    /// How long one `bd` read may take before it is ended.
    public static let readTimeout: TimeInterval = 20
    /// A round of reads slower than this counts as `bd` being busy.
    public static let slowRound: TimeInterval = 10

    /// The wait before the next round: doubled, up to `maxInterval`, after a
    /// round that failed or was slow; back to `baseInterval` after a prompt one.
    public static func nextInterval(after current: TimeInterval, roundTook: TimeInterval, failed: Bool) -> TimeInterval
    {
        guard failed || roundTook > slowRound else { return baseInterval }
        return min(max(current, baseInterval) * 2, maxInterval)
    }

    /// Whether a read finished at `lastRead` is old enough to read again
    /// outside the timer, as when the app comes to the front. Never read is stale.
    public static func isStale(lastRead: Date?, now: Date = Date(), maxAge: TimeInterval = baseInterval) -> Bool {
        guard let lastRead else { return true }
        return now.timeIntervalSince(lastRead) >= maxAge
    }

    /// `bd` arguments for a read: `--readonly` first, so a read can never
    /// write, whatever the subcommand does by default.
    public static func readArguments(_ arguments: [String]) -> [String] {
        ["--readonly"] + arguments
    }
}
