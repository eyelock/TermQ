import Foundation
import TermQShared

/// Handles repos.json persistence and file monitoring.
///
/// Follows the `BoardPersistence` pattern: owns the save URL, delegates encode/decode
/// to `RepoConfigLoader` (which uses NSFileCoordinator + ISO 8601 dates), and wires up
/// a `FileMonitor` for external changes (MCP / CLI writes).
@MainActor
final class RepoPersistence {
    let saveURL: URL
    private var fileMonitor: FileMonitor?

    init() {
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            fatalError("Unable to access Application Support directory")
        }

        #if DEBUG
            let termqDir = appSupport.appendingPathComponent("TermQ-Debug", isDirectory: true)
        #else
            let termqDir = appSupport.appendingPathComponent("TermQ", isDirectory: true)
        #endif

        try? FileManager.default.createDirectory(at: termqDir, withIntermediateDirectories: true)
        saveURL = termqDir.appendingPathComponent("repos.json")
    }

    deinit {
        fileMonitor = nil
    }

    // MARK: - Load

    func loadConfig() -> RepoConfig {
        let dir = saveURL.deletingLastPathComponent()
        return (try? RepoConfigLoader.load(dataDirectory: dir)) ?? RepoConfig()
    }

    // MARK: - Save

    func save(_ config: RepoConfig) throws {
        let dir = saveURL.deletingLastPathComponent()
        try RepoConfigLoader.save(config, dataDirectory: dir)
    }

    // MARK: - File Monitoring

    func startFileMonitoring(onExternalChange: @escaping @Sendable () -> Void) {
        let path = saveURL.path
        fileMonitor = FileMonitor(path: path) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                onExternalChange()
                self.fileMonitor?.restartMonitoring(path: self.saveURL.path)
            }
        }
    }
}

extension RepoPersistence: RepoPersistenceProtocol {}
