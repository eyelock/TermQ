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

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        }
    }

    /// Relative path to the marketplace index inside the cloned repo.
    var indexPath: String {
        switch self {
        case .claude: return ".claude-plugin/marketplace.json"
        case .cursor: return ".cursor-plugin/marketplace.json"
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
            self.type = str.hasPrefix(".") ? .relative : .url
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
        self.url = (try? container.decode(String.self, forKey: .url)) ?? ""
        self.path = try? container.decode(String.self, forKey: .path)
    }

    private enum RawSourceCodingKeys: String, CodingKey {
        case source, type, url, path
    }
}

extension PluginSourceSpec {
    /// Resolves the effective `(url, path)` pair for `ynh include add`.
    ///
    /// Relative-source plugins live inside the marketplace repo, so the correct
    /// source URL is the marketplace git URL, not the relative path stored in
    /// the plugin spec (which is meaningless as a standalone git URL to YNH).
    func resolved(marketplaceURL: String) -> (url: String, path: String?) {
        // Also catch persisted entries where type was corrupted to .unknown due to
        // the "source" vs "type" key mismatch in the old decoder.
        guard type.isRelative || url.hasPrefix("./") else {
            if type == .github {
                let expanded = url.hasPrefix("github.com/") ? url : "github.com/\(url)"
                return (expanded, path)
            }
            return (url, path)
        }
        let rawPath = url.hasPrefix("./") ? String(url.dropFirst(2)) : url
        let fullPath = path.map { "\(rawPath)/\($0)" } ?? rawPath
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

    private enum CodingKeys: String, CodingKey { case type, message }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "pending"
        switch type {
        case "eager": self = .eager
        case "failed":
            let msg = (try? container.decode(String.self, forKey: .message)) ?? ""
            self = .failed(msg)
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
        }
    }

    var isResolved: Bool {
        switch self {
        case .eager, .failed: return true
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
