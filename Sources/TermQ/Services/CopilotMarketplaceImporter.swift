import Foundation

/// Reads the marketplaces configured in GitHub Copilot CLI.
///
/// Copilot CLI records marketplaces added with `copilot plugin marketplace add` in
/// `~/.copilot/settings.json` under `extraKnownMarketplaces`, keyed by marketplace name:
///
///     "extraKnownMarketplaces": {
///       "name": { "source": { "source": "github", "repo": "owner/repo" } },
///       "other": { "source": { "source": "directory", "path": "/abs/path" } }
///     }
///
/// Copilot also ships `awesome-copilot` built in; it is not written to the file, so it
/// is always included.
enum CopilotMarketplaceImporter {

    /// `~/.copilot/settings.json`, honouring `COPILOT_HOME` like the CLI does.
    static func defaultSettingsURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let home =
            environment["COPILOT_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot", isDirectory: true)
        return home.appendingPathComponent("settings.json")
    }

    /// Marketplaces Copilot CLI knows about: the built-in one plus any in `settings`.
    /// A missing or unreadable file yields just the built-in marketplace.
    static func load(from settings: URL = defaultSettingsURL()) -> [Marketplace] {
        var result = [builtIn]
        guard let data = try? Data(contentsOf: settings),
            let entries = parse(data)
        else { return result }
        for marketplace in entries where !result.contains(where: { $0.url == marketplace.url }) {
            result.append(marketplace)
        }
        return result
    }

    static let builtIn = make(
        name: "Awesome Copilot", owner: "GitHub", url: "https://github.com/github/awesome-copilot", ref: nil)

    /// Parse the JSON body of `settings.json`. Returns nil when it is not valid JSON.
    static func parse(_ data: Data) -> [Marketplace]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        guard let known = root["extraKnownMarketplaces"] as? [String: Any] else { return [] }
        return known.keys.sorted().compactMap { key in
            guard let entry = known[key] as? [String: Any],
                let source = entry["source"] as? [String: Any],
                let kind = source["source"] as? String
            else { return nil }
            let ref = (source["ref"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            switch kind {
            case "github":
                guard let repo = source["repo"] as? String, !repo.isEmpty else { return nil }
                return make(
                    name: key, owner: repo.components(separatedBy: "/").first ?? "",
                    url: "https://github.com/\(repo)", ref: ref)
            case "git", "url":
                guard let url = source["url"] as? String, !url.isEmpty else { return nil }
                return make(name: key, owner: "", url: url, ref: ref)
            case "directory", "local":
                guard let path = source["path"] as? String, !path.isEmpty else { return nil }
                return make(name: key, owner: "Local", url: path, ref: nil)
            default:
                return nil
            }
        }
    }

    private static func make(name: String, owner: String, url: String, ref: String?) -> Marketplace {
        Marketplace(
            id: UUID(), name: name, owner: owner, description: nil, vendor: .copilot,
            url: url, ref: ref, plugins: [], lastFetched: nil, fetchError: nil)
    }
}
