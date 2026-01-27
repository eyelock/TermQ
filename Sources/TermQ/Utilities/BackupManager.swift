import Foundation
import TermQCore

/// Backup frequency options
enum BackupFrequency: String, CaseIterable, Identifiable {
    case manual = "manual"
    case onSave = "onSave"
    case daily = "daily"
    case weekly = "weekly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:
            return "Manual Only"
        case .onSave:
            return "Every Save"
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        }
    }

    var description: String {
        switch self {
        case .manual:
            return "Only backup when you click 'Backup Now'"
        case .onSave:
            return "Backup every time your board changes"
        case .daily:
            return "Backup once per day on first change"
        case .weekly:
            return "Backup once per week on first change"
        }
    }
}

/// Handles backup and restore of board data to a location that survives app uninstall
enum BackupManager {
    // MARK: - Constants

    static let backupFileName = "board-backup.json"
    static let secretsBackupFileName = "secrets-backup.enc"

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let backupFrequency = "backupFrequency"
        static let backupRetentionCount = "backupRetentionCount"
        static let lastBackupDate = "lastBackupDate"
    }

    // MARK: - Settings

    /// The backup location (uses central DataDirectoryManager)
    static var backupLocation: String {
        DataDirectoryManager.dataDirectory
    }

    /// The backup frequency (default: daily)
    static var frequency: BackupFrequency {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Keys.backupFrequency),
                let frequency = BackupFrequency(rawValue: rawValue)
            else {
                return .daily
            }
            return frequency
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.backupFrequency)
        }
    }

    /// Number of backups to retain (default: 10)
    static var retentionCount: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: Keys.backupRetentionCount)
            return value > 0 ? value : 10
        }
        set {
            UserDefaults.standard.set(max(1, newValue), forKey: Keys.backupRetentionCount)
        }
    }

    /// Date of last backup
    static var lastBackupDate: Date? {
        get {
            let interval = UserDefaults.standard.double(forKey: Keys.lastBackupDate)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Keys.lastBackupDate)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.lastBackupDate)
            }
        }
    }

    // MARK: - Path Helpers

    /// Expanded backup directory path
    static var expandedBackupPath: String {
        NSString(string: backupLocation).expandingTildeInPath
    }

    /// Full path to the backup file
    static var backupFilePath: String {
        "\(expandedBackupPath)/\(backupFileName)"
    }

    /// URL to the backup file
    static var backupFileURL: URL {
        URL(fileURLWithPath: backupFilePath)
    }

    /// Full path to the secrets backup file
    static var secretsBackupFilePath: String {
        "\(expandedBackupPath)/\(secretsBackupFileName)"
    }

    /// URL to the secrets backup file
    static var secretsBackupFileURL: URL {
        URL(fileURLWithPath: secretsBackupFilePath)
    }

    /// Path to the primary board.json file
    static var primaryBoardPath: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        #if DEBUG
            let termqDir = appSupport.appendingPathComponent("TermQ-Debug", isDirectory: true)
        #else
            let termqDir = appSupport.appendingPathComponent("TermQ", isDirectory: true)
        #endif
        return termqDir.appendingPathComponent("board.json")
    }

    // MARK: - Backup Operations

    /// Check if a backup exists
    static var hasBackup: Bool {
        FileManager.default.fileExists(atPath: backupFilePath)
    }

    /// Get backup file info
    static var backupInfo: (exists: Bool, date: Date?, size: Int64) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupFilePath),
            let attrs = try? fm.attributesOfItem(atPath: backupFilePath)
        else {
            return (false, nil, 0)
        }

        let date = attrs[.modificationDate] as? Date
        let size = (attrs[.size] as? Int64) ?? 0
        return (true, date, size)
    }

    /// Perform a backup of the board data and secrets
    static func backup() -> Result<String, BackupError> {
        let fm = FileManager.default
        let sourcePath = primaryBoardPath.path

        // Check if source exists
        guard fm.fileExists(atPath: sourcePath) else {
            return .failure(.sourceNotFound)
        }

        do {
            // Create backup directory if needed
            try fm.createDirectory(atPath: expandedBackupPath, withIntermediateDirectories: true)

            // Remove existing backup if present
            if fm.fileExists(atPath: backupFilePath) {
                try fm.removeItem(atPath: backupFilePath)
            }

            // Copy the board file
            try fm.copyItem(atPath: sourcePath, toPath: backupFilePath)

            // Backup secrets file if it exists
            backupSecrets()

            // Update last backup date
            lastBackupDate = Date()

            #if DEBUG
                print("[BackupManager] Backup created at: \(backupFilePath)")
            #endif

            return .success("Backup created successfully at \(backupLocation)/\(backupFileName)")
        } catch {
            return .failure(.backupFailed(error.localizedDescription))
        }
    }

    /// Backup secrets file from SecureStorage config directory
    private static func backupSecrets() {
        Task {
            let fm = FileManager.default
            let configDir = await SecureStorage.shared.getConfigDirectory()
            let secretsSourcePath = configDir.appendingPathComponent("secrets.enc").path

            // Only backup if secrets file exists
            guard fm.fileExists(atPath: secretsSourcePath) else {
                #if DEBUG
                    print("[BackupManager] No secrets file to backup")
                #endif
                return
            }

            do {
                // Remove existing secrets backup if present
                if fm.fileExists(atPath: secretsBackupFilePath) {
                    try fm.removeItem(atPath: secretsBackupFilePath)
                }

                // Copy the secrets file
                try fm.copyItem(atPath: secretsSourcePath, toPath: secretsBackupFilePath)

                #if DEBUG
                    print("[BackupManager] Secrets backup created at: \(secretsBackupFilePath)")
                #endif
            } catch {
                #if DEBUG
                    print("[BackupManager] Failed to backup secrets: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Restore board data and secrets from backup
    static func restore() -> Result<String, BackupError> {
        let fm = FileManager.default

        // Check if backup exists
        guard fm.fileExists(atPath: backupFilePath) else {
            return .failure(.noBackupFound)
        }

        // Validate backup data
        guard let data = try? Data(contentsOf: backupFileURL),
            (try? JSONDecoder().decode(Board.self, from: data)) != nil
        else {
            return .failure(.invalidBackupData)
        }

        do {
            // Ensure primary directory exists
            let primaryDir = primaryBoardPath.deletingLastPathComponent()
            try fm.createDirectory(at: primaryDir, withIntermediateDirectories: true)

            // Remove existing primary if present
            if fm.fileExists(atPath: primaryBoardPath.path) {
                try fm.removeItem(at: primaryBoardPath)
            }

            // Copy backup to primary location
            try fm.copyItem(atPath: backupFilePath, toPath: primaryBoardPath.path)

            // Restore secrets if backup exists
            restoreSecrets()

            #if DEBUG
                print("[BackupManager] Restored from backup: \(backupFilePath)")
            #endif

            return .success("Board restored successfully from backup")
        } catch {
            return .failure(.restoreFailed(error.localizedDescription))
        }
    }

    /// Restore secrets file to SecureStorage config directory
    private static func restoreSecrets() {
        let fm = FileManager.default

        // Only restore if secrets backup exists
        guard fm.fileExists(atPath: secretsBackupFilePath) else {
            #if DEBUG
                print("[BackupManager] No secrets backup to restore")
            #endif
            return
        }

        Task {
            let configDir = await SecureStorage.shared.getConfigDirectory()
            let secretsDestPath = configDir.appendingPathComponent("secrets.enc").path

            do {
                // Ensure config directory exists
                try fm.createDirectory(at: configDir, withIntermediateDirectories: true)

                // Remove existing secrets if present
                if fm.fileExists(atPath: secretsDestPath) {
                    try fm.removeItem(atPath: secretsDestPath)
                }

                // Copy the secrets backup
                try fm.copyItem(atPath: secretsBackupFilePath, toPath: secretsDestPath)

                // Clear SecureStorage cache so it reloads
                await SecureStorage.shared.clearCache()

                #if DEBUG
                    print("[BackupManager] Secrets restored to: \(secretsDestPath)")
                #endif
            } catch {
                #if DEBUG
                    print("[BackupManager] Failed to restore secrets: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Restore from a specific backup file (e.g., from file picker)
    static func restore(from url: URL) -> Result<String, BackupError> {
        let fm = FileManager.default

        // Validate backup data
        guard let data = try? Data(contentsOf: url),
            (try? JSONDecoder().decode(Board.self, from: data)) != nil
        else {
            return .failure(.invalidBackupData)
        }

        do {
            // Ensure primary directory exists
            let primaryDir = primaryBoardPath.deletingLastPathComponent()
            try fm.createDirectory(at: primaryDir, withIntermediateDirectories: true)

            // Remove existing primary if present
            if fm.fileExists(atPath: primaryBoardPath.path) {
                try fm.removeItem(at: primaryBoardPath)
            }

            // Copy backup to primary location
            try fm.copyItem(at: url, to: primaryBoardPath)

            #if DEBUG
                print("[BackupManager] Restored from: \(url.path)")
            #endif

            return .success("Board restored successfully from \(url.lastPathComponent)")
        } catch {
            return .failure(.restoreFailed(error.localizedDescription))
        }
    }

    // MARK: - Automatic Backup Logic

    /// Check if a backup should be performed based on frequency setting
    static func shouldBackupNow() -> Bool {
        switch frequency {
        case .manual:
            return false
        case .onSave:
            return true
        case .daily:
            guard let lastBackup = lastBackupDate else { return true }
            return Calendar.current.dateComponents([.hour], from: lastBackup, to: Date()).hour ?? 0 >= 24
        case .weekly:
            guard let lastBackup = lastBackupDate else { return true }
            return Calendar.current.dateComponents([.day], from: lastBackup, to: Date()).day ?? 0 >= 7
        }
    }

    /// Perform backup if conditions are met (called from BoardViewModel.save())
    static func backupIfNeeded() {
        guard shouldBackupNow() else { return }

        let result = backup()
        #if DEBUG
            switch result {
            case .success(let message):
                print("[BackupManager] Auto-backup: \(message)")
            case .failure(let error):
                print("[BackupManager] Auto-backup failed: \(error.localizedDescription)")
            }
        #endif
    }

    // MARK: - Startup Restore Check

    /// Check if we should offer to restore from backup
    /// Returns the backup URL if primary is missing/empty but backup exists
    static func checkAndOfferRestore() -> URL? {
        let fm = FileManager.default
        let primaryPath = primaryBoardPath.path

        // Check if primary board exists and has content
        let primaryExists = fm.fileExists(atPath: primaryPath)
        let primaryHasContent: Bool
        if primaryExists {
            if let data = try? Data(contentsOf: primaryBoardPath),
                let board = try? JSONDecoder().decode(Board.self, from: data) {
                // Consider empty if no cards
                primaryHasContent = !board.cards.isEmpty
            } else {
                primaryHasContent = false
            }
        } else {
            primaryHasContent = false
        }

        // Check if backup exists and is valid
        guard hasBackup,
            let data = try? Data(contentsOf: backupFileURL),
            let backupBoard = try? JSONDecoder().decode(Board.self, from: data),
            !backupBoard.cards.isEmpty
        else {
            return nil
        }

        // Offer restore if primary is missing/empty but backup has data
        if !primaryHasContent {
            return backupFileURL
        }

        return nil
    }
}

// MARK: - Import for Board decoding

// MARK: - Errors

enum BackupError: LocalizedError {
    case sourceNotFound
    case backupFailed(String)
    case restoreFailed(String)
    case noBackupFound
    case invalidBackupData
    case locationNotWritable

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "No board data found to backup."
        case .backupFailed(let message):
            return "Backup failed: \(message)"
        case .restoreFailed(let message):
            return "Restore failed: \(message)"
        case .noBackupFound:
            return "No backup file found."
        case .invalidBackupData:
            return "The backup file is corrupted or invalid."
        case .locationNotWritable:
            return "The backup location is not writable."
        }
    }
}
