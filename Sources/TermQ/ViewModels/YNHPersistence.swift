import Foundation
import TermQShared

/// Handles ynh.json persistence.
///
/// Follows the `RepoPersistence` pattern: owns the save URL, delegates encode/decode
/// to `YNHConfigLoader` (which uses NSFileCoordinator).
///
/// Identity contract: all stored harness keys and values use `Harness.id`
/// (namespace-qualified `"namespace/name"` for namespaced installs, bare
/// `name` otherwise). The `migrateLegacyHarnessKeys(using:)` pass rewrites
/// any pre-existing bare-name values to their canonical id form.
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

    /// Explicit harness override for a specific worktree path. Returns the
    /// canonical `Harness.id` (after migration); pre-migration data may
    /// return a bare name.
    func harness(for worktreePath: String) -> String? {
        config.worktreeHarness[worktreePath]
    }

    /// Repository-level default harness id. Independent from worktree overrides.
    func repoDefaultHarness(for repoPath: String) -> String? {
        config.repoHarness[repoPath]
    }

    /// Worktree paths linked to a harness id. Pass `harness.id`.
    func worktrees(forHarnessId harnessId: String) -> [String] {
        config.worktreeHarness
            .compactMap { $0.value == harnessId ? $0.key : nil }
            .sorted()
    }

    func vendorOverride(for harnessId: String) -> String? {
        config.harnessVendor[harnessId]
    }

    /// Last-used review harness id for a repository (Run with Focus sheet).
    func runHarness(for repoPath: String) -> String? {
        config.repoRunHarness[repoPath]
    }

    /// Last-used focus name for a repository. Empty string means no focus.
    func runFocus(for repoPath: String) -> String? {
        config.repoRunFocus[repoPath]
    }

    // MARK: - Mutations

    func setRepoDefaultHarness(_ harnessId: String?, for repoPath: String) {
        if let id = harnessId {
            config.repoHarness[repoPath] = id
        } else {
            config.repoHarness.removeValue(forKey: repoPath)
        }
        save()
    }

    /// Remove all worktree, repo-level, and vendor associations for a harness.
    /// Pass the harness's canonical `id` so the match is unambiguous after
    /// migration; for safety we also drop legacy bare-name and `*/<bareName>`
    /// matches in case migration hasn't run yet.
    func removeAllAssociations(for harnessId: String) {
        let bareName = harnessId.split(separator: "/").last.map(String.init) ?? harnessId

        let matches: (String) -> Bool = { value in
            value == harnessId || value == bareName || value.hasSuffix("/\(bareName)")
        }

        let worktreePaths = config.worktreeHarness.compactMap { matches($0.value) ? $0.key : nil }
        for path in worktreePaths {
            config.worktreeHarness.removeValue(forKey: path)
        }
        let repoPaths = config.repoHarness.compactMap { matches($0.value) ? $0.key : nil }
        for path in repoPaths {
            config.repoHarness.removeValue(forKey: path)
        }
        let vendorKeys = config.harnessVendor.keys.filter(matches)
        for key in vendorKeys {
            config.harnessVendor.removeValue(forKey: key)
        }
        save()
    }

    func setRunHarness(_ harnessId: String?, for repoPath: String) {
        if let id = harnessId {
            config.repoRunHarness[repoPath] = id
        } else {
            config.repoRunHarness.removeValue(forKey: repoPath)
        }
        save()
    }

    func setRunFocus(_ focus: String?, for repoPath: String) {
        if let focus {
            config.repoRunFocus[repoPath] = focus
        } else {
            config.repoRunFocus.removeValue(forKey: repoPath)
        }
        save()
    }

    func remotePRFeedCap(for repoPath: String) -> Int? {
        config.repoRemotePRFeedCap[repoPath]
    }

    func setRemotePRFeedCap(_ cap: Int?, for repoPath: String) {
        if let cap {
            config.repoRemotePRFeedCap[repoPath] = cap
        } else {
            config.repoRemotePRFeedCap.removeValue(forKey: repoPath)
        }
        save()
    }

    func setVendorOverride(_ vendorId: String?, for harnessId: String) {
        if let vendorId, !vendorId.isEmpty {
            config.harnessVendor[harnessId] = vendorId
        } else {
            config.harnessVendor.removeValue(forKey: harnessId)
        }
        save()
    }

    func setHarness(_ harnessId: String?, for worktreePath: String) {
        if let id = harnessId {
            config.worktreeHarness[worktreePath] = id
        } else {
            config.worktreeHarness.removeValue(forKey: worktreePath)
        }
        save()
    }

    // MARK: - Migration

    /// Rewrite any persisted association whose stored value is the bare
    /// `name` of a now-namespaced harness, replacing it with the canonical
    /// `Harness.id`. Idempotent; safe to call after every successful list
    /// refresh. Writes only when at least one entry changed.
    func migrateLegacyHarnessKeys(using harnesses: [Harness]) {
        var nameToId: [String: String] = [:]
        for harness in harnesses where harness.id != harness.name {
            // Only migrate names that unambiguously map to one id. If two
            // harnesses share a bare `name` across namespaces, leave the
            // legacy value alone — there is no safe target.
            if nameToId[harness.name] == nil {
                nameToId[harness.name] = harness.id
            } else {
                nameToId[harness.name] = ""  // sentinel: ambiguous
            }
        }

        var dirty = false

        for (path, value) in config.worktreeHarness {
            if let canonical = nameToId[value], !canonical.isEmpty, canonical != value {
                config.worktreeHarness[path] = canonical
                dirty = true
            }
        }
        for (path, value) in config.repoHarness {
            if let canonical = nameToId[value], !canonical.isEmpty, canonical != value {
                config.repoHarness[path] = canonical
                dirty = true
            }
        }
        for (key, value) in config.harnessVendor {
            if let canonical = nameToId[key], !canonical.isEmpty, canonical != key {
                config.harnessVendor.removeValue(forKey: key)
                config.harnessVendor[canonical] = value
                dirty = true
            }
        }

        if dirty { save() }
    }

    /// Rewrite persisted ids using a deterministic `oldId → newId`
    /// mapping from `ynh migrate --json`. Used during the YNH 0.2 → 0.3
    /// canonical-id migration window: TermQ persists `Harness.id` values
    /// keyed in the old shape (e.g. `"eyelock-assistants/planner"`), and
    /// YNH's migration manifest provides the rewrite map to the new
    /// shape (`"github.com/eyelock/assistants/planner"`).
    ///
    /// Idempotent — re-applying the same map after writes is a no-op.
    /// Caller is responsible for not double-applying a manifest (track
    /// `lastAppliedManifestTimestamp` UserDefault).
    func migrateCanonicalIds(using oldToNew: [String: String]) {
        guard !oldToNew.isEmpty else { return }
        var dirty = false
        var rewriteCount = 0

        // Match by exact id first (the manifest's `old_id` for harnesses
        // YNH already tracked by canonical id), then fall back to leaf-name
        // matching for entries TermQ persisted as `<old-namespace>/<name>`
        // while YNH only tracked them as `<name>` — the persistence-shape
        // mismatch we hit in practice on first cutover migration.
        func resolve(_ value: String) -> String? {
            if let direct = oldToNew[value] { return direct }
            let leaf = value.split(separator: "/").last.map(String.init) ?? value
            if leaf != value, let leafMatch = oldToNew[leaf] { return leafMatch }
            return nil
        }

        for (path, value) in config.worktreeHarness {
            if let canonical = resolve(value), canonical != value {
                config.worktreeHarness[path] = canonical
                dirty = true
                rewriteCount += 1
            }
        }
        for (path, value) in config.repoHarness {
            if let canonical = resolve(value), canonical != value {
                config.repoHarness[path] = canonical
                dirty = true
                rewriteCount += 1
            }
        }
        for (key, _) in config.harnessVendor {
            if let canonical = resolve(key), canonical != key {
                let vendorValue = config.harnessVendor[key]
                config.harnessVendor.removeValue(forKey: key)
                config.harnessVendor[canonical] = vendorValue
                dirty = true
                rewriteCount += 1
            }
        }

        TermQLogger.session.info(
            "YNHPersistence.migrateCanonicalIds: rewrote \(rewriteCount) entries"
        )
        if dirty { save() }
    }

    private func save() {
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
