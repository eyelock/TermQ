import Foundation

/// Harness names that TermQ treats as "defaults" in the sidebar grouping.
///
/// Harnesses matching these names appear in the Default disclosure group
/// regardless of their installation provenance. The Default group disappears
/// entirely when none of these harnesses are installed.
///
/// TermQ developers configure this list; users can remove individual entries
/// by uninstalling the harness.
enum KnownHarnesses {
    static let defaultNames: Set<String> = [
        "assistants",
        "ynh-dev",
        "termq-dev",
    ]
}
