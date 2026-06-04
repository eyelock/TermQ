import Foundation
import XCTest

@testable import TermQ

final class RepoHarnessScannerTests: XCTestCase {

    private var repoDir: URL!

    override func setUpWithError() throws {
        repoDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("repo-scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoDir)
    }

    // MARK: - Fixture helpers

    private func writeEntry(name: String, at relative: String) throws {
        let base = relative == "." ? repoDir! : repoDir.appendingPathComponent(relative)
        let pluginDir = base.appendingPathComponent(".ynh-plugin")
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let json = ["name": name, "version": "0.1.0", "default_vendor": "claude"]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: pluginDir.appendingPathComponent("plugin.json"))
    }

    private func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(
            at: repoDir.appendingPathComponent(relative), withIntermediateDirectories: true)
    }

    // MARK: - Discovery

    func test_scan_findsEntriesAcrossConventionalLayouts() throws {
        try writeEntry(name: "termq-dev", at: "ynh/termq-dev")
        try writeEntry(name: "gitflow", at: "plugins/gitflow")
        try writeEntry(name: "dev-skills", at: "skills/dev")

        let scan = RepoHarnessScanner.scan(repoPath: repoDir.path)
        XCTAssertEqual(
            scan.entries,
            [
                RepoHarnessEntry(name: "gitflow", relativePath: "plugins/gitflow"),
                RepoHarnessEntry(name: "dev-skills", relativePath: "skills/dev"),
                RepoHarnessEntry(name: "termq-dev", relativePath: "ynh/termq-dev"),
            ]
        )
    }

    func test_scan_rootEmbeddedHarness_reportedAsDot() throws {
        try writeEntry(name: "collective-dev", at: ".")

        let scan = RepoHarnessScanner.scan(repoPath: repoDir.path)
        XCTAssertEqual(scan.entries, [RepoHarnessEntry(name: "collective-dev", relativePath: ".")])
        // Root entry means the whole repo is the harness — nothing nested
        // is scanned and no parent suggestions arise.
        XCTAssertTrue(scan.suggestedParentDirs.isEmpty)
    }

    func test_scan_skipsJunkAndHiddenDirectories() throws {
        try writeEntry(name: "buried", at: "node_modules/pkg")
        try writeEntry(name: "hidden", at: ".cache/entry")
        try writeEntry(name: "real", at: "ynh/real")

        let scan = RepoHarnessScanner.scan(repoPath: repoDir.path)
        XCTAssertEqual(scan.entries.map(\.name), ["real"])
    }

    func test_scan_respectsMaxDepth() throws {
        try writeEntry(name: "shallow", at: "a/shallow")
        try writeEntry(name: "deep", at: "a/b/c/d/deep")

        let scan = RepoHarnessScanner.scan(repoPath: repoDir.path)
        XCTAssertEqual(scan.entries.map(\.name), ["shallow"])
    }

    func test_scan_malformedManifest_skippedNotFatal() throws {
        let pluginDir = repoDir.appendingPathComponent("ynh/broken/.ynh-plugin")
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: pluginDir.appendingPathComponent("plugin.json"))
        try writeEntry(name: "ok", at: "ynh/ok")

        let scan = RepoHarnessScanner.scan(repoPath: repoDir.path)
        XCTAssertEqual(scan.entries.map(\.name), ["ok"])
    }

    func test_scan_emptyRepo_returnsEmptyScan() {
        let scan = RepoHarnessScanner.scan(repoPath: repoDir.path)
        XCTAssertTrue(scan.entries.isEmpty)
        XCTAssertTrue(scan.suggestedParentDirs.isEmpty)
        XCTAssertFalse(scan.hasRegisterScript)
    }

    // MARK: - Suggestions

    func test_suggestedParents_rankedByPopulation() throws {
        try writeEntry(name: "a", at: "ynh/a")
        try writeEntry(name: "b", at: "ynh/b")
        try writeEntry(name: "c", at: "plugins/c")

        let scan = RepoHarnessScanner.scan(repoPath: repoDir.path)
        XCTAssertEqual(scan.suggestedParentDirs, ["ynh", "plugins"])
    }

    func test_suggestedParents_tie_brokenAlphabetically() throws {
        try writeEntry(name: "a", at: "zeta/a")
        try writeEntry(name: "b", at: "alpha/b")

        let scan = RepoHarnessScanner.scan(repoPath: repoDir.path)
        XCTAssertEqual(scan.suggestedParentDirs, ["alpha", "zeta"])
    }

    // MARK: - Name matching & register script

    func test_entryNamed_matchesManifestName() throws {
        try writeEntry(name: "termq-dev", at: "ynh/termq-dev")

        let scan = RepoHarnessScanner.scan(repoPath: repoDir.path)
        XCTAssertEqual(scan.entry(named: "termq-dev")?.relativePath, "ynh/termq-dev")
        XCTAssertNil(scan.entry(named: "other"))
    }

    func test_registerScript_detectedOnlyWhenExecutable() throws {
        try mkdir("scripts")
        let script = repoDir.appendingPathComponent("scripts/ynh-register.sh")
        try Data("#!/bin/sh\n".utf8).write(to: script)

        // Plain file — not executable yet.
        XCTAssertFalse(RepoHarnessScanner.scan(repoPath: repoDir.path).hasRegisterScript)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        XCTAssertTrue(RepoHarnessScanner.scan(repoPath: repoDir.path).hasRegisterScript)
    }
}
