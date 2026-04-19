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

    enum CodingKeys: String, CodingKey {
        case vendorID = "name"
        case displayName = "display_name"
        case binary = "cli"
        case configDir = "config_dir"
        case available
    }
}
