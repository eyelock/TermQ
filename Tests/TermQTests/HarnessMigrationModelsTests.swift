import Foundation
import XCTest

@testable import TermQ

/// Decoder contract tests for the data types `HarnessMigrationCoordinator`
/// consumes: `MigrationManifest` from `ynh migrate --json`, and
/// `QuarantineEntry` from `ynh quarantine list --format json` and the
/// manifest's `quarantined` array.
final class HarnessMigrationModelsTests: XCTestCase {

    // MARK: - MigrationManifest

    func test_migrationManifest_decodesEntriesWithSnakeCaseKeys() throws {
        let json = """
            {
              "schema_version": 2,
              "migrated_at": "2026-05-08T08:14:15Z",
              "action": "migrated",
              "entries": [
                {
                  "old_id": "eyelock-assistants/planner",
                  "new_id": "github.com/eyelock/assistants/planner",
                  "vendor": "claude"
                },
                {
                  "old_id": "researcher",
                  "new_id": "local/researcher"
                }
              ]
            }
            """
        let manifest = try JSONDecoder().decode(
            MigrationManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(manifest.action, "migrated")
        XCTAssertEqual(manifest.entries?.count, 2)
        XCTAssertEqual(manifest.entries?[0].oldID, "eyelock-assistants/planner")
        XCTAssertEqual(manifest.entries?[0].newID, "github.com/eyelock/assistants/planner")
        XCTAssertEqual(manifest.entries?[0].vendor, "claude")
        XCTAssertNil(manifest.entries?[1].vendor)
    }

    /// `--skip-broken` migrations populate `quarantined` alongside `entries`.
    /// The manifest is the single source of truth for quarantine surface
    /// state right after migration; coordinator stores it on the published
    /// `quarantinedEntries` property.
    func test_migrationManifest_decodesQuarantinedAlongsideEntries() throws {
        let json = """
            {
              "schema_version": 2,
              "action": "migrated",
              "entries": [],
              "quarantined": [
                {
                  "name": "broken-harness",
                  "path": "/Users/test/.ynh/.quarantine/broken/broken-harness",
                  "original_path": "/Users/test/.ynh/installed/broken-harness",
                  "reason": "plugin manifest has no name"
                }
              ]
            }
            """
        let manifest = try JSONDecoder().decode(
            MigrationManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.quarantined?.count, 1)
        XCTAssertEqual(manifest.quarantined?[0].name, "broken-harness")
        XCTAssertEqual(manifest.quarantined?[0].reason, "plugin manifest has no name")
        XCTAssertEqual(
            manifest.quarantined?[0].originalPath,
            "/Users/test/.ynh/installed/broken-harness")
    }

    /// A clean run emits a manifest with no entries and no quarantine —
    /// must decode without optional fields blowing up.
    func test_migrationManifest_decodesCleanRun() throws {
        let json = """
            {
              "schema_version": 2,
              "action": "noop"
            }
            """
        let manifest = try JSONDecoder().decode(
            MigrationManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(manifest.action, "noop")
        XCTAssertNil(manifest.entries)
        XCTAssertNil(manifest.quarantined)
    }

    // MARK: - QuarantineEntry

    /// `ynh quarantine list --format json` emits a bare array of entries —
    /// same shape as the manifest's `quarantined` field.
    func test_quarantineList_decodesBareArray() throws {
        let json = """
            [
              {
                "name": "alpha",
                "path": "/Users/test/.ynh/.quarantine/broken/alpha",
                "reason": "missing manifest"
              },
              {
                "name": "beta",
                "reason": "schema mismatch"
              }
            ]
            """
        let entries = try JSONDecoder().decode(
            [QuarantineEntry].self, from: Data(json.utf8))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].name, "alpha")
        XCTAssertEqual(entries[0].path, "/Users/test/.ynh/.quarantine/broken/alpha")
        XCTAssertEqual(entries[0].reason, "missing manifest")
        XCTAssertNil(entries[1].path)
    }

    /// `QuarantineEntry.id` is keyed off `name` so SwiftUI `ForEach` is stable
    /// across refreshes — a quarantined harness keeps its row identity.
    func test_quarantineEntry_idMatchesName() {
        let entry = QuarantineEntry(
            name: "broken",
            path: nil,
            originalPath: nil,
            reason: "test"
        )
        XCTAssertEqual(entry.id, entry.name)
    }
}
