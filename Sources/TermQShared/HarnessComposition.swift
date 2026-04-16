import Foundation

/// Composed, vendor-neutral view decoded from `ynd compose <path>`.
///
/// This is the second half of the detail pane data. The first half comes from
/// `ynh info` (see ``HarnessInfo``). TermQ merges both into ``HarnessDetail``.
///
/// `ynd compose` defaults to JSON output — no `--format json` flag needed.
public struct HarnessComposition: Codable, Sendable {
    public let name: String
    public let version: String
    public let description: String?
    public let defaultVendor: String
    public let artifacts: ComposedArtifacts
    public let includes: [ComposedInclude]
    public let delegatesTo: [ComposedDelegate]
    public let hooks: [String: [ComposedHook]]?
    public let mcpServers: [String: ComposedMCPServer]?
    public let profiles: [String]
    public let focuses: [String: ComposedFocus]?
    public let counts: ComposedCounts

    enum CodingKeys: String, CodingKey {
        case name, version, description, artifacts, includes, hooks, profiles, focuses, counts
        case defaultVendor = "default_vendor"
        case delegatesTo = "delegates_to"
        case mcpServers = "mcp_servers"
    }
}

// MARK: - Artifacts

/// Container for all artifact categories.
public struct ComposedArtifacts: Codable, Sendable {
    public let skills: [ComposedArtifact]
    public let agents: [ComposedArtifact]
    public let rules: [ComposedArtifact]
    public let commands: [ComposedArtifact]

    /// All artifacts flattened into a single array.
    public var all: [ComposedArtifact] {
        skills + agents + rules + commands
    }
}

/// A single artifact — name plus which harness (or include) contributed it.
public struct ComposedArtifact: Codable, Sendable, Identifiable {
    public var id: String { "\(source)/\(name)" }
    public let name: String
    public let source: String
}

// MARK: - Includes & Delegates

/// An include directive with resolution status from the compose resolver.
public struct ComposedInclude: Codable, Sendable {
    public let git: String
    public let ref: String?
    public let path: String?
    public let pick: [String]?
    public let resolved: Bool
}

/// A delegate directive from the composed harness.
public struct ComposedDelegate: Codable, Sendable {
    public let git: String
    public let ref: String?
    public let path: String?
}

// MARK: - Hooks

/// A single hook entry within an event.
public struct ComposedHook: Codable, Sendable {
    public let command: String
    public let matcher: String?
}

// MARK: - MCP Servers

/// MCP server configuration from the composed harness.
public struct ComposedMCPServer: Codable, Sendable {
    public let command: String?
    public let args: [String]?
    public let env: [String: String]?
    public let url: String?
    public let headers: [String: String]?
}

// MARK: - Focuses

/// A named focus from the composed harness.
public struct ComposedFocus: Codable, Sendable {
    public let profile: String?
    public let prompt: String
}

// MARK: - Counts

/// Aggregate artifact counts.
public struct ComposedCounts: Codable, Sendable {
    public let skills: Int
    public let agents: Int
    public let rules: Int
    public let commands: Int

    public var total: Int { skills + agents + rules + commands }
}
