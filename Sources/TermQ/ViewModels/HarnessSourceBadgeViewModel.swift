import Foundation
import TermQShared

/// Where a harness came from — drives the source badge in the detail-pane
/// header and (eventually) the editability decision.
///
/// Resolved from `Harness.installedFrom`:
///
/// - `local` — no install record (pre-feature) or `source_type == "local"`
///   without a `forked_from`. Fully editable.
/// - `git` — installed by cloning a git repo the user owns. Fully editable;
///   `Update from remote` runs `git pull`.
/// - `registry` — installed from a marketplace registry. Read-only by default;
///   primary action is `Fork to local`.
/// - `forked` — `source_type == "local"` with `forked_from` populated.
///   Editable, with a ghost origin shown in the header.
enum HarnessSource: Equatable, Sendable {
    case local
    case git
    case registry(name: String?)
    case forked(origin: ForkOrigin)
}

/// Pure formatter that maps a `Harness` to the data the source badge view
/// needs: the classified source and an SF Symbol icon. Localized labels are
/// produced by the view layer from the source case.
///
/// Keeps no state. Treats nil `installedFrom` as `.local` so pre-feature
/// installs render correctly without special-casing in the view.
struct HarnessSourceBadgeViewModel: Sendable, Equatable {
    let source: HarnessSource
    let iconSystemName: String

    init(harness: Harness) {
        self.source = Self.classify(harness.installedFrom)
        self.iconSystemName = Self.icon(for: source)
    }

    static func classify(_ provenance: HarnessProvenance?) -> HarnessSource {
        guard let provenance else { return .local }
        switch provenance.sourceType {
        case "registry":
            return .registry(name: provenance.registryName)
        case "git":
            return .git
        case "local":
            if let origin = provenance.forkedFrom {
                return .forked(origin: origin)
            }
            return .local
        default:
            // Unknown source_type from a future YNH — treat as local so we
            // don't strand the user on a read-only pane for something we
            // didn't anticipate.
            return .local
        }
    }

    private static func icon(for source: HarnessSource) -> String {
        switch source {
        case .local: return "folder"
        case .git: return "arrow.triangle.branch"
        case .registry: return "storefront"
        case .forked: return "tuningfork"
        }
    }
}
