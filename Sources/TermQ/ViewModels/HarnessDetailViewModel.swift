import Foundation
import TermQShared

/// Bundles the inputs the harness detail pane needs and exposes derived
/// view-models that the view binds against.
///
/// Built fresh by the parent (`ContentView`) on each render — it is a value
/// type so there is no lifetime to manage. The underlying observable data
/// (harness list, detail cache, update-availability service) is owned by
/// shared stores; this view-model is just a snapshot at render time.
@MainActor
struct HarnessDetailViewModel {
    let harness: Harness
    let detail: HarnessDetail?
    let isLoadingDetail: Bool
    let detailError: String?

    /// Service the view consults for per-harness and per-include update
    /// availability.
    let updateAvailability: any UpdateAvailabilityService

    /// Pure formatter for the header source badge.
    var sourceBadge: HarnessSourceBadgeViewModel {
        HarnessSourceBadgeViewModel(harness: harness)
    }

    /// Current cached update-check state for this harness as a whole.
    /// (Per-include states arrive in a later slice when the dependency list
    /// gains its update pills.)
    var harnessUpdateState: UpdateCheckState {
        updateAvailability.state(forHarness: harness.id)
    }

    /// Harness snapshot from the last successful update probe. Only non-nil
    /// when the state is `.fresh` — callers can check this without separately
    /// pattern-matching on `harnessUpdateState`.
    var updateSnapshot: Harness? {
        guard case .fresh = harnessUpdateState else { return nil }
        return updateAvailability.snapshot(forHarness: harness.id)
    }

    /// The richer update signal for this harness — used by the detail banner
    /// to choose copy and styling (versioned bump vs unversioned content
    /// drift). Mirrors the sidebar row's `signal(for:)` so banner and dot
    /// stay aligned.
    var updateSignal: HarnessUpdateSignal {
        HarnessUpdateBadgeStore(service: updateAvailability).signal(for: harness)
    }

    /// Editing rights for this harness — drives which controls appear in the
    /// detail pane (Fork CTA, Update from remote, read-only indicator).
    var editability: HarnessEditability {
        HarnessEditabilityResolver.resolve(harness)
    }

    /// True when the YNH binary supports Phase 1 features. Derived from the
    /// capabilities string reported in the last structured response.
    /// Callers hide Phase 1 affordances (update banner, fork button) when false.
    var phase1Capable: Bool {
        YnhVersionProbe.supportsPhase1(capabilities)
    }

    /// YNH capabilities string from the most recent envelope response.
    /// Injected from the harness list response so we don't need a separate probe.
    let capabilities: String?
}
