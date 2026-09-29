/// A YNH vendor — decoded from `ynh vendors --format json`.
///
/// No hardcoded vendor IDs anywhere in TermQ. UI asks `VendorService` for
/// the list; selections hold opaque `vendorID` strings.
public struct Vendor: Codable, Sendable, Identifiable {
    public var id: String { vendorID }

    /// Opaque vendor identifier (e.g. "claude", "codex"). YNH owns this enum.
    public let vendorID: String

    /// Human-readable name (e.g. "Claude Code", "OpenAI Codex").
    public let displayName: String

    /// CLI binary name (e.g. "claude", "codex", "agent").
    public let binary: String

    /// Vendor-specific config directory name (e.g. ".claude", ".codex").
    public let configDir: String

    /// Whether the vendor's CLI binary is currently on `$PATH`.
    public let available: Bool

    /// Whether this vendor's CLI can start an interactive session with an initial
    /// prompt pre-loaded (`ynh run --interactive`).
    public let supportsInitialPrompt: Bool

    /// Whether this vendor's CLI can continue a previous interactive session
    /// (`ynh run --resume`).
    ///
    /// Absent-means-false is load-bearing, not merely defensive. A pre-resume
    /// YNH forwards flags it does not recognise straight through to the vendor
    /// CLI, so sending `--resume` to an older binary would reach Claude as a
    /// *bare* `--resume` — which opens its interactive session picker and hangs
    /// the pane waiting for a keypress. An older YNH omits this field, which
    /// decodes to false, which stops TermQ emitting the flag at all.
    public let supportsResume: Bool

    enum CodingKeys: String, CodingKey {
        case vendorID = "name"
        case displayName = "display_name"
        case binary = "cli"
        case configDir = "config_dir"
        case available
        case supportsInitialPrompt = "supports_initial_prompt"
        case supportsResume = "supports_resume"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vendorID = try c.decode(String.self, forKey: .vendorID)
        displayName = try c.decode(String.self, forKey: .displayName)
        binary = try c.decode(String.self, forKey: .binary)
        configDir = try c.decode(String.self, forKey: .configDir)
        available = try c.decode(Bool.self, forKey: .available)
        supportsInitialPrompt =
            (try? c.decode(Bool.self, forKey: .supportsInitialPrompt)) ?? false
        supportsResume =
            (try? c.decode(Bool.self, forKey: .supportsResume)) ?? false
    }
}
