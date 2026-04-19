import Foundation

/// Resolved directory paths reported by `ynh paths --format json`.
///
/// Matches the seven-field JSON contract defined in `docs/cli-structured.md`.
/// All paths are absolute and fully resolved — no `~`, no relative fragments.
/// Uses `snake_case` keys per the YNH structured-output convention.
public struct YNHPaths: Codable, Equatable, Sendable {
    public let home: String
    public let config: String
    public let harnesses: String
    public let symlinks: String
    public let cache: String
    public let run: String
    public let bin: String

    public init(
        home: String,
        config: String,
        harnesses: String,
        symlinks: String,
        cache: String,
        run: String,
        bin: String
    ) {
        self.home = home
        self.config = config
        self.harnesses = harnesses
        self.symlinks = symlinks
        self.cache = cache
        self.run = run
        self.bin = bin
    }
}
