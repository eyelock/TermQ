import Foundation

/// Checks whether the running YNH binary supports Phase 1 harness-management
/// features (update checking, fork, editability model).
///
/// Phase 1 requires `capabilities >= "0.3.0"`. The capabilities string comes
/// from the JSON envelope of any structured (`--format json`) YNH command —
/// TermQ reads it from `HarnessListResponse.capabilities` and
/// `HarnessInfoResponse.capabilities`. No separate `ynh --version` call needed.
///
/// The probe is stateless; callers pass the capabilities string they already
/// have rather than shelling out again.
struct YnhVersionProbe: Sendable {
    static let phase1Minimum = "0.3.0"

    /// Returns true when the reported capabilities version satisfies the Phase 1
    /// minimum. Nil capabilities (pre-0.3 binary) always returns false.
    static func supportsPhase1(_ capabilities: String?) -> Bool {
        guard let caps = capabilities else { return false }
        return semverAtLeast(caps, minimum: phase1Minimum)
    }

    // MARK: - Internals

    /// Simple three-part semantic version comparison. Handles the "x.y.z"
    /// pattern used by YNH capabilities strings. Treats unparseable strings
    /// as "0.0.0".
    static func semverAtLeast(_ version: String, minimum: String) -> Bool {
        func parts(_ str: String) -> [Int] {
            let comps = str.split(separator: ".").compactMap { Int($0) }
            return [
                comps.isEmpty ? 0 : comps[0],
                comps.count > 1 ? comps[1] : 0,
                comps.count > 2 ? comps[2] : 0,
            ]
        }
        let ver = parts(version)
        let min = parts(minimum)
        if ver[0] != min[0] { return ver[0] > min[0] }
        if ver[1] != min[1] { return ver[1] > min[1] }
        return ver[2] >= min[2]
    }
}
