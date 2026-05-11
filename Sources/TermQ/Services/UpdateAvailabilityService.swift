import Foundation
import TermQShared

/// Service that tells the UI whether an update is available for a harness or
/// any of its includes.
///
/// The real implementation lands in Track B once YNH ships the opt-in
/// `--check-updates` flag on `ynh ls` / `ynh info`. Until then,
/// `UnknownUpdateAvailabilityService` is wired in so the seam — protocol shape,
/// view-model dependency, render path — is in place and exercised end-to-end
/// against the `idle` state.
///
/// Reads are synchronous: views ask "what's the state for harness X?" and get
/// an immediate `UpdateCheckState`. Writes are async: `refresh(harness:)`
/// kicks off a check and updates the cached state when it completes.
/// Mutating actions (fork, install, include update) call `invalidate(harness:)`
/// so the dot reflects local truth immediately and reconciles on the next
/// refresh.
@MainActor
protocol UpdateAvailabilityService: AnyObject {
    /// True while a global `refreshAll` probe is in flight. Surfaces a
    /// spinner in the harness sidebar header so the user knows availability
    /// data is being recomputed.
    var isProbingAll: Bool { get }

    /// Current cached state for the named harness (id from `Harness.id`).
    func state(forHarness id: String) -> UpdateCheckState

    /// Current cached state for a specific include within a harness. The
    /// include is identified by its `git` URL (unique within a harness).
    func state(forInclude git: String, inHarness id: String) -> UpdateCheckState

    /// Latest harness snapshot from a `--check-updates` probe, carrying
    /// `version_available` and per-include `ref_available`. Returns nil when
    /// no probe has run for this harness yet.
    func snapshot(forHarness id: String) -> Harness?

    /// Trigger a fresh check for the named harness. Updates internal state
    /// and resolves when the check has settled.
    func refresh(harness id: String) async

    /// Trigger a fresh check for every installed harness in a single probe.
    /// Used when the harness list opens or the user clicks Refresh; cheaper
    /// than per-harness calls because YNH wraps everything in one
    /// `ynh ls --check-updates` invocation.
    func refreshAll() async

    /// Drop the cached state for a harness — used by mutating actions so the
    /// next read shows `stale` until the next `refresh` completes.
    func invalidate(harness id: String)
}

/// Stub implementation that reports `idle` for every harness and include.
///
/// Used in Track A while the real `--check-updates` JSON contract is shipping.
/// `idle` renders as nothing (no badge, no dot, no banner), which matches the
/// "unknown until proven otherwise" semantic in the YNH JSON contract.
@MainActor
final class UnknownUpdateAvailabilityService: UpdateAvailabilityService {
    /// Kept around for tests and previews that want a service that never
    /// reports an update. Production wires the live service.
    static let shared = UnknownUpdateAvailabilityService()

    let isProbingAll = false

    func state(forHarness id: String) -> UpdateCheckState { .idle }

    func state(forInclude git: String, inHarness id: String) -> UpdateCheckState { .idle }

    func snapshot(forHarness id: String) -> Harness? { nil }

    func refresh(harness id: String) async {}

    func refreshAll() async {}

    func invalidate(harness id: String) {}
}
