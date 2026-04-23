import Foundation
import XCTest

@testable import TermQShared

final class LocalYNHConfigTests: XCTestCase {

    // MARK: - LocalYNHConfig

    func testLocalYNHConfig_defaultInit() {
        let config = LocalYNHConfig()
        XCTAssertTrue(config.worktreeHarness.isEmpty)
        XCTAssertTrue(config.repoHarness.isEmpty)
        XCTAssertNil(config.preferredVendor)
    }

    func testLocalYNHConfig_init_withValues() {
        let config = LocalYNHConfig(
            worktreeHarness: ["/path/wt": "harness1"],
            repoHarness: ["/path/repo": "harness2"],
            preferredVendor: "claude"
        )
        XCTAssertEqual(config.worktreeHarness["/path/wt"], "harness1")
        XCTAssertEqual(config.repoHarness["/path/repo"], "harness2")
        XCTAssertEqual(config.preferredVendor, "claude")
    }

    func testLocalYNHConfig_codableRoundTrip() throws {
        let original = LocalYNHConfig(
            worktreeHarness: ["/wt1": "h1", "/wt2": "h2"],
            repoHarness: ["/repo": "h3"],
            preferredVendor: "claude"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LocalYNHConfig.self, from: data)
        XCTAssertEqual(decoded.worktreeHarness, original.worktreeHarness)
        XCTAssertEqual(decoded.repoHarness, original.repoHarness)
        XCTAssertEqual(decoded.preferredVendor, original.preferredVendor)
    }

    func testLocalYNHConfig_backwardCompat_missingRepoHarness() throws {
        let json = """
            {"worktreeHarness": {"/path": "h1"}}
            """
        let config = try JSONDecoder().decode(LocalYNHConfig.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(config.worktreeHarness["/path"], "h1")
        XCTAssertTrue(config.repoHarness.isEmpty)
        XCTAssertNil(config.preferredVendor)
    }

    func testLocalYNHConfig_backwardCompat_emptyObject() throws {
        let config = try JSONDecoder().decode(LocalYNHConfig.self, from: "{}".data(using: .utf8)!)
        XCTAssertTrue(config.worktreeHarness.isEmpty)
        XCTAssertTrue(config.repoHarness.isEmpty)
        XCTAssertNil(config.preferredVendor)
    }

    func testLocalYNHConfig_backwardCompat_missingWorktreeHarness() throws {
        let json = """
            {"repoHarness": {"/r": "h"}}
            """
        let config = try JSONDecoder().decode(LocalYNHConfig.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(config.worktreeHarness.isEmpty)
        XCTAssertEqual(config.repoHarness["/r"], "h")
    }

    func testLocalYNHConfig_nilPreferredVendor() throws {
        let json = """
            {"worktreeHarness":{}, "repoHarness":{}}
            """
        let config = try JSONDecoder().decode(LocalYNHConfig.self, from: json.data(using: .utf8)!)
        XCTAssertNil(config.preferredVendor)
    }

    // MARK: - YNHConfigLoader URLs

    func testYNHConfigLoader_getConfigURL_customDirectory() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString)")
        let url = YNHConfigLoader.getConfigURL(dataDirectory: dir)
        XCTAssertEqual(url.lastPathComponent, "ynh.json")
        XCTAssertTrue(url.path.hasPrefix(dir.path))
    }

    // MARK: - YNHConfigLoader Load

    func testYNHConfigLoader_load_fileNotFound_returnsDefault() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let config = try YNHConfigLoader.load(dataDirectory: dir)
        XCTAssertTrue(config.worktreeHarness.isEmpty)
        XCTAssertTrue(config.repoHarness.isEmpty)
    }

    func testYNHConfigLoader_load_validFile() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let original = LocalYNHConfig(
            worktreeHarness: ["/wt": "myharness"],
            repoHarness: [:],
            preferredVendor: "claude"
        )
        try YNHConfigLoader.save(original, dataDirectory: dir)

        let loaded = try YNHConfigLoader.load(dataDirectory: dir)
        XCTAssertEqual(loaded.worktreeHarness["/wt"], "myharness")
        XCTAssertEqual(loaded.preferredVendor, "claude")
    }

    func testYNHConfigLoader_load_invalidJSON_throwsDecodingFailed() throws {
        let dir = tempDir()
        defer { cleanup(dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let configURL = dir.appendingPathComponent("ynh.json")
        try "{ invalid json ".write(to: configURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try YNHConfigLoader.load(dataDirectory: dir)) { error in
            guard case YNHConfigLoader.LoadError.decodingFailed = error else {
                XCTFail("Expected decodingFailed, got: \(error)")
                return
            }
        }
    }

    // MARK: - YNHConfigLoader Save

    func testYNHConfigLoader_save_roundTrip() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let config = LocalYNHConfig(
            worktreeHarness: ["/a": "x", "/b": "y"],
            repoHarness: ["/c": "z"],
            preferredVendor: nil
        )
        try YNHConfigLoader.save(config, dataDirectory: dir)
        let loaded = try YNHConfigLoader.load(dataDirectory: dir)

        XCTAssertEqual(loaded.worktreeHarness, config.worktreeHarness)
        XCTAssertEqual(loaded.repoHarness, config.repoHarness)
        XCTAssertNil(loaded.preferredVendor)
    }

    func testYNHConfigLoader_save_createsDirectoryIfNeeded() throws {
        let nested = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-\(UUID().uuidString)")
            .appendingPathComponent("nested")
        defer { try? FileManager.default.removeItem(at: nested.deletingLastPathComponent()) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.path))
        try YNHConfigLoader.save(LocalYNHConfig(), dataDirectory: nested)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: nested.appendingPathComponent("ynh.json").path))
    }

    func testYNHConfigLoader_save_overwritesExistingFile() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let first = LocalYNHConfig(worktreeHarness: ["/first": "h1"])
        try YNHConfigLoader.save(first, dataDirectory: dir)

        let second = LocalYNHConfig(worktreeHarness: ["/second": "h2"])
        try YNHConfigLoader.save(second, dataDirectory: dir)

        let loaded = try YNHConfigLoader.load(dataDirectory: dir)
        XCTAssertNil(loaded.worktreeHarness["/first"])
        XCTAssertEqual(loaded.worktreeHarness["/second"], "h2")
    }

    // MARK: - Error Descriptions

    func testLoadError_decodingFailed_description() {
        let error = YNHConfigLoader.LoadError.decodingFailed("bad JSON")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("bad JSON"))
    }

    func testLoadError_coordinationFailed_description() {
        let error = YNHConfigLoader.LoadError.coordinationFailed("locked")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("locked"))
    }

    func testSaveError_encodingFailed_description() {
        let error = YNHConfigLoader.SaveError.encodingFailed("cannot encode")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("cannot encode"))
    }

    func testSaveError_writeFailed_description() {
        let error = YNHConfigLoader.SaveError.writeFailed("disk full")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("disk full"))
    }

    func testSaveError_coordinationFailed_description() {
        let error = YNHConfigLoader.SaveError.coordinationFailed("busy")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("busy"))
    }

    // MARK: - Helpers

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ynhtest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
