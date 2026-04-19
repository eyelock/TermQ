import Foundation

enum GitURLHelper {
    /// Returns a browser-openable URL for a git source reference.
    ///
    /// `source` is expected in `host/org/repo` form (no scheme).
    static func browserURL(for source: String, path: String? = nil) -> URL? {
        guard !source.hasPrefix("/"), !source.hasPrefix(".") else { return nil }
        var urlString = "https://\(source)"
        if let path, !path.isEmpty {
            urlString += "/tree/HEAD/\(path)"
        }
        return URL(string: urlString)
    }

    /// Strips the scheme and host from a git URL, returning `org/repo`.
    ///
    /// Accepts both `host/org/repo` and `https://host/org/repo` forms.
    static func shortURL(_ url: String) -> String {
        guard !url.hasPrefix("/"), !url.hasPrefix(".") else { return url }
        var stripped = url
        if let range = stripped.range(of: "://") { stripped = String(stripped[range.upperBound...]) }
        let parts = stripped.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : stripped
    }

    /// Extracts the GitHub (or generic git host) org/owner from a URL.
    ///
    /// Accepts `https://github.com/org/repo` and `github.com/org/repo` forms.
    /// Returns `nil` if the URL has fewer than two path components after the host.
    static func repoOwner(_ url: String) -> String? {
        var stripped = url
        if let range = stripped.range(of: "://") { stripped = String(stripped[range.upperBound...]) }
        guard let hostSlash = stripped.firstIndex(of: "/") else { return nil }
        let afterHost = String(stripped[stripped.index(after: hostSlash)...])
        if let orgSlash = afterHost.firstIndex(of: "/") {
            let org = String(afterHost[..<orgSlash])
            return org.isEmpty ? nil : org
        }
        return nil
    }
}
