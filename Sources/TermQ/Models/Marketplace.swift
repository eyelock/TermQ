import Foundation

// MARK: - Top-level

struct Marketplace: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var owner: String
    var description: String?
    var vendor: MarketplaceVendor
    var url: String
    /// Optional git ref (branch name, tag, or full/abbreviated SHA) to pin fetches to.
    /// nil → always fetch latest HEAD.
    var ref: String?
    var plugins: [MarketplacePlugin]
    var lastFetched: Date?
    var fetchError: String?
    /// Optional subfolder of the repository (or local folder) that holds the marketplace index.
    /// nil/blank → the top level. Relative plugin sources resolve against this folder.
    var folder: String?
    /// User-assigned label. Survives refreshes, which overwrite `name` with the index's own name.
    var customName: String?

    /// Name shown in the UI: the user's label, else the index name, else the short repo path.
    var displayName: String {
        if let custom = customName?.trimmingCharacters(in: .whitespaces), !custom.isEmpty { return custom }
        if !name.isEmpty { return name }
        if isLocal { return URL(fileURLWithPath: localPath).lastPathComponent }
        return GitURLHelper.shortURL(url)
    }

    /// Filesystem path for a local marketplace (strips a `file://` prefix).
    var localPath: String { url.hasPrefix("file:///") ? String(url.dropFirst(7)) : url }

    /// `folder` with surrounding whitespace/slashes removed; nil when blank.
    var normalizedFolder: String? { Self.normalizeFolder(folder) }

    static func normalizeFolder(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("./") { trimmed = String(trimmed.dropFirst(2)) }
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Refuse parent-directory segments so a folder can never escape the repository root.
        if trimmed.split(separator: "/").contains("..") { return nil }
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Turns the shorthand people paste (`owner/repo`, `github.com/owner/repo`) into a URL git can
    /// clone. Anything with a scheme, an scp-style `git@host:` form, or a local path is left alone.
    static func normalizeRepoURL(_ raw: String) -> String {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty || url.contains("://") || url.hasPrefix("git@") || url.hasPrefix("/")
            || url.hasPrefix("~")
        {
            return url
        }
        if url.hasPrefix("github.com/") || url.hasPrefix("www.github.com/") { return "https://" + url }
        let parts = url.split(separator: "/", omittingEmptySubsequences: false)
        let slug = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        if parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(slug.contains) }) {
            return "https://github.com/\(url)"
        }
        return url
    }

    /// True when this marketplace points to a local folder rather than a remote Git repository.
    var isLocal: Bool { url.hasPrefix("/") || url.hasPrefix("file:///") }

    /// True when `ref` is a commit SHA (40 hex chars or a 7-40 char hex abbreviation).
    /// Branch/tag refs are mutable; SHAs are immutable — truly pinned.
    var isPinnedToSHA: Bool {
        guard let ref else { return false }
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return ref.count >= 7 && ref.count <= 40
            && ref.unicodeScalars.allSatisfy { hex.contains($0) }
    }
}

enum MarketplaceVendor: String, Codable, Sendable, CaseIterable {
    case claude
    case cursor
    case copilot

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        case .copilot: return "Copilot"
        }
    }

    /// Relative path to the marketplace index inside the cloned repo.
    var indexPath: String { indexPaths[0] }

    /// Candidate index locations, in lookup order. Copilot CLI also reads the Claude layout.
    var indexPaths: [String] {
        switch self {
        case .claude: return [".claude-plugin/marketplace.json"]
        case .cursor: return [".cursor-plugin/marketplace.json"]
        case .copilot: return [".github/plugin/marketplace.json", ".claude-plugin/marketplace.json"]
        }
    }
}

// MARK: - Plugin

struct MarketplacePlugin: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var description: String?
    var version: String?
    var category: String?
    var tags: [String]
    var source: PluginSourceSpec
    var picks: [String]  // artifact paths selectable via --pick (e.g. "skills/foo", "agents/bar")
    var skillsState: SkillsLoadState
}

// MARK: - Source spec

struct PluginSourceSpec: Codable, Sendable {
    var type: PluginSourceType
    var url: String  // relative path ("./plugins/foo") or external URL
    var path: String?  // optional subdirectory within the source

    init(type: PluginSourceType, url: String, path: String? = nil) {
        self.type = type
        self.url = url
        self.path = path
    }

    // The vendor marketplace.json `source` field may be a plain string (relative path)
    // or a JSON object. The object uses "source" as the type discriminator key (not "type").
    init(from decoder: Decoder) throws {
        if let str = try? decoder.singleValueContainer().decode(String.self) {
            // A bare string is a path inside the marketplace repo ("./plugins/x", or "plugins/x" as
            // Copilot's index writes it) unless it is clearly a remote URL.
            let isRemote = str.contains("://") || str.hasPrefix("git@") || str.hasPrefix("github.com/")
            self.type = isRemote ? .url : .relative
            self.url = str
            self.path = nil
            return
        }
        // Object form from vendor JSON: {"source": "github", "url": "..."}
        // Object form from TermQ persistence: {"type": "github", "url": "..."}

        let container = try decoder.container(keyedBy: RawSourceCodingKeys.self)
        let typeStr =
            (try? container.decode(String.self, forKey: .source))
            ?? (try? container.decode(String.self, forKey: .type))
            ?? ""
        self.type = PluginSourceType(rawValue: typeStr) ?? .unknown
        if self.type == .github, let repo = try? container.decode(String.self, forKey: .repo) {
            self.url = "https://github.com/\(repo)"
        } else {
            self.url = (try? container.decode(String.self, forKey: .url)) ?? ""
        }
        self.path = try? container.decode(String.self, forKey: .path)
    }

    private enum RawSourceCodingKeys: String, CodingKey {
        case source, type, url, path, repo
    }
}

extension PluginSourceSpec {
    /// Resolves the effective `(url, path)` pair for `ynh include add`.
    ///
    /// Relative-source plugins live inside the marketplace repo, so the correct
    /// source URL is the marketplace git URL, not the relative path stored in
    /// the plugin spec (which is meaningless as a standalone git URL to YNH).
    func resolved(marketplaceURL: String, folder: String? = nil) -> (url: String, path: String?) {
        // Also catch persisted entries where type was corrupted to .unknown due to
        // the "source" vs "type" key mismatch in the old decoder.
        guard type.isRelative || url.hasPrefix("./") else {
            if type == .github {
                let expanded: String
                if url.hasPrefix("http") || url.hasPrefix("github.com/") {
                    expanded = url
                } else {
                    expanded = "github.com/\(url)"
                }
                return (expanded, path)
            }
            return (url, path)
        }
        let rawPath = url.hasPrefix("./") ? String(url.dropFirst(2)) : url
        var fullPath = path.map { "\(rawPath)/\($0)" } ?? rawPath
        if let folder = Marketplace.normalizeFolder(folder) {
            fullPath = fullPath.isEmpty ? folder : "\(folder)/\(fullPath)"
        }
        return (marketplaceURL, fullPath.isEmpty ? nil : fullPath)
    }
}

enum PluginSourceType: String, Codable, Sendable {
    case relative
    case github
    case url
    case npm
    case gitSubdir = "git-subdir"
    case unknown

    var isRelative: Bool { self == .relative }
    var isExternal: Bool { !isRelative && self != .unknown }
}

// MARK: - Skills load state

enum SkillsLoadState: Codable, Sendable, Equatable {
    case eager  // fully enumerated from the marketplace clone
    case pending  // external source — not yet cloned
    case loading  // clone in progress
    case failed(String)
    /// Recognised content TermQ/ynh cannot add (e.g. a Copilot "extensions" plugin). Holds the type name.
    case unsupported(String)

    private enum CodingKeys: String, CodingKey { case type, message }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "pending"
        switch type {
        case "eager": self = .eager
        case "failed":
            let msg = (try? container.decode(String.self, forKey: .message)) ?? ""
            self = .failed(msg)
        case "unsupported":
            let kind = (try? container.decode(String.self, forKey: .message)) ?? ""
            self = .unsupported(kind)
        default: self = .pending
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .eager:
            try container.encode("eager", forKey: .type)
        case .pending, .loading:
            // Don't persist transient loading state; restart as pending.
            try container.encode("pending", forKey: .type)
        case .failed(let msg):
            try container.encode("failed", forKey: .type)
            try container.encode(msg, forKey: .message)
        case .unsupported(let kind):
            try container.encode("unsupported", forKey: .type)
            try container.encode(kind, forKey: .message)
        }
    }

    var isResolved: Bool {
        switch self {
        case .eager, .failed, .unsupported: return true
        default: return false
        }
    }
}

// MARK: - Raw JSON model for marketplace index parsing

/// Raw plugin entry decoded directly from the vendor marketplace.json.
/// TermQ maps this into `MarketplacePlugin` after enumeration.
struct RawMarketplacePlugin: Decodable, Sendable {
    let name: String
    let description: String?
    let version: String?
    let category: String?
    let tags: [String]?
    let source: PluginSourceSpec?

    enum CodingKeys: String, CodingKey {
        case name, description, version, category, tags, source
    }
}

/// Top-level structure of the vendor marketplace.json.
struct RawMarketplaceIndex: Decodable, Sendable {
    let name: String?
    let owner: String?  // resolved from object {"name":...} or plain string
    let description: String?
    let plugins: [RawMarketplacePlugin]

    private enum CodingKeys: String, CodingKey { case name, owner, description, plugins }
    private struct OwnerObject: Decodable { let name: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try? c.decode(String.self, forKey: .name)
        self.description = try? c.decode(String.self, forKey: .description)
        self.plugins = (try? c.decode([RawMarketplacePlugin].self, forKey: .plugins)) ?? []
        // owner may be a plain string or {"name": "...", "email": "..."}
        if let str = try? c.decode(String.self, forKey: .owner) {
            self.owner = str
        } else if let obj = try? c.decode(OwnerObject.self, forKey: .owner) {
            self.owner = obj.name
        } else {
            self.owner = nil
        }
    }
}
