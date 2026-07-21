import Foundation
import XCTest

@testable import TermQ

/// Tests for the publish sheet's pure decision logic — the destination
/// matrix and git-URL identity matching. The async orchestration sits on
/// top of services that have their own suites.
final class PublishHarnessViewModelTests: XCTestCase {

    private var repoDir: URL!

    override func setUpWithError() throws {
        repoDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("publish-vm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoDir)
    }

    private func scan(
        entries: [RepoHarnessEntry],
        suggested: [String] = [],
        hasRegisterScript: Bool = false
    ) -> RepoHarnessScan {
        RepoHarnessScan(
            entries: entries,
            suggestedParentDirs: suggested,
            hasRegisterScript: hasRegisterScript
        )
    }

    // MARK: - Destination matrix

    func test_nameMatch_updatesAtExistingPath_regardlessOfChosenParent() {
        let state = PublishHarnessViewModel.resolveDestinationState(
            name: "termq-dev",
            parentDir: "somewhere/else",
            scan: scan(entries: [RepoHarnessEntry(name: "termq-dev", relativePath: "ynh/termq-dev")]),
            repoPath: repoDir.path
        )
        XCTAssertEqual(state, .updateExisting(relativePath: "ynh/termq-dev"))
    }

    func test_rootEmbeddedEntry_updateTargetsDot() {
        let state = PublishHarnessViewModel.resolveDestinationState(
            name: "collective-dev",
            parentDir: "",
            scan: scan(entries: [RepoHarnessEntry(name: "collective-dev", relativePath: ".")]),
            repoPath: repoDir.path
        )
        XCTAssertEqual(state, .updateExisting(relativePath: "."))
    }

    func test_differentHarnessAtChosenPath_isClash() {
        let state = PublishHarnessViewModel.resolveDestinationState(
            name: "other",
            parentDir: "ynh",
            scan: scan(entries: [RepoHarnessEntry(name: "occupant", relativePath: "ynh/other")]),
            repoPath: repoDir.path
        )
        XCTAssertEqual(state, .clash(existingName: "occupant"))
    }

    func test_existingNonHarnessDirectory_isOccupied() throws {
        try FileManager.default.createDirectory(
            at: repoDir.appendingPathComponent("ynh/taken"), withIntermediateDirectories: true)
        let state = PublishHarnessViewModel.resolveDestinationState(
            name: "taken",
            parentDir: "ynh",
            scan: scan(entries: []),
            repoPath: repoDir.path
        )
        XCTAssertEqual(state, .directoryOccupied)
    }

    func test_freeDestination_isNewEntry() {
        let state = PublishHarnessViewModel.resolveDestinationState(
            name: "fresh",
            parentDir: "ynh",
            scan: scan(entries: [RepoHarnessEntry(name: "other", relativePath: "ynh/other")]),
            repoPath: repoDir.path
        )
        XCTAssertEqual(state, .newEntry)
    }

    func test_emptyParentOrDot_resolvesToBareName() throws {
        try FileManager.default.createDirectory(
            at: repoDir.appendingPathComponent("bare"), withIntermediateDirectories: true)
        for parent in ["", ".", "  "] {
            let state = PublishHarnessViewModel.resolveDestinationState(
                name: "bare",
                parentDir: parent,
                scan: scan(entries: []),
                repoPath: repoDir.path
            )
            XCTAssertEqual(state, .directoryOccupied, "parent: \"\(parent)\"")
        }
    }

    // MARK: - Git URL normalization

    func test_normalizedGitURL_equivalentForms() {
        let forms = [
            "https://github.com/eyelock/collective-core",
            "https://github.com/eyelock/collective-core.git",
            "git@github.com:eyelock/collective-core.git",
            "ssh://git@github.com/eyelock/collective-core",
            "HTTPS://GitHub.com/Eyelock/Collective-Core.git",
            "https://github.com/eyelock/collective-core/",
        ]
        let normalized = Set(forms.compactMap { PublishHarnessViewModel.normalizedGitURL($0) })
        XCTAssertEqual(normalized, ["github.com/eyelock/collective-core"])
    }

    func test_normalizedGitURL_distinctReposStayDistinct() {
        XCTAssertNotEqual(
            PublishHarnessViewModel.normalizedGitURL("https://github.com/eyelock/assistants"),
            PublishHarnessViewModel.normalizedGitURL("https://github.com/eyelock/collective-core")
        )
    }

    func test_normalizedGitURL_emptyAndGarbage() {
        XCTAssertNil(PublishHarnessViewModel.normalizedGitURL(""))
        XCTAssertNil(PublishHarnessViewModel.normalizedGitURL("   "))
    }
}

// MARK: - PublishChangePreview

final class PublishChangePreviewTests: XCTestCase {

    private var sourceDir: URL!
    private var destinationDir: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("publish-preview-test-\(UUID().uuidString)")
        sourceDir = base.appendingPathComponent("source")
        destinationDir = base.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: destinationDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sourceDir.deletingLastPathComponent())
    }

    private func write(_ relative: String, in base: URL, contents: String) throws {
        let url = base.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    func test_diff_reportsAddedModifiedRemoved() throws {
        try write(".ynh-plugin/plugin.json", in: sourceDir, contents: "v2")
        try write("skills/new/SKILL.md", in: sourceDir, contents: "new")
        try write(".ynh-plugin/plugin.json", in: destinationDir, contents: "v1")
        try write("skills/old/SKILL.md", in: destinationDir, contents: "old")

        let plan = HarnessPublishPlan(
            sourcePath: sourceDir.path,
            mode: .enumerated,
            files: [".ynh-plugin", "skills"],
            unresolvedReferences: []
        )
        let changes = PublishChangePreview.diff(plan: plan, destinationPath: destinationDir.path)

        XCTAssertEqual(
            changes,
            [
                PublishChange(path: ".ynh-plugin/plugin.json", kind: .modified),
                PublishChange(path: "skills/new/SKILL.md", kind: .added),
                PublishChange(path: "skills/old/SKILL.md", kind: .removed),
            ]
        )
    }

    func test_diff_identicalTrees_reportNothing() throws {
        try write(".ynh-plugin/plugin.json", in: sourceDir, contents: "same")
        try write(".ynh-plugin/plugin.json", in: destinationDir, contents: "same")

        let plan = HarnessPublishPlan(
            sourcePath: sourceDir.path,
            mode: .enumerated,
            files: [".ynh-plugin"],
            unresolvedReferences: []
        )
        XCTAssertTrue(
            PublishChangePreview.diff(plan: plan, destinationPath: destinationDir.path).isEmpty)
    }

    func test_diff_hostProjectFilesOutsidePlanRoots_neverReported() throws {
        try write(".ynh-plugin/plugin.json", in: sourceDir, contents: "x")
        try write(".ynh-plugin/plugin.json", in: destinationDir, contents: "x")
        // Host project file at a root-embedded destination — not a plan root.
        try write("services/api/main.go", in: destinationDir, contents: "package main")

        let plan = HarnessPublishPlan(
            sourcePath: sourceDir.path,
            mode: .enumerated,
            files: [".ynh-plugin"],
            unresolvedReferences: []
        )
        XCTAssertTrue(
            PublishChangePreview.diff(plan: plan, destinationPath: destinationDir.path).isEmpty)
    }

    func test_diff_junkInsideRoots_ignored() throws {
        try write("skills/mine/SKILL.md", in: sourceDir, contents: "x")
        try write("skills/mine/SKILL.md", in: destinationDir, contents: "x")
        try write("skills/mine/node_modules/dep.js", in: destinationDir, contents: "junk")

        let plan = HarnessPublishPlan(
            sourcePath: sourceDir.path,
            mode: .enumerated,
            files: ["skills/mine"],
            unresolvedReferences: []
        )
        XCTAssertTrue(
            PublishChangePreview.diff(plan: plan, destinationPath: destinationDir.path).isEmpty)
    }

    func test_diff_singleFileRoot() throws {
        try write("tools/guard.sh", in: sourceDir, contents: "new")
        try write("tools/guard.sh", in: destinationDir, contents: "old")

        let plan = HarnessPublishPlan(
            sourcePath: sourceDir.path,
            mode: .enumerated,
            files: ["tools/guard.sh"],
            unresolvedReferences: []
        )
        XCTAssertEqual(
            PublishChangePreview.diff(plan: plan, destinationPath: destinationDir.path),
            [PublishChange(path: "tools/guard.sh", kind: .modified)]
        )
    }
}
