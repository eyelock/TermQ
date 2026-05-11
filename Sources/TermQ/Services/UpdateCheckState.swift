import Foundation

/// Lifecycle state of an asynchronous update-availability check for a harness
/// or include. Drives the per-harness banner, the per-include update pill, and
/// the sidebar update dot.
///
/// The state machine has five terminal-or-transient cases:
///
/// - `idle` — no check has been run yet (e.g. on first session before the
///   detail tab is opened).
/// - `loading` — a check is in flight. UI renders a subtle pulse on the
///   banner / dot. Never blocks the detail pane.
/// - `fresh(at:)` — a check completed successfully and the cached result is
///   still considered current. The associated `Date` is the moment the cache
///   entry was populated.
/// - `stale` — a previous check succeeded but the cached result has aged out
///   (or has been invalidated by a local mutation such as a fork).
/// - `error(reason:)` — the most recent check failed. UI surfaces the reason
///   as a tooltip-on-hover; failures never block the detail pane.
enum UpdateCheckState: Equatable, Sendable {
    case idle
    case loading
    case fresh(at: Date)
    case stale
    case error(reason: String)
}
