import Foundation

/// Central manager for TermQ's data directory
/// Used by BackupManager and SecureStorage for consistent storage location
enum DataDirectoryManager {
    // MARK: - Constants

    static let defaultPath = "~/.termq"
    private static let userDefaultsKey = "termqDataDirectory"

    // MARK: - Properties

    /// The current data directory path (full path)
    static var dataDirectory: String {
        get {
            if let customPath = UserDefaults.standard.string(forKey: userDefaultsKey),
                !customPath.isEmpty {
                return customPath
            }
            return expandedDefaultPath
        }
        set {
            if newValue == expandedDefaultPath || newValue == defaultPath {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            }
        }
    }

    /// The display-friendly path (uses ~ for home directory)
    static var displayPath: String {
        let path = dataDirectory
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// The data directory as a URL
    static var url: URL {
        URL(fileURLWithPath: dataDirectory)
    }

    // MARK: - Private Helpers

    private static var expandedDefaultPath: String {
        NSString(string: defaultPath).expandingTildeInPath
    }

    // MARK: - Directory Management

    /// Ensures the data directory exists, creating it if necessary
    static func ensureDirectoryExists() throws {
        let fileManager = FileManager.default
        let path = dataDirectory

        if !fileManager.fileExists(atPath: path) {
            try fileManager.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    /// Checks if the data directory is writable
    static var isWritable: Bool {
        FileManager.default.isWritableFile(atPath: dataDirectory)
    }
}
