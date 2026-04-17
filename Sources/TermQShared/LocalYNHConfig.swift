import Foundation

/// Persisted YNH configuration stored in `ynh.json` (app-local).
public struct LocalYNHConfig: Codable, Sendable {
    /// Maps worktree path to linked harness name.
    public var worktreeHarness: [String: String]
    /// Global preferred vendor ID for harness launches.
    public var preferredVendor: String?

    public init(worktreeHarness: [String: String] = [:], preferredVendor: String? = nil) {
        self.worktreeHarness = worktreeHarness
        self.preferredVendor = preferredVendor
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
