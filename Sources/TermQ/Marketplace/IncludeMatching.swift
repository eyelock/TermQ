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
        let lhs = GitURLNormalizer.normalize(self.url)
        let rhs = GitURLNormalizer.normalize(candidate)
        let lhsPath = (self.path?.isEmpty == true) ? nil : self.path
        let rhsPath = (candidatePath?.isEmpty == true) ? nil : candidatePath
        return lhs == rhs && lhsPath == rhsPath
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
    /// given pair. Marketplace `url` comparison uses `GitURLNormalizer`
    /// to bridge the various ways YNH and TermQ record the same git URL
    /// (short / host-prefixed / scheme-prefixed / `.git`-suffixed / SSH).
    static func find(
        sourceURL: String,
        path: String?,
        in marketplaces: [Marketplace]
    ) -> PluginMatch? {
        let needleURL = GitURLNormalizer.normalize(sourceURL)
        let needlePath = (path?.isEmpty == true) ? nil : path
        for market in marketplaces {
            for plugin in market.plugins {
                let resolved = plugin.source.resolved(marketplaceURL: market.url)
                let foundURL = GitURLNormalizer.normalize(resolved.url)
                let foundPath = (resolved.path?.isEmpty == true) ? nil : resolved.path
                if foundURL == needleURL && foundPath == needlePath {
                    return PluginMatch(marketplace: market, plugin: plugin)
                }
            }
        }
        return nil
    }
}

/// Normalize git URLs to a single host-prefixed, suffix-stripped form so
/// the various recording conventions YNH and TermQ each use compare equal.
///
/// All of these normalize to `github.com/eyelock/assistants`:
///   - `eyelock/assistants`                 (short, after registry shortening)
///   - `github.com/eyelock/assistants`      (host-prefixed, YNH ls format)
///   - `https://github.com/eyelock/assistants`
///   - `https://github.com/eyelock/assistants.git`
///   - `git@github.com:eyelock/assistants.git`
enum GitURLNormalizer {
    static func normalize(_ url: String) -> String {
        var normalized = url.lowercased()
        for prefix in ["https://", "http://", "git+ssh://", "ssh://"]
        where normalized.hasPrefix(prefix) {
            normalized.removeFirst(prefix.count)
            break
        }
        // SSH alt form: git@host:owner/repo → host/owner/repo
        if normalized.hasPrefix("git@") {
            normalized.removeFirst(4)
            if let colon = normalized.firstIndex(of: ":") {
                normalized.replaceSubrange(colon...colon, with: "/")
            }
        }
        if normalized.hasSuffix(".git") { normalized.removeLast(4) }
        if normalized.hasSuffix("/") { normalized.removeLast() }
        // Drop well-known host so short URLs (post host-strip from registry)
        // match host-prefixed URLs (from YNH ls).
        for host in ["github.com/", "gitlab.com/", "bitbucket.org/"]
        where normalized.hasPrefix(host) {
            normalized.removeFirst(host.count)
            break
        }
        return normalized
    }
}
