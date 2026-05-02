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
    /// The currently installed version. Maps from YNH's `version_installed` key.
    public let version: String
    /// The latest published version available, populated only when YNH is
    /// invoked with `--check-updates` and the install record carries enough
    /// provenance to resolve an upstream (registry installs). Absent in any
    /// other case — the three-state semantics from the YNH JSON contract.
    public let versionAvailable: String?
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
    /// True when the harness is structurally pinned to a specific commit SHA.
    /// Absent on YNH builds older than 0.3.0 — treat nil as `false`.
    public let isPinned: Bool?
    /// Latest commit SHA on the harness's recorded install ref upstream
    /// (`installed_from.ref`). Populated by `--check-updates` (YNH 0.3+
    /// post the harness-level drift fix). Compare against
    /// `installedFrom.sha` to detect drift on the harness's own source —
    /// the path that catches self-contained plugins (no includes).
    public let shaAvailable: String?

    /// True when an update is available from upstream — populated only after a
    /// `--check-updates` probe and only when the harness has registry
    /// provenance. Otherwise nil ("unknown / not checked").
    public var hasVersionUpdate: Bool? {
        guard let versionAvailable, !versionAvailable.isEmpty else { return nil }
        return versionAvailable != version
    }

    /// The "where to edit this harness" path that user-facing actions
    /// (Reveal in Finder/Terminal, Open in editor, Copy Path) should target.
    ///
    /// For forked-local and plain-local installs whose `installed_from.source`
    /// is a filesystem path, that's the editable working tree the user
    /// expects to land in. Otherwise (registry, git, no provenance) the
    /// canonical location is the install dir at `path`.
    ///
    /// Once YNH's `ynh fork --register` lands and the install dir becomes a
    /// symlink to the source tree, the two converge — but we keep this
    /// indirection so behaviour is stable across both layouts.
    public var editablePath: String {
        guard let provenance = installedFrom,
            provenance.sourceType == "local"
        else { return path }
        let source = provenance.source
        if source.hasPrefix("/") || source.hasPrefix("~") {
            return (source as NSString).expandingTildeInPath
        }
        return path
    }

    /// True when this harness is a fork of a registry install — `update`
    /// flows are disabled by YNH for forks (per `ynh update` behaviour),
    /// so the UI hides the Update affordance for these.
    public var isFork: Bool {
        installedFrom?.forkedFrom != nil
    }

    /// True when the harness's own source SHA differs from upstream on the
    /// recorded install ref. Distinct from include-level drift; specifically
    /// catches self-contained plugins where the entire content lives inside
    /// the harness directory (no includes to drift). Returns false when
    /// either side is missing — we cannot prove drift without both.
    public var hasSourceDrift: Bool {
        guard let installedSHA = installedFrom?.sha, !installedSHA.isEmpty,
            let availableSHA = shaAvailable, !availableSHA.isEmpty
        else { return false }
        return installedSHA != availableSHA
    }

    enum CodingKeys: String, CodingKey {
        case name, description, path, artifacts, includes, namespace
        case version = "version_installed"
        case versionAvailable = "version_available"
        case defaultVendor = "default_vendor"
        case installedFrom = "installed_from"
        case delegatesTo = "delegates_to"
        case isPinned = "is_pinned"
        case shaAvailable = "sha_available"
    }

    /// Custom decoder that tolerates `null` arrays for `includes` and
    /// `delegates_to`. YNH emits these as `null` for broken installs (e.g. a
    /// pointer file whose source path was deleted, or a harness with a legacy
    /// manifest format) so they show up in `ynh ls` as error rows. Without
    /// this tolerance, a single bad row would fail the whole list decode and
    /// empty the sidebar.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.version = try c.decode(String.self, forKey: .version)
        self.versionAvailable = try c.decodeIfPresent(String.self, forKey: .versionAvailable)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.defaultVendor = try c.decode(String.self, forKey: .defaultVendor)
        self.namespace = try c.decodeIfPresent(String.self, forKey: .namespace)
        self.path = try c.decode(String.self, forKey: .path)
        self.installedFrom = try c.decodeIfPresent(HarnessProvenance.self, forKey: .installedFrom)
        self.artifacts = try c.decode(HarnessArtifactCounts.self, forKey: .artifacts)
        self.includes = (try? c.decodeIfPresent([HarnessInclude].self, forKey: .includes)) ?? []
        self.delegatesTo = (try? c.decodeIfPresent([HarnessDelegate].self, forKey: .delegatesTo)) ?? []
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned)
        self.shaAvailable = try c.decodeIfPresent(String.self, forKey: .shaAvailable)
    }

    public init(
        name: String,
        version: String,
        versionAvailable: String? = nil,
        description: String? = nil,
        defaultVendor: String,
        namespace: String? = nil,
        path: String,
        installedFrom: HarnessProvenance? = nil,
        artifacts: HarnessArtifactCounts,
        includes: [HarnessInclude] = [],
        delegatesTo: [HarnessDelegate] = [],
        isPinned: Bool? = nil,
        shaAvailable: String? = nil
    ) {
        self.name = name
        self.version = version
        self.versionAvailable = versionAvailable
        self.description = description
        self.defaultVendor = defaultVendor
        self.namespace = namespace
        self.path = path
        self.installedFrom = installedFrom
        self.artifacts = artifacts
        self.includes = includes
        self.delegatesTo = delegatesTo
        self.isPinned = isPinned
        self.shaAvailable = shaAvailable
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
    /// When set, this is a forked-to-local harness and the value carries the
    /// origin it was forked from. Populated by `ynh fork` (YNH 0.3+).
    public let forkedFrom: ForkOrigin?

    enum CodingKeys: String, CodingKey {
        case source, path, ref, sha, namespace
        case sourceType = "source_type"
        case registryName = "registry_name"
        case installedAt = "installed_at"
        case forkedFrom = "forked_from"
    }

    public init(
        sourceType: String,
        source: String,
        path: String? = nil,
        registryName: String? = nil,
        installedAt: String,
        ref: String? = nil,
        sha: String? = nil,
        namespace: String? = nil,
        forkedFrom: ForkOrigin? = nil
    ) {
        self.sourceType = sourceType
        self.source = source
        self.path = path
        self.registryName = registryName
        self.installedAt = installedAt
        self.ref = ref
        self.sha = sha
        self.namespace = namespace
        self.forkedFrom = forkedFrom
    }
}

/// Origin record for a forked-to-local harness. Captured at fork time so the
/// detail pane can show the ghost origin and the "Re-fork from upstream"
/// affordance has the data it needs.
public struct ForkOrigin: Codable, Equatable, Sendable {
    public let sourceType: String
    public let source: String
    public let registryName: String?
    public let version: String?
    public let sha: String?

    enum CodingKeys: String, CodingKey {
        case source, version, sha
        case sourceType = "source_type"
        case registryName = "registry_name"
    }

    public init(
        sourceType: String,
        source: String,
        registryName: String? = nil,
        version: String? = nil,
        sha: String? = nil
    ) {
        self.sourceType = sourceType
        self.source = source
        self.registryName = registryName
        self.version = version
        self.sha = sha
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
    /// The manifest-declared ref (the pin in `plugin.json`) — present only when
    /// the include is explicitly pinned. Floating refs leave this empty and
    /// resolve to whatever upstream HEAD was at install time; that resolved
    /// commit is captured separately in `refInstalled`.
    public let ref: String?
    public let path: String?
    public let pick: [String]?
    /// True when the include is pinned to a specific commit SHA. Absent on
    /// YNH builds older than 0.3.0 — treat nil as `false`.
    public let isPinned: Bool?
    /// Commit SHA actually checked out at install/update time, recorded by
    /// YNH 0.3.0+ in `installed.json.resolved`. Compared against
    /// `refAvailable` to detect per-include drift.
    public let refInstalled: String?
    /// Latest upstream commit SHA, populated when YNH was invoked with
    /// `--check-updates`.
    public let refAvailable: String?

    enum CodingKeys: String, CodingKey {
        case git, ref, path, pick
        case isPinned = "is_pinned"
        case refInstalled = "ref_installed"
        case refAvailable = "ref_available"
    }
}

/// A delegate reference within a harness.
public struct HarnessDelegate: Codable, Equatable, Sendable {
    public let git: String
    public let ref: String?
    public let path: String?
}

// MARK: - YNH structured-output envelope

/// Top-level envelope returned by `ynh ls --format json` (YNH 0.3.0+).
///
/// YNH wraps array-returning commands in an envelope so it can attach
/// `capabilities` and `ynh_version` metadata. Callers should decode this and
/// read `harnesses` rather than decoding `[Harness]` directly.
public struct HarnessListResponse: Codable, Sendable {
    public let capabilities: String?
    public let ynhVersion: String?
    public let harnesses: [Harness]

    enum CodingKeys: String, CodingKey {
        case capabilities, harnesses
        case ynhVersion = "ynh_version"
    }
}

/// Top-level envelope returned by `ynh info <name> --format json` (YNH 0.3.0+).
public struct HarnessInfoResponse: Codable, Sendable {
    public let capabilities: String?
    public let ynhVersion: String?
    public let harness: HarnessInfo

    enum CodingKeys: String, CodingKey {
        case capabilities, harness
        case ynhVersion = "ynh_version"
    }
}
