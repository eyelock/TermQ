import Foundation

/// Compact identifier for an existing include used to detect duplicates
/// in the Add Include flow. The match is normalized — trailing `.git` and
/// scheme casing are ignored — so users see a plugin marked
/// already-installed even when the recorded URL form differs slightly
/// from the marketplace's.
struct IncludeKey: Equatable {
    let url: String
    let path: String?

    func matches(url candidate: String, path candidatePath: String?) -> Bool {
        let lhs = Self.normalize(self.url)
        let rhs = Self.normalize(candidate)
        let lhsPath = (self.path?.isEmpty == true) ? nil : self.path
        let rhsPath = (candidatePath?.isEmpty == true) ? nil : candidatePath
        return lhs == rhs && lhsPath == rhsPath
    }

    private static func normalize(_ url: String) -> String {
        var normalized = url
        if normalized.hasSuffix(".git") { normalized.removeLast(4) }
        return normalized.lowercased()
    }
}

/// Pure helpers for matching includes to marketplace plugins. Used both to
/// detect already-installed plugins (so we can disable them in the picker)
/// and to discover the available picks for an existing include in the
/// edit sheet.
enum IncludePluginLookup {
    struct PluginMatch {
        let marketplace: Marketplace
        let plugin: MarketplacePlugin
    }

    /// Find the plugin whose `(resolvedURL, resolvedPath)` matches the
    /// given pair. Marketplace `url` comparison uses normalized git URLs
    /// to avoid trailing-`.git` mismatches.
    static func find(
        sourceURL: String,
        path: String?,
        in marketplaces: [Marketplace]
    ) -> PluginMatch? {
        let needleURL = normalize(sourceURL)
        let needlePath = (path?.isEmpty == true) ? nil : path
        for market in marketplaces {
            for plugin in market.plugins {
                let resolved = plugin.source.resolved(marketplaceURL: market.url)
                let foundURL = normalize(resolved.url)
                let foundPath = (resolved.path?.isEmpty == true) ? nil : resolved.path
                if foundURL == needleURL && foundPath == needlePath {
                    return PluginMatch(marketplace: market, plugin: plugin)
                }
            }
        }
        return nil
    }

    /// Strip a trailing `.git` suffix and normalize scheme so two URLs
    /// that only differ in `.git`/scheme casing compare equal.
    private static func normalize(_ url: String) -> String {
        var normalized = url
        if normalized.hasSuffix(".git") { normalized.removeLast(4) }
        return normalized.lowercased()
    }
}
