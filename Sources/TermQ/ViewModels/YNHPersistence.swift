import Foundation
import TermQShared

/// Handles ynh.json persistence.
///
/// Follows the `RepoPersistence` pattern: owns the save URL, delegates encode/decode
/// to `YNHConfigLoader` (which uses NSFileCoordinator).
@MainActor
final class YNHPersistence: ObservableObject, YNHPersistenceProtocol {
    static let shared = YNHPersistence()

    @Published private(set) var config = LocalYNHConfig()
    let saveURL: URL

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
        saveURL = termqDir.appendingPathComponent("ynh.json")
        config = (try? YNHConfigLoader.load(dataDirectory: termqDir)) ?? LocalYNHConfig()
    }

    // MARK: - Queries

    /// Explicit harness override for a specific worktree path.
    func harness(for worktreePath: String) -> String? {
        config.worktreeHarness[worktreePath]
    }

    /// Repository-level default harness. Independent from worktree overrides.
    func repoDefaultHarness(for repoPath: String) -> String? {
        config.repoHarness[repoPath]
    }

    func worktrees(for harnessName: String) -> [String] {
        config.worktreeHarness
            .compactMap { $0.value == harnessName ? $0.key : nil }
            .sorted()
    }

    // MARK: - Mutations

    func setRepoDefaultHarness(_ harnessName: String?, for repoPath: String) {
        if let name = harnessName {
            config.repoHarness[repoPath] = name
        } else {
            config.repoHarness.removeValue(forKey: repoPath)
        }
        do {
            try YNHConfigLoader.save(config, dataDirectory: saveURL.deletingLastPathComponent())
        } catch {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.session.warning("YNHPersistence: save failed: \(error.localizedDescription)")
            } else {
                TermQLogger.session.warning("YNHPersistence: save failed")
            }
        }
    }

    /// Remove all worktree associations for a harness (called after uninstall).
    func removeAllAssociations(for harnessName: String) {
        let paths = config.worktreeHarness
            .compactMap { $0.value == harnessName ? $0.key : nil }
        for path in paths {
            config.worktreeHarness.removeValue(forKey: path)
        }
        let repoPaths = config.repoHarness
            .compactMap { $0.value == harnessName ? $0.key : nil }
        for path in repoPaths {
            config.repoHarness.removeValue(forKey: path)
        }
        do {
            try YNHConfigLoader.save(config, dataDirectory: saveURL.deletingLastPathComponent())
        } catch {
            TermQLogger.session.warning("YNHPersistence: save failed")
        }
    }

    func setHarness(_ harnessName: String?, for worktreePath: String) {
        if let name = harnessName {
            config.worktreeHarness[worktreePath] = name
        } else {
            config.worktreeHarness.removeValue(forKey: worktreePath)
        }
        do {
            try YNHConfigLoader.save(config, dataDirectory: saveURL.deletingLastPathComponent())
        } catch {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.session.warning("YNHPersistence: save failed: \(error.localizedDescription)")
            } else {
                TermQLogger.session.warning("YNHPersistence: save failed")
            }
        }
    }
}
