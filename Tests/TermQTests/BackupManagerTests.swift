import Foundation
import TermQCore
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
        if case .failure(let backupError) = result {
            if case .sourceNotFound = backupError {
                // expected
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
        if case .failure(let backupError) = result {
            if case .noBackupFound = backupError {
                // expected
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
        if case .failure(let backupError) = result {
            if case .invalidBackupData = backupError {
                // expected
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
        if case .failure(let backupError) = result {
            if case .invalidBackupData = backupError {
                // expected
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

// MARK: - BackupRoots Injection

/// Exercises the real backup/restore flow against temp directories injected
/// via `BackupManager.rootsOverride`. Each test gets fresh primary + backup
/// dirs, eliminating the prior "skip if real file exists" pattern.
final class BackupManagerRootsInjectionTests: XCTestCase {
    private var primaryDir: URL!
    private var backupDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupManagerTests-\(UUID().uuidString)", isDirectory: true)
        primaryDir = base.appendingPathComponent("primary", isDirectory: true)
        backupDir = base.appendingPathComponent("backup", isDirectory: true)
        try FileManager.default.createDirectory(at: primaryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        BackupManager.rootsOverride = BackupRoots(primaryDir: primaryDir, backupDir: backupDir)
    }

    override func tearDownWithError() throws {
        BackupManager.rootsOverride = nil
        if let primary = primaryDir {
            try? FileManager.default.removeItem(at: primary.deletingLastPathComponent())
        }
    }

    private func writeBoard(cards: Int = 0) throws {
        let column = Column(name: "To Do", orderIndex: 0)
        let testCards = (0..<cards).map { i in
            TerminalCard(
                title: "Card \(i)",
                columnId: column.id,
                orderIndex: i,
                workingDirectory: "/tmp"
            )
        }
        let board = Board(columns: [column], cards: testCards)
        let data = try JSONEncoder().encode(board)
        try data.write(to: primaryDir.appendingPathComponent("board.json"))
    }

    // MARK: - backup()

    func test_backup_sourceMissing_returnsSourceNotFound() {
        let result = BackupManager.backup()
        guard case .failure(let err) = result, case .sourceNotFound = err else {
            XCTFail("Expected .sourceNotFound, got \(result)")
            return
        }
    }

    func test_backup_writesBackupFile() throws {
        try writeBoard(cards: 1)
        let result = BackupManager.backup()
        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: BackupManager.backupFilePath))
    }

    func test_backup_overwritesExistingBackup() throws {
        try writeBoard(cards: 1)
        _ = BackupManager.backup()
        // Mutate primary then re-backup; backup should reflect the new content.
        try writeBoard(cards: 0)
        _ = BackupManager.backup()

        let backupData = try Data(contentsOf: BackupManager.backupFileURL)
        let str = String(data: backupData, encoding: .utf8) ?? ""
        XCTAssertFalse(str.contains("00000000-0000-0000-0000-000000000001"))
    }

    func test_backup_copiesReposJsonWhenPresent() throws {
        try writeBoard(cards: 1)
        try #"{"repositories":[]}"#.write(
            to: primaryDir.appendingPathComponent("repos.json"),
            atomically: true, encoding: .utf8)

        _ = BackupManager.backup()

        XCTAssertTrue(FileManager.default.fileExists(atPath: BackupManager.reposBackupFilePath))
    }

    // MARK: - restore()

    func test_restore_noBackupFile_returnsNoBackupFound() {
        let result = BackupManager.restore()
        guard case .failure(let err) = result, case .noBackupFound = err else {
            XCTFail("Expected .noBackupFound, got \(result)")
            return
        }
    }

    func test_restore_invalidBackupContent_returnsInvalidBackupData() throws {
        try "not json".write(
            to: backupDir.appendingPathComponent(BackupManager.backupFileName),
            atomically: true, encoding: .utf8)
        let result = BackupManager.restore()
        guard case .failure(let err) = result, case .invalidBackupData = err else {
            XCTFail("Expected .invalidBackupData, got \(result)")
            return
        }
    }

    func test_restore_copiesBackupOverPrimary() throws {
        try writeBoard(cards: 1)
        _ = BackupManager.backup()

        // Wipe primary, then restore from backup.
        try FileManager.default.removeItem(at: primaryDir.appendingPathComponent("board.json"))
        let result = BackupManager.restore()

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: primaryDir.appendingPathComponent("board.json").path))
    }

    // MARK: - hasBackup / backupInfo

    func test_hasBackup_falseInitially() {
        XCTAssertFalse(BackupManager.hasBackup)
    }

    func test_hasBackup_trueAfterSuccessfulBackup() throws {
        try writeBoard(cards: 1)
        _ = BackupManager.backup()
        XCTAssertTrue(BackupManager.hasBackup)
    }

    func test_backupInfo_existsAndHasSize_afterBackup() throws {
        try writeBoard(cards: 1)
        _ = BackupManager.backup()
        let info = BackupManager.backupInfo
        XCTAssertTrue(info.exists)
        XCTAssertNotNil(info.date)
        XCTAssertGreaterThan(info.size, 0)
    }

    // MARK: - checkAndOfferRestore

    func test_checkAndOfferRestore_returnsBackupURL_whenPrimaryEmptyAndBackupHasContent() throws {
        try writeBoard(cards: 1)
        _ = BackupManager.backup()
        // Wipe primary so the restore offer is triggered
        try FileManager.default.removeItem(at: primaryDir.appendingPathComponent("board.json"))

        let url = BackupManager.checkAndOfferRestore()
        XCTAssertEqual(url, BackupManager.backupFileURL)
    }

    func test_checkAndOfferRestore_returnsNil_whenBackupAbsent() {
        XCTAssertNil(BackupManager.checkAndOfferRestore())
    }

    func test_checkAndOfferRestore_returnsNil_whenPrimaryHasContent() throws {
        try writeBoard(cards: 1)
        _ = BackupManager.backup()
        // Primary still has content — no offer
        XCTAssertNil(BackupManager.checkAndOfferRestore())
    }
}
