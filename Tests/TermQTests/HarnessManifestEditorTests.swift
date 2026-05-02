import Foundation
import XCTest

@testable import TermQ

final class SemverValidatorTests: XCTestCase {

    func test_valid_basic() {
        XCTAssertTrue(SemverValidator.isValid("0.0.0"))
        XCTAssertTrue(SemverValidator.isValid("1.2.3"))
        XCTAssertTrue(SemverValidator.isValid("10.20.30"))
    }

    func test_valid_prerelease() {
        XCTAssertTrue(SemverValidator.isValid("1.0.0-alpha"))
        XCTAssertTrue(SemverValidator.isValid("1.0.0-alpha.1"))
        XCTAssertTrue(SemverValidator.isValid("1.0.0-rc.1"))
    }

    func test_valid_buildMetadata() {
        XCTAssertTrue(SemverValidator.isValid("1.0.0+build.1"))
        XCTAssertTrue(SemverValidator.isValid("1.0.0-rc.1+sha.abc"))
    }

    func test_invalid_missingComponent() {
        XCTAssertFalse(SemverValidator.isValid("1"))
        XCTAssertFalse(SemverValidator.isValid("1.2"))
        XCTAssertFalse(SemverValidator.isValid("1.2.3.4"))
    }

    func test_invalid_leadingZero() {
        XCTAssertFalse(SemverValidator.isValid("01.2.3"))
        XCTAssertFalse(SemverValidator.isValid("1.02.3"))
    }

    func test_invalid_emptyAndGarbage() {
        XCTAssertFalse(SemverValidator.isValid(""))
        XCTAssertFalse(SemverValidator.isValid("v1.0.0"))
        XCTAssertFalse(SemverValidator.isValid("foo"))
    }
}

// MARK: - HarnessManifestEditor read/write tests

final class HarnessManifestEditorTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("manifest-editor-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(".ynh-plugin"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeManifest(_ json: String) throws {
        let url = tempDir.appendingPathComponent(".ynh-plugin/plugin.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
    }

    private func readManifest() throws -> [String: Any] {
        let url = tempDir.appendingPathComponent(".ynh-plugin/plugin.json")
        let data = try Data(contentsOf: url)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func test_read_returnsAllFields() throws {
        try writeManifest(
            #"""
            {
              "$schema": "x",
              "name": "h",
              "version": "0.1.0",
              "default_vendor": "claude",
              "description": "Test"
            }
            """#)
        let fields = try HarnessManifestEditor.read(at: tempDir.path)
        XCTAssertEqual(fields.version, "0.1.0")
        XCTAssertEqual(fields.defaultVendor, "claude")
        XCTAssertEqual(fields.description, "Test")
    }

    func test_read_missingDescription_returnsEmptyString() throws {
        try writeManifest(
            #"""
            {"name": "h", "version": "0.1.0", "default_vendor": "claude"}
            """#)
        let fields = try HarnessManifestEditor.read(at: tempDir.path)
        XCTAssertEqual(fields.description, "")
    }

    func test_read_missingFile_throws() {
        XCTAssertThrowsError(try HarnessManifestEditor.read(at: "/nonexistent")) { err in
            guard case HarnessManifestEditorError.fileNotFound = err else {
                XCTFail("expected fileNotFound, got \(err)")
                return
            }
        }
    }

    func test_write_preservesUnrelatedFields() throws {
        try writeManifest(
            #"""
            {
              "$schema": "x",
              "name": "h",
              "version": "0.1.0",
              "default_vendor": "claude",
              "includes": [{"git": "https://example.com/repo.git"}]
            }
            """#)
        try HarnessManifestEditor.write(
            at: tempDir.path,
            fields: HarnessManifestFields(
                description: "Updated",
                defaultVendor: "claude",
                version: "0.2.0"
            )
        )
        let manifest = try readManifest()
        XCTAssertEqual(manifest["name"] as? String, "h")
        XCTAssertEqual(manifest["$schema"] as? String, "x")
        XCTAssertEqual(manifest["description"] as? String, "Updated")
        XCTAssertEqual(manifest["version"] as? String, "0.2.0")
        XCTAssertNotNil(manifest["includes"])
    }

    func test_write_emptyDescription_removesKey() throws {
        try writeManifest(
            #"""
            {
              "name": "h", "version": "0.1.0",
              "default_vendor": "claude", "description": "old"
            }
            """#)
        try HarnessManifestEditor.write(
            at: tempDir.path,
            fields: HarnessManifestFields(
                description: "",
                defaultVendor: "claude",
                version: "0.1.0"
            )
        )
        let manifest = try readManifest()
        XCTAssertNil(manifest["description"])
    }

    func test_write_changesVersionAndVendor() throws {
        try writeManifest(
            #"""
            {"name": "h", "version": "0.1.0", "default_vendor": "claude"}
            """#)
        try HarnessManifestEditor.write(
            at: tempDir.path,
            fields: HarnessManifestFields(
                description: "",
                defaultVendor: "codex",
                version: "1.0.0"
            )
        )
        let manifest = try readManifest()
        XCTAssertEqual(manifest["version"] as? String, "1.0.0")
        XCTAssertEqual(manifest["default_vendor"] as? String, "codex")
    }
}
