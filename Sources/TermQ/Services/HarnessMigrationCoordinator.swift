import Foundation
import TermQShared

/// Drives the one-shot YNH 0.2 → 0.3 canonical-id migration on TermQ's
/// side: detects when YNH's `~/.ynh/.schema-version < 2`, runs
/// `ynh migrate --json --skip-broken`, parses the resulting manifest,
/// and rewrites TermQ-side persisted ids in `YNHPersistence`.
///
/// Hook into the detector status flow: when YNH transitions to
/// `.ready`, call `runIfNeeded(...)` once. Subsequent transitions
/// re-check via the `lastAppliedManifestSchema` UserDefault flag and
/// no-op when the manifest has already been applied.
///
/// The coordinator surfaces quarantined entries via `quarantinedEntries`
/// for the sidebar's quarantine group to render. Migration failures are
/// surfaced via `lastError`.
@MainActor
final class HarnessMigrationCoordinator: ObservableObject {
    /// Quarantined entries returned by the most recent `ynh migrate` or
    /// `ynh quarantine list` call. Empty when there's nothing in
    /// `~/.ynh/.quarantine/broken/`.
    @Published private(set) var quarantinedEntries: [QuarantineEntry] = []
    @Published private(set) var lastError: String?

    private let persistence: YNHPersistence
    private let commandRunner: any YNHCommandRunner
    private let userDefaults: UserDefaults

    /// Persisted UserDefault key recording the schema version that the
    /// last `migrateCanonicalIds` call rewrote against. When the live
    /// envelope's `schema_version` matches this value, the migration
    /// has already been applied to TermQ-side persisted ids.
    private static let lastAppliedKey = "TermQ.harnessMigration.lastAppliedSchema"

    init(
        persistence: YNHPersistence = .shared,
        commandRunner: any YNHCommandRunner = LiveYNHCommandRunner(),
        userDefaults: UserDefaults = .standard
    ) {
        self.persistence = persistence
        self.commandRunner = commandRunner
        self.userDefaults = userDefaults
    }

    /// Returns true if `migrateCanonicalIds` has already been applied
    /// against the given schema version. Used to no-op subsequent
    /// detector-ready transitions.
    func hasApplied(forSchema schemaVersion: Int) -> Bool {
        let last = userDefaults.integer(forKey: Self.lastAppliedKey)
        return last >= schemaVersion
    }

    /// Detects schema state and runs migration if needed.
    /// - Parameters:
    ///   - schemaVersion: Value from the most recent `ynh ls` envelope.
    ///     `nil` is treated as pre-migration.
    ///   - ynhPath: Path to the ynh binary (from the detector).
    ///   - environment: Environment for the migrate invocation.
    func runIfNeeded(
        schemaVersion: Int?,
        ynhPath: String,
        environment: [String: String]
    ) async {
        let liveSchema = schemaVersion ?? 1
        TermQLogger.session.debug(
            "HarnessMigration: runIfNeeded entered, liveSchema=\(liveSchema)"
        )
        if hasApplied(forSchema: liveSchema) {
            TermQLogger.session.debug(
                "HarnessMigration: already applied for schema \(liveSchema), refreshing quarantine only"
            )
            await refreshQuarantineList(ynhPath: ynhPath, environment: environment)
            return
        }

        // Always apply the on-disk manifest first if it exists. Covers
        // the case where YNH migrated `~/.ynh` in a prior session and
        // wrote `.migration-manifest.json`, but TermQ-side persistence
        // hasn't been rewritten yet — i.e. user upgrades TermQ after
        // already being on a schema-2 YNH binary.
        await applyManifestIfPresent()

        if liveSchema < 2 {
            // YNH-side `~/.ynh` not yet at schema 2 — invoke migrate to
            // do the directory layout pass and emit a fresh manifest.
            // The new manifest is then re-applied to catch any entries
            // that didn't exist in the on-disk manifest above.
            TermQLogger.session.debug("HarnessMigration: liveSchema<2, calling ynh migrate")
            _ = await runMigrate(ynhPath: ynhPath, environment: environment)
        }

        userDefaults.set(max(liveSchema, 2), forKey: Self.lastAppliedKey)
        await refreshQuarantineList(ynhPath: ynhPath, environment: environment)
    }

    // MARK: - Manifest

    /// Run `ynh migrate --json --skip-broken`, parse the manifest, and
    /// apply any `old_id → new_id` rewrites to TermQ-side persisted
    /// state. Returns the parsed manifest (or nil on failure).
    private func runMigrate(ynhPath: String, environment: [String: String]) async -> MigrationManifest? {
        do {
            let result = try await commandRunner.run(
                executable: ynhPath,
                arguments: ["migrate", "--json", "--skip-broken"],
                environment: environment
            )
            guard result.didSucceed else {
                lastError = ynhErrorMessage(from: result.stderr) ?? "Migration failed"
                TermQLogger.session.error(
                    "HarnessMigration: ynh migrate exit=\(result.exitCode)"
                )
                return nil
            }
            let manifest = try JSONDecoder().decode(
                MigrationManifest.self,
                from: Data(result.stdout.utf8)
            )
            applyManifest(manifest)
            return manifest
        } catch {
            lastError = error.localizedDescription
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.session.error(
                    "HarnessMigration: ynh migrate failed: \(error.localizedDescription)"
                )
            } else {
                TermQLogger.session.error("HarnessMigration: ynh migrate failed")
            }
            return nil
        }
    }

    /// Read `~/.ynh/.migration-manifest.json` if present and apply.
    /// Used when the binary is already at schema 2 from a prior session.
    private func applyManifestIfPresent() async {
        let manifestURL = ynhHome.appendingPathComponent(".migration-manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            TermQLogger.session.debug(
                "HarnessMigration: manifest file not readable at \(manifestURL.path)"
            )
            return
        }
        do {
            let manifest = try JSONDecoder().decode(MigrationManifest.self, from: data)
            TermQLogger.session.debug(
                "HarnessMigration: manifest decoded, entries=\(manifest.entries?.count ?? 0)"
            )
            applyManifest(manifest)
        } catch {
            TermQLogger.session.error(
                "HarnessMigration: manifest decode failed: \(error.localizedDescription)"
            )
        }
    }

    private func applyManifest(_ manifest: MigrationManifest) {
        let entries = manifest.entries ?? []
        if !entries.isEmpty {
            // YNH manifests can contain multiple entries with the same
            // `old_id` (e.g. one entry per `kind` for the same harness).
            // Last write wins — they all map to the same destination.
            var map: [String: String] = [:]
            for entry in entries {
                map[entry.oldID] = entry.newID
            }
            TermQLogger.session.debug(
                "HarnessMigration: applying \(entries.count) entries (\(map.count) unique) to YNHPersistence"
            )
            persistence.migrateCanonicalIds(using: map)
        }
        quarantinedEntries = manifest.quarantined ?? []
        TermQLogger.session.debug(
            "HarnessMigration: applyManifest done; quarantined=\(quarantinedEntries.count)"
        )
    }

    // MARK: - Quarantine list refresh

    /// Refresh the quarantine list independently of migration. Called
    /// after migration and any time the sidebar wants up-to-date data.
    func refreshQuarantineList(ynhPath: String, environment: [String: String]) async {
        do {
            let result = try await commandRunner.run(
                executable: ynhPath,
                arguments: ["quarantine", "list", "--format", "json"],
                environment: environment
            )
            guard result.didSucceed else { return }
            let entries = try JSONDecoder().decode(
                [QuarantineEntry].self,
                from: Data(result.stdout.utf8)
            )
            quarantinedEntries = entries
        } catch {
            // Quarantine list can fail silently — if `ynh quarantine`
            // doesn't exist on this binary, there are no quarantined
            // entries to surface. Don't poison the migration error
            // state with a benign decode failure.
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.session.info(
                    "HarnessMigration: quarantine list unavailable: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Restore a quarantined entry and refresh the list.
    func restoreQuarantine(name: String, ynhPath: String, environment: [String: String]) async {
        let result = try? await commandRunner.run(
            executable: ynhPath,
            arguments: ["quarantine", "restore", name],
            environment: environment
        )
        if let result, !result.didSucceed {
            lastError = ynhErrorMessage(from: result.stderr) ?? "Restore failed"
        }
        await refreshQuarantineList(ynhPath: ynhPath, environment: environment)
    }

    /// Drop a quarantined entry permanently and refresh the list.
    func dropQuarantine(name: String, ynhPath: String, environment: [String: String]) async {
        let result = try? await commandRunner.run(
            executable: ynhPath,
            arguments: ["quarantine", "drop", name],
            environment: environment
        )
        if let result, !result.didSucceed {
            lastError = ynhErrorMessage(from: result.stderr) ?? "Drop failed"
        }
        await refreshQuarantineList(ynhPath: ynhPath, environment: environment)
    }

    // MARK: - Helpers

    private var ynhHome: URL {
        if let override = ProcessInfo.processInfo.environment["YNH_HOME"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ynh", isDirectory: true)
    }
}

// MARK: - Manifest types

struct MigrationManifest: Codable, Sendable {
    let schemaVersion: Int?
    let migratedAt: String?
    let action: String?
    let entries: [ManifestEntry]?
    let quarantined: [QuarantineEntry]?

    enum CodingKeys: String, CodingKey {
        case action
        case schemaVersion = "schema_version"
        case migratedAt = "migrated_at"
        case entries
        case quarantined
    }
}

struct ManifestEntry: Codable, Sendable {
    let oldID: String
    let newID: String
    let vendor: String?

    enum CodingKeys: String, CodingKey {
        case oldID = "old_id"
        case newID = "new_id"
        case vendor
    }
}

/// One entry in `ynh quarantine list --format json` or in the manifest's
/// `quarantined` array. Same shape on both surfaces.
public struct QuarantineEntry: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let path: String?
    public let originalPath: String?
    public let reason: String

    enum CodingKeys: String, CodingKey {
        case name, path, reason
        case originalPath = "original_path"
    }
}
