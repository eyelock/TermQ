import Foundation
import XCTest

@testable import TermQShared

final class HarnessManifestLayoutTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("manifest-layout-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func touch(_ relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url)
    }

    func test_noManifest_resolvesNil_andWritesCanonical() {
        XCTAssertNil(HarnessManifestLayout.resolve(at: root.path))
        XCTAssertNil(HarnessManifestLayout.manifestURL(at: root.path))
        XCTAssertEqual(HarnessManifestLayout.writeDir(at: root.path), ".agents/harness")
    }

    func test_canonicalOnly() throws {
        try touch(".agents/harness/plugin.json")
        let resolution = try XCTUnwrap(HarnessManifestLayout.resolve(at: root.path))
        XCTAssertEqual(resolution.state, .canonical)
        XCTAssertEqual(resolution.dir, ".agents/harness")
        XCTAssertFalse(resolution.needsAttention)
    }

    func test_legacyOnly_flagged_andWrittenInPlace() throws {
        try touch(".ynh-plugin/plugin.json")
        let resolution = try XCTUnwrap(HarnessManifestLayout.resolve(at: root.path))
        XCTAssertEqual(resolution.state, .legacy)
        XCTAssertTrue(resolution.needsAttention)
        XCTAssertEqual(HarnessManifestLayout.writeDir(at: root.path), ".ynh-plugin")
    }

    func test_both_canonicalWins_andFlagged() throws {
        try touch(".agents/harness/plugin.json")
        try touch(".ynh-plugin/plugin.json")
        let resolution = try XCTUnwrap(HarnessManifestLayout.resolve(at: root.path))
        XCTAssertEqual(resolution.state, .both)
        XCTAssertEqual(resolution.dir, ".agents/harness")
        XCTAssertTrue(resolution.needsAttention)
    }

    func test_otherAgentsContent_isNotAHarness() throws {
        try touch(".agents/skills/x/SKILL.md")
        XCTAssertNil(HarnessManifestLayout.resolve(at: root.path))
        XCTAssertFalse(HarnessManifestLayout.hasManifestDir(at: root.path))
    }

    func test_hasManifestDir_acceptsEitherLayout() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".ynh-plugin"), withIntermediateDirectories: true)
        XCTAssertTrue(HarnessManifestLayout.hasManifestDir(at: root.path))
    }
}
