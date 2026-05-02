import Foundation
import TermQShared

/// Discriminates between the kinds of "update available" signal a harness can
/// surface. Used by sidebar row and detail banner to render with different
/// visual weight depending on whether the change is maintainer-versioned (a
/// trusted bump) or content-only (a potential supply-chain warning signal).
enum HarnessUpdateSignal: Equatable {
    /// No drift detected — local matches upstream on both `version` and every
    /// include's recorded SHA.
    case none

    /// A `version` bump was published upstream. `versionAvailable` is the new
    /// version. The maintainer has explicitly signalled this update via the
    /// manifest `version` field — render with the standard "update available"
    /// affordance (orange dot, blue/orange banner).
    case versioned(versionAvailable: String?)

    /// One or more include SHAs drifted upstream WITHOUT a corresponding
    /// `version` bump. Carries the list of drifted include paths so the UI can
    /// surface "what changed" before the user proceeds. Render as a warning
    /// (amber triangle, warning banner, confirmation in the update sheet) —
    /// this is the supply-chain case where upstream content changed silently.
    case unversionedDrift(driftedIncludes: [DriftedInclude])

    struct DriftedInclude: Equatable {
        let path: String
        let installedSHA: String
        let availableSHA: String
    }
}

/// Aggregates update state for sidebar dots and detail banners.
///
/// Computes a `HarnessUpdateSignal` for each harness from the cached
/// `UpdateAvailabilityService` snapshot. The sidebar row uses the signal to
/// pick a dot/triangle and colour; the detail banner uses it to choose copy
/// and confirmation behaviour.
@MainActor
final class HarnessUpdateBadgeStore: ObservableObject {
    static let shared = HarnessUpdateBadgeStore()

    private let service: any UpdateAvailabilityService

    init(service: any UpdateAvailabilityService = LiveUpdateAvailabilityService.shared) {
        self.service = service
    }

    /// Computes the update signal for a harness. Returns `.none` when no
    /// snapshot is cached (i.e. probe hasn't run yet) — callers can fall back
    /// to the loading state from `state(for:)` for the in-flight UI hint.
    ///
    /// Three signals, in priority order:
    ///   1. `versioned` — `version_installed != version_available`. Trusted
    ///      maintainer-driven update.
    ///   2. `unversionedDrift` — harness-source SHA OR any include's SHA has
    ///      drifted upstream WITHOUT a version bump. Surfaces as a warning
    ///      because content changed silently.
    ///   3. `none` — no detectable drift.
    ///
    /// Drift only counts when both the installed and available SHAs are
    /// present and differ. Missing-side cases collapse to "no claim" rather
    /// than "drift" — we never report drift we can't prove.
    func signal(for harness: Harness) -> HarnessUpdateSignal {
        guard let snapshot = service.snapshot(forHarness: harness.id) else { return .none }
        if snapshot.hasVersionUpdate == true {
            return .versioned(versionAvailable: snapshot.versionAvailable)
        }
        var drifted: [HarnessUpdateSignal.DriftedInclude] = []

        // Harness-source drift: catches self-contained plugins (no includes).
        if snapshot.hasSourceDrift,
            let installedSHA = snapshot.installedFrom?.sha,
            let availableSHA = snapshot.shaAvailable
        {
            drifted.append(
                HarnessUpdateSignal.DriftedInclude(
                    path: snapshot.installedFrom?.path ?? snapshot.name,
                    installedSHA: installedSHA,
                    availableSHA: availableSHA
                ))
        }

        // Include-level drift: per-include SHA comparison.
        for include in snapshot.includes {
            guard let installed = include.refInstalled, !installed.isEmpty,
                let available = include.refAvailable, !available.isEmpty,
                installed != available
            else { continue }
            drifted.append(
                HarnessUpdateSignal.DriftedInclude(
                    path: include.path ?? include.git,
                    installedSHA: installed,
                    availableSHA: available
                ))
        }

        return drifted.isEmpty ? .none : .unversionedDrift(driftedIncludes: drifted)
    }

    /// Convenience for places that just need a yes/no — true for both
    /// versioned and unversioned-drift signals.
    func hasUpdate(for harness: Harness) -> Bool {
        if case .none = signal(for: harness) { return false }
        return true
    }

    /// Current update check state for a harness — used by the sidebar row to
    /// decide whether to show a loading pulse vs a dot vs nothing.
    func state(for harness: Harness) -> UpdateCheckState {
        service.state(forHarness: harness.id)
    }
}
