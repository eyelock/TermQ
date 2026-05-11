import Foundation
import TermQShared

/// The editing rights for a harness, derived from its installation provenance.
///
/// Drives which controls appear in the detail pane:
/// - `fullyEditable` — all mutation controls visible (local, git-cloned, forked-to-local).
/// - `readOnly(canFork:)` — read-only with an optional "Fork to local" CTA (registry installs).
enum HarnessEditability: Equatable, Sendable {
    case fullyEditable
    case readOnly(canFork: Bool)
}

/// Resolves editing rights for a harness from its installation provenance.
///
/// Treats nil `installedFrom` as local (pre-feature installs) and unknown
/// `source_type` values as fully editable, so future YNH source types never
/// strand a user on a permanently read-only detail pane.
struct HarnessEditabilityResolver: Sendable {
    static func resolve(_ harness: Harness) -> HarnessEditability {
        switch HarnessSourceBadgeViewModel.classify(harness.installedFrom) {
        case .local, .git, .forked:
            return .fullyEditable
        case .registry:
            return .readOnly(canFork: true)
        }
    }
}
