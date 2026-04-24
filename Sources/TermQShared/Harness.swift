import Foundation

/// Lightweight row model decoded from `ynh ls --format json`.
///
/// Represents a single installed harness. All fields match the structured-output
/// contract defined in YNH's `docs/cli-structured.md`. Uses `snake_case` JSON
/// keys per the YNH convention.
public struct Harness: Codable, Equatable, Sendable, Identifiable {
    /// Unique identifier. Includes namespace when present: `"org/repo/name"`.
    /// Falls back to plain `name` for flat/local installs.
    public var id: String {
        guard let ns = namespace, !ns.isEmpty else { return name }
        return "\(ns)/\(name)"
    }

    public let name: String
    public let version: String
    public let description: String?
    public let defaultVendor: String
    /// Namespace derived from the registry entry (e.g. `"eyelock/assistants"`).
    /// `nil` for locally installed or flat harnesses.
    public let namespace: String?
    public let path: String
    public let installedFrom: HarnessProvenance?
    public let artifacts: HarnessArtifactCounts
    public let includes: [HarnessInclude]
    public let delegatesTo: [HarnessDelegate]

    enum CodingKeys: String, CodingKey {
        case name, version, description, path, artifacts, includes, namespace
        case defaultVendor = "default_vendor"
        case installedFrom = "installed_from"
        case delegatesTo = "delegates_to"
    }

    public init(
        name: String,
        version: String,
        description: String? = nil,
        defaultVendor: String,
        namespace: String? = nil,
        path: String,
        installedFrom: HarnessProvenance? = nil,
        artifacts: HarnessArtifactCounts,
        includes: [HarnessInclude] = [],
        delegatesTo: [HarnessDelegate] = []
    ) {
        self.name = name
        self.version = version
        self.description = description
        self.defaultVendor = defaultVendor
        self.namespace = namespace
        self.path = path
        self.installedFrom = installedFrom
        self.artifacts = artifacts
        self.includes = includes
        self.delegatesTo = delegatesTo
    }
}

/// Installation provenance for a harness.
public struct HarnessProvenance: Codable, Equatable, Sendable {
    public let sourceType: String
    public let source: String
    public let path: String?
    public let registryName: String?
    public let installedAt: String
    /// Git ref resolved at install time (ynh 0.2+, registry installs only).
    public let ref: String?
    /// Git commit SHA resolved at install time (ynh 0.2+, registry installs only).
    public let sha: String?
    /// Namespace of the registry entry this harness was installed from (ynh 0.2+).
    public let namespace: String?

    enum CodingKeys: String, CodingKey {
        case source, path, ref, sha, namespace
        case sourceType = "source_type"
        case registryName = "registry_name"
        case installedAt = "installed_at"
    }
}

/// Artifact counts for an installed harness.
public struct HarnessArtifactCounts: Codable, Equatable, Sendable {
    public let skills: Int
    public let agents: Int
    public let rules: Int
    public let commands: Int

    /// Total number of artifacts across all categories.
    public var total: Int { skills + agents + rules + commands }

    public init(skills: Int, agents: Int, rules: Int, commands: Int) {
        self.skills = skills
        self.agents = agents
        self.rules = rules
        self.commands = commands
    }
}

/// An include reference within a harness.
public struct HarnessInclude: Codable, Equatable, Sendable {
    public let git: String
    public let ref: String?
    public let path: String?
    public let pick: [String]?
}

/// A delegate reference within a harness.
public struct HarnessDelegate: Codable, Equatable, Sendable {
    public let git: String
    public let ref: String?
    public let path: String?
}
