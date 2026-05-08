import Foundation

/// Persisted YNH configuration stored in `ynh.json` (app-local).
public struct LocalYNHConfig: Codable, Sendable {
    /// Maps worktree path to an explicit harness override for that specific worktree.
    public var worktreeHarness: [String: String]
    /// Maps repository root path to a repo-level default harness.
    ///
    /// Separate from `worktreeHarness` so repo defaults and worktree overrides
    /// are independent even when the main worktree path equals the repo path.
    public var repoHarness: [String: String]
    /// Global preferred vendor ID for harness launches.
    public var preferredVendor: String?
    /// Per-harness vendor override. Maps harness id (`Harness.id`, namespace-
    /// qualified when present) to a vendor id (`claude` / `codex` / `cursor`).
    /// When set, this overrides the harness's own `default_vendor` for both
    /// the badge in the detail pane and the launch sheet's initial selection.
    public var harnessVendor: [String: String]
    /// Last-used harness id for "Review with Focus" per repo path.
    /// Independent from `repoHarness` — a review harness can differ from the
    /// default terminal-launch harness.
    public var repoReviewHarness: [String: String]
    /// Last-used focus name for "Review with Focus" per repo path.
    /// Empty string means no focus selected (ad-hoc prompt).
    public var repoReviewFocus: [String: String]

    public init(
        worktreeHarness: [String: String] = [:],
        repoHarness: [String: String] = [:],
        preferredVendor: String? = nil,
        harnessVendor: [String: String] = [:],
        repoReviewHarness: [String: String] = [:],
        repoReviewFocus: [String: String] = [:]
    ) {
        self.worktreeHarness = worktreeHarness
        self.repoHarness = repoHarness
        self.preferredVendor = preferredVendor
        self.harnessVendor = harnessVendor
        self.repoReviewHarness = repoReviewHarness
        self.repoReviewFocus = repoReviewFocus
    }

    // Custom decoder for backward compat: all optional dicts default to empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        worktreeHarness = (try? c.decode([String: String].self, forKey: .worktreeHarness)) ?? [:]
        repoHarness = (try? c.decode([String: String].self, forKey: .repoHarness)) ?? [:]
        preferredVendor = try? c.decode(String.self, forKey: .preferredVendor)
        harnessVendor = (try? c.decode([String: String].self, forKey: .harnessVendor)) ?? [:]
        repoReviewHarness = (try? c.decode([String: String].self, forKey: .repoReviewHarness)) ?? [:]
        repoReviewFocus = (try? c.decode([String: String].self, forKey: .repoReviewFocus)) ?? [:]
    }
}

/// Loads and saves YNH configuration from `ynh.json` (shared across CLI and MCP).
///
/// Uses NSFileCoordinator for safe concurrent access across processes.
/// Returns an empty `LocalYNHConfig` when the file does not yet exist (first run).
public enum YNHConfigLoader {
    public enum LoadError: Error, LocalizedError, Sendable {
        case decodingFailed(String)
        case coordinationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .decodingFailed(let message):
                return "Failed to decode ynh.json: \(message)"
            case .coordinationFailed(let message):
                return "File coordination failed: \(message)"
            }
        }
    }

    public enum SaveError: Error, LocalizedError, Sendable {
        case encodingFailed(String)
        case writeFailed(String)
        case coordinationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .encodingFailed(let message):
                return "Failed to encode ynh.json: \(message)"
            case .writeFailed(let message):
                return "Failed to write ynh.json: \(message)"
            case .coordinationFailed(let message):
                return "File coordination failed: \(message)"
            }
        }
    }

    public static func getConfigURL(dataDirectory: URL? = nil, debug: Bool = false) -> URL {
        BoardLoader.getDataDirectoryPath(customDirectory: dataDirectory, debug: debug)
            .appendingPathComponent("ynh.json")
    }

    public static func load(dataDirectory: URL? = nil, debug: Bool = false) throws -> LocalYNHConfig {
        let configURL = getConfigURL(dataDirectory: dataDirectory, debug: debug)

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return LocalYNHConfig()
        }

        var coordinationError: NSError?
        var loadResult: Result<LocalYNHConfig, Error>?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: configURL, options: [], error: &coordinationError) { url in
            do {
                let data = try Data(contentsOf: url)
                loadResult = .success(try JSONDecoder().decode(LocalYNHConfig.self, from: data))
            } catch let error as DecodingError {
                loadResult = .failure(LoadError.decodingFailed(error.localizedDescription))
            } catch {
                loadResult = .failure(error)
            }
        }

        if let error = coordinationError {
            throw LoadError.coordinationFailed(error.localizedDescription)
        }

        guard let result = loadResult else {
            throw LoadError.coordinationFailed("File coordination completed without result")
        }

        return try result.get()
    }

    public static func save(_ config: LocalYNHConfig, dataDirectory: URL? = nil, debug: Bool = false) throws {
        let configURL = getConfigURL(dataDirectory: dataDirectory, debug: debug)

        let dirURL = configURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dirURL.path) {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData: Data
        do {
            jsonData = try encoder.encode(config)
        } catch {
            throw SaveError.encodingFailed(error.localizedDescription)
        }

        var coordinationError: NSError?
        var writeError: Error?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: configURL, options: [], error: &coordinationError) { writeURL in
            do {
                try jsonData.write(to: writeURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let error = coordinationError {
            throw SaveError.coordinationFailed(error.localizedDescription)
        }

        if let error = writeError {
            throw SaveError.writeFailed(error.localizedDescription)
        }
    }
}
