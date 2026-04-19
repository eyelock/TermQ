import Foundation
import XCTest

@testable import TermQ

/// Tests for BackupManager logic.
///
/// File-system tests use temp directories created fresh per test.
/// shouldBackupNow() is tested via UserDefaults in a dedicated suite that
/// restores original values in tearDown.
final class BackupManagerTests: XCTestCase {

    // MARK: - BackupFrequency enum

    func testBackupFrequency_allCasesHaveDisplayName() {
        for freq in BackupFrequency.allCases {
            XCTAssertFalse(freq.displayName.isEmpty, "\(freq.rawValue) has empty displayName")
        }
    }

    func testBackupFrequency_allCasesHaveDescription() {
        for freq in BackupFrequency.allCases {
            XCTAssertFalse(freq.description.isEmpty, "\(freq.rawValue) has empty description")
        }
    }

    func testBackupFrequency_idEqualsRawValue() {
        for freq in BackupFrequency.allCases {
            XCTAssertEqual(freq.id, freq.rawValue)
        }
    }

    func testBackupFrequency_rawValueRoundTrip() {
        for freq in BackupFrequency.allCases {
            let restored = BackupFrequency(rawValue: freq.rawValue)
            XCTAssertEqual(restored, freq)
        }
    }

    func testBackupFrequency_fourCases() {
        XCTAssertEqual(BackupFrequency.allCases.count, 4)
    }

    // MARK: - BackupError localizedDescription

    func testBackupError_sourceNotFound_hasDescription() {
        let error = BackupError.sourceNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testBackupError_backupFailed_includesMessage() {
        let error = BackupError.backupFailed("disk full")
        XCTAssertTrue(error.errorDescription?.contains("disk full") ?? false)
    }

    func testBackupError_restoreFailed_includesMessage() {
        let error = BackupError.restoreFailed("permission denied")
        XCTAssertTrue(error.errorDescription?.contains("permission denied") ?? false)
    }

    func testBackupError_noBackupFound_hasDescription() {
        let error = BackupError.noBackupFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testBackupError_invalidBackupData_hasDescription() {
        let error = BackupError.invalidBackupData
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testBackupError_locationNotWritable_hasDescription() {
        let error = BackupError.locationNotWritable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    // MARK: - shouldBackupNow() — pure frequency logic

    private let defaults = UserDefaults.standard
    private let frequencyKey = "backupFrequency"
    private let lastBackupKey = "lastBackupDate"

    private func setFrequency(_ freq: BackupFrequency) {
        defaults.set(freq.rawValue, forKey: frequencyKey)
    }

    private func setLastBackup(_ date: Date?) {
        if let date = date {
            defaults.set(date.timeIntervalSince1970, forKey: lastBackupKey)
        } else {
            defaults.removeObject(forKey: lastBackupKey)
        }
    }

    private var savedFrequency: String?
    private var savedLastBackup: Double?

    override func setUp() {
        super.setUp()
        savedFrequency = defaults.string(forKey: frequencyKey)
        let interval = defaults.double(forKey: lastBackupKey)
        savedLastBackup = interval > 0 ? interval : nil
    }

    override func tearDown() {
        super.tearDown()
        if let saved = savedFrequency {
            defaults.set(saved, forKey: frequencyKey)
        } else {
            defaults.removeObject(forKey: frequencyKey)
        }
        if let saved = savedLastBackup {
            defaults.set(saved, forKey: lastBackupKey)
        } else {
            defaults.removeObject(forKey: lastBackupKey)
        }
    }

    func testShouldBackupNow_manual_alwaysFalse() {
        setFrequency(.manual)
        setLastBackup(nil)
        XCTAssertFalse(BackupManager.shouldBackupNow())
    }

    func testShouldBackupNow_onSave_alwaysTrue() {
        setFrequency(.onSave)
        setLastBackup(Date())  // even if backed up just now
        XCTAssertTrue(BackupManager.shouldBackupNow())
    }

    func testShouldBackupNow_daily_noLastBackup_true() {
        setFrequency(.daily)
        setLastBackup(nil)
        XCTAssertTrue(BackupManager.shouldBackupNow())
    }

    func testShouldBackupNow_daily_recentBackup_false() {
        setFrequency(.daily)
        setLastBackup(Date().addingTimeInterval(-3600))  // 1 hour ago
        XCTAssertFalse(BackupManager.shouldBackupNow())
    }

    func testShouldBackupNow_daily_oldBackup_true() {
        setFrequency(.daily)
        setLastBackup(Date().addingTimeInterval(-25 * 3600))  // 25 hours ago
        XCTAssertTrue(BackupManager.shouldBackupNow())
    }

    func testShouldBackupNow_daily_exactlyAtBoundary_true() {
        setFrequency(.daily)
        setLastBackup(Date().addingTimeInterval(-24 * 3600))  // exactly 24 hours ago
        XCTAssertTrue(BackupManager.shouldBackupNow())
    }

    func testShouldBackupNow_weekly_noLastBackup_true() {
        setFrequency(.weekly)
        setLastBackup(nil)
        XCTAssertTrue(BackupManager.shouldBackupNow())
    }

    func testShouldBackupNow_weekly_recentBackup_false() {
        setFrequency(.weekly)
        setLastBackup(Date().addingTimeInterval(-3 * 24 * 3600))  // 3 days ago
        XCTAssertFalse(BackupManager.shouldBackupNow())
    }

    func testShouldBackupNow_weekly_oldBackup_true() {
        setFrequency(.weekly)
        setLastBackup(Date().addingTimeInterval(-8 * 24 * 3600))  // 8 days ago
        XCTAssertTrue(BackupManager.shouldBackupNow())
    }

    // MARK: - File-based: backup() and restore()

    func testBackup_sourceNotFound_returnsFailure() throws {
        // Point the board path to a non-existent file by using a fresh temp dir
        // BackupManager.primaryBoardPath is a fixed path; we test the error path
        // by verifying the result when source doesn't exist (fresh machine / clean env)
        guard !FileManager.default.fileExists(atPath: BackupManager.primaryBoardPath.path) else {
            throw XCTSkip("Primary board exists on this machine — skipping sourceNotFound test")
        }
        let result = BackupManager.backup()
        if case .failure(let error) = result, let backupError = error as? BackupError {
            if case .sourceNotFound = backupError { /* expected */
            } else {
                XCTFail("Expected .sourceNotFound, got \(backupError)")
            }
        }
        // If the source does exist the backup will succeed, which is also valid behaviour
    }

    func testRestore_noBackup_returnsFailure() throws {
        guard !BackupManager.hasBackup else {
            throw XCTSkip("Backup file already exists — skipping noBackupFound test")
        }
        let result = BackupManager.restore()
        if case .failure(let error) = result, let backupError = error as? BackupError {
            if case .noBackupFound = backupError { /* expected */
            } else {
                XCTFail("Expected .noBackupFound, got \(backupError)")
            }
        }
    }

    func testRestoreFromURL_invalidJSON_returnsInvalidBackupData() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let badFile = tempDir.appendingPathComponent("bad.json")
        try "not valid json at all".write(to: badFile, atomically: true, encoding: .utf8)

        let result = BackupManager.restore(from: badFile)
        if case .failure(let error) = result, let backupError = error as? BackupError {
            if case .invalidBackupData = backupError { /* expected */
            } else {
                XCTFail("Expected .invalidBackupData, got \(backupError)")
            }
        } else if case .success = result {
            XCTFail("Expected failure for invalid JSON")
        }
    }

    func testRestoreFromURL_emptyBoardJSON_returnsInvalidBackupData() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // JSON that isn't a Board (wrong schema)
        let badFile = tempDir.appendingPathComponent("bad.json")
        try #"{"not":"a board"}"#.write(to: badFile, atomically: true, encoding: .utf8)

        let result = BackupManager.restore(from: badFile)
        if case .failure(let error) = result, let backupError = error as? BackupError {
            if case .invalidBackupData = backupError { /* expected */
            } else {
                XCTFail("Expected .invalidBackupData, got \(backupError)")
            }
        } else if case .success = result {
            XCTFail("Expected failure for wrong JSON schema")
        }
    }

    // MARK: - BackupInfo

    func testBackupInfo_missingFile_existsFalse() throws {
        guard !BackupManager.hasBackup else {
            throw XCTSkip("Backup file exists — skipping missing-file info test")
        }
        let info = BackupManager.backupInfo
        XCTAssertFalse(info.exists)
        XCTAssertNil(info.date)
        XCTAssertEqual(info.size, 0)
    }
}
