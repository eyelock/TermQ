import Foundation
import TermQShared

/// Handles ynh.json persistence.
///
/// Follows the `RepoPersistence` pattern: owns the save URL, delegates encode/decode
/// to `YNHConfigLoader` (which uses NSFileCoordinator).
@MainActor
final class YNHPersistence: ObservableObject {
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

    func harness(for worktreePath: String) -> String? {
        config.worktreeHarness[worktreePath]
    }

    func worktrees(for harnessName: String) -> [String] {
        config.worktreeHarness
            .compactMap { $0.value == harnessName ? $0.key : nil }
            .sorted()
    }

    // MARK: - Mutations

    func setHarness(_ harnessName: String?, for worktreePath: String) {
        if let name = harnessName {
            config.worktreeHarness[worktreePath] = name
        } else {
            config.worktreeHarness.removeValue(forKey: worktreePath)
        }
        do {
            try YNHConfigLoader.save(config, dataDirectory: saveURL.deletingLastPathComponent())
        } catch {
            TermQLogger.session.warning("YNHPersistence: save failed: \(error.localizedDescription)")
        }
    }
}
