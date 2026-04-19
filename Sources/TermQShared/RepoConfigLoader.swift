import Foundation

// MARK: - Repo Config Loader

/// Loads and saves repository configuration from `repos.json` (shared across CLI and MCP)
///
/// Uses NSFileCoordinator for safe concurrent access across processes.
/// Returns an empty `RepoConfig` when the file does not yet exist (first run).
public enum RepoConfigLoader {
    public enum LoadError: Error, LocalizedError, Sendable {
        case decodingFailed(String)
        case coordinationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .decodingFailed(let message):
                return "Failed to decode repos.json: \(message)"
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
                return "Failed to encode repos.json: \(message)"
            case .writeFailed(let message):
                return "Failed to write repos.json: \(message)"
            case .coordinationFailed(let message):
                return "File coordination failed: \(message)"
            }
        }
    }

    /// URL for `repos.json` in the TermQ data directory
    public static func getConfigURL(dataDirectory: URL? = nil, debug: Bool = false) -> URL {
        BoardLoader.getDataDirectoryPath(customDirectory: dataDirectory, debug: debug)
            .appendingPathComponent("repos.json")
    }

    /// Load repository configuration from disk.
    ///
    /// Returns an empty `RepoConfig` if the file does not exist yet.
    public static func load(dataDirectory: URL? = nil, debug: Bool = false) throws -> RepoConfig {
        let configURL = getConfigURL(dataDirectory: dataDirectory, debug: debug)

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return RepoConfig()
        }

        var coordinationError: NSError?
        var loadResult: Result<RepoConfig, Error>?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: configURL, options: [], error: &coordinationError) { url in
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let config = try decoder.decode(RepoConfig.self, from: data)
                loadResult = .success(config)
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

    /// Save repository configuration to disk.
    ///
    /// Creates the TermQ data directory if it does not yet exist.
    public static func save(_ config: RepoConfig, dataDirectory: URL? = nil, debug: Bool = false) throws {
        let configURL = getConfigURL(dataDirectory: dataDirectory, debug: debug)

        // Ensure the data directory exists
        let dirURL = configURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dirURL.path) {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

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
