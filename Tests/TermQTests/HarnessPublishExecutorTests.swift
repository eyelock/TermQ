import Foundation
import XCTest

@testable import TermQ

final class HarnessPublishExecutorTests: XCTestCase {

    private var sourceDir: URL!
    private var worktreeDir: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("publish-executor-test-\(UUID().uuidString)")
        sourceDir = base.appendingPathComponent("source")
        worktreeDir = base.appendingPathComponent("worktree")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sourceDir.deletingLastPathComponent())
    }

    // MARK: - Fixture helpers

    private func write(_ relative: String, in base: URL, contents: String = "x") throws {
        let url = base.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func writeSourceManifest(name: String = "demo") throws {
        try write(
            ".ynh-plugin/plugin.json", in: sourceDir,
            contents: #"{"name":"\#(name)","version":"0.1.0","default_vendor":"claude"}"#)
    }

    private func exists(_ relative: String, in base: URL) -> Bool {
        FileManager.default.fileExists(atPath: base.appendingPathComponent(relative).path)
    }

    private func makePlan(files: [String]) -> HarnessPublishPlan {
        HarnessPublishPlan(
            sourcePath: sourceDir.path,
            mode: .enumerated,
            files: files,
            unresolvedReferences: []
        )
    }

    // MARK: - New entry

    func test_newEntry_copiesRootsIntoDestination() throws {
        try writeSourceManifest()
        try write("skills/mine/SKILL.md", in: sourceDir)
        try write("tools/hooks/guard.sh", in: sourceDir)

        let report = try HarnessPublishExecutor.execute(
            plan: makePlan(files: [".ynh-plugin", "skills/mine", "tools/hooks/guard.sh"]),
            worktreePath: worktreeDir.path,
            destinationRelativePath: "ynh/demo",
            isUpdate: false
        )

        XCTAssertEqual(report.copiedRoots, [".ynh-plugin", "skills/mine", "tools/hooks/guard.sh"])
        XCTAssertTrue(exists("ynh/demo/.ynh-plugin/plugin.json", in: worktreeDir))
        XCTAssertTrue(exists("ynh/demo/skills/mine/SKILL.md", in: worktreeDir))
        XCTAssertTrue(exists("ynh/demo/tools/hooks/guard.sh", in: worktreeDir))
        XCTAssertTrue(report.deletedPaths.isEmpty)
    }

    func test_newEntry_existingHarnessAtDestination_throws() throws {
        try writeSourceManifest()
        try write("ynh/demo/.ynh-plugin/plugin.json", in: worktreeDir)

        XCTAssertThrowsError(
            try HarnessPublishExecutor.execute(
                plan: makePlan(files: [".ynh-plugin"]),
                worktreePath: worktreeDir.path,
                destinationRelativePath: "ynh/demo",
                isUpdate: false
            )
        ) { error in
            guard case HarnessPublishExecutorError.destinationOccupied = error else {
                return XCTFail("expected destinationOccupied, got \(error)")
            }
        }
    }

    func test_invalidDestination_escapingWorktree_throws() throws {
        try writeSourceManifest()
        for bad in ["../outside", "/absolute"] {
            XCTAssertThrowsError(
                try HarnessPublishExecutor.execute(
                    plan: makePlan(files: [".ynh-plugin"]),
                    worktreePath: worktreeDir.path,
                    destinationRelativePath: bad,
                    isUpdate: false
                ),
                "expected invalidDestination for \(bad)"
            ) { error in
                guard case HarnessPublishExecutorError.invalidDestination = error else {
                    return XCTFail("expected invalidDestination, got \(error)")
                }
            }
        }
    }

    // MARK: - Junk filtering & provenance strip

    func test_copy_skipsJunkAtAnyDepth_andStripsInstalledJSON() throws {
        try writeSourceManifest()
        try write(".ynh-plugin/installed.json", in: sourceDir)
        try write("skills/mine/SKILL.md", in: sourceDir)
        try write("skills/mine/node_modules/dep/index.js", in: sourceDir)
        try write("skills/mine/.DS_Store", in: sourceDir)

        _ = try HarnessPublishExecutor.execute(
            plan: makePlan(files: [".ynh-plugin", "skills/mine"]),
            worktreePath: worktreeDir.path,
            destinationRelativePath: "ynh/demo",
            isUpdate: false
        )

        XCTAssertTrue(exists("ynh/demo/skills/mine/SKILL.md", in: worktreeDir))
        XCTAssertFalse(exists("ynh/demo/skills/mine/node_modules", in: worktreeDir))
        XCTAssertFalse(exists("ynh/demo/skills/mine/.DS_Store", in: worktreeDir))
        XCTAssertFalse(exists("ynh/demo/.ynh-plugin/installed.json", in: worktreeDir))
        XCTAssertTrue(exists("ynh/demo/.ynh-plugin/plugin.json", in: worktreeDir))
    }

    func test_copy_preservesExecutablePermissions() throws {
        try writeSourceManifest()
        try write("tools/guard.sh", in: sourceDir, contents: "#!/bin/sh\n")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: sourceDir.appendingPathComponent("tools/guard.sh").path)

        _ = try HarnessPublishExecutor.execute(
            plan: makePlan(files: [".ynh-plugin", "tools/guard.sh"]),
            worktreePath: worktreeDir.path,
            destinationRelativePath: "ynh/demo",
            isUpdate: false
        )

        XCTAssertTrue(
            FileManager.default.isExecutableFile(
                atPath: worktreeDir.appendingPathComponent("ynh/demo/tools/guard.sh").path))
    }

    // MARK: - Update: dedicated harness dir

    func test_update_dedicatedDir_wholesaleReplaced() throws {
        try writeSourceManifest()
        try write("skills/mine/SKILL.md", in: sourceDir)
        // Existing entry has a file the source no longer ships.
        try write("ynh/demo/.ynh-plugin/plugin.json", in: worktreeDir)
        try write("ynh/demo/skills/obsolete/SKILL.md", in: worktreeDir)

        let report = try HarnessPublishExecutor.execute(
            plan: makePlan(files: [".ynh-plugin", "skills/mine"]),
            worktreePath: worktreeDir.path,
            destinationRelativePath: "ynh/demo",
            isUpdate: true
        )

        XCTAssertEqual(report.deletedPaths, ["ynh/demo"])
        XCTAssertTrue(exists("ynh/demo/skills/mine/SKILL.md", in: worktreeDir))
        XCTAssertFalse(exists("ynh/demo/skills/obsolete", in: worktreeDir))
    }

    // MARK: - Update: root/shared destination

    func test_update_rootDestination_neverWholesaleDeleted() throws {
        try writeSourceManifest()
        try write("skills/mine/SKILL.md", in: sourceDir)
        // The worktree root holds the host project AND the embedded harness.
        try write("services/api/main.go", in: worktreeDir)
        try write(".ynh-plugin/plugin.json", in: worktreeDir)
        try write("skills/old/SKILL.md", in: worktreeDir)

        let report = try HarnessPublishExecutor.execute(
            plan: makePlan(files: [".ynh-plugin", "skills/mine"]),
            worktreePath: worktreeDir.path,
            destinationRelativePath: ".",
            isUpdate: true,
            existingFileRoots: [".ynh-plugin", "skills/old"]
        )

        // Host project untouched; stale harness root deleted; new root copied.
        XCTAssertTrue(exists("services/api/main.go", in: worktreeDir))
        XCTAssertTrue(exists("skills/mine/SKILL.md", in: worktreeDir))
        XCTAssertFalse(exists("skills/old", in: worktreeDir))
        XCTAssertEqual(report.deletedPaths, ["skills/old"])
        XCTAssertTrue(report.warnings.isEmpty)
    }

    func test_update_rootDestination_unknownExistingSet_skipsDeletionsWithWarning() throws {
        try writeSourceManifest()
        try write(".ynh-plugin/plugin.json", in: worktreeDir)
        try write("skills/old/SKILL.md", in: worktreeDir)

        let report = try HarnessPublishExecutor.execute(
            plan: makePlan(files: [".ynh-plugin"]),
            worktreePath: worktreeDir.path,
            destinationRelativePath: ".",
            isUpdate: true,
            existingFileRoots: nil
        )

        XCTAssertTrue(exists("skills/old/SKILL.md", in: worktreeDir))
        XCTAssertTrue(report.deletedPaths.isEmpty)
        XCTAssertEqual(report.warnings.count, 1)
    }

    func test_update_replacedRoot_propagatesDeletionsInsideDirectory() throws {
        try writeSourceManifest()
        try write("skills/mine/SKILL.md", in: sourceDir)
        // Destination's copy of the same root has an extra nested file.
        try write("ynh/demo/.ynh-plugin/plugin.json", in: worktreeDir)
        try write("ynh/demo/skills/mine/SKILL.md", in: worktreeDir)
        try write("ynh/demo/skills/mine/references/stale.md", in: worktreeDir)

        _ = try HarnessPublishExecutor.execute(
            plan: makePlan(files: [".ynh-plugin", "skills/mine"]),
            worktreePath: worktreeDir.path,
            destinationRelativePath: "ynh/demo",
            isUpdate: true
        )

        XCTAssertTrue(exists("ynh/demo/skills/mine/SKILL.md", in: worktreeDir))
        XCTAssertFalse(exists("ynh/demo/skills/mine/references/stale.md", in: worktreeDir))
    }

    // MARK: - Rename

    func test_rename_rewritesManifestName_preservingOtherKeys() throws {
        try write(
            ".ynh-plugin/plugin.json", in: sourceDir,
            contents:
                #"{"$schema":"s","name":"demo","version":"0.2.0","default_vendor":"claude","description":"d"}"#
        )

        _ = try HarnessPublishExecutor.execute(
            plan: makePlan(files: [".ynh-plugin"]),
            worktreePath: worktreeDir.path,
            destinationRelativePath: "ynh/renamed",
            renameTo: "renamed",
            isUpdate: false
        )

        let data = try Data(
            contentsOf: worktreeDir.appendingPathComponent("ynh/renamed/.ynh-plugin/plugin.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "renamed")
        XCTAssertEqual(json["version"] as? String, "0.2.0")
        XCTAssertEqual(json["$schema"] as? String, "s")
        XCTAssertEqual(json["description"] as? String, "d")
    }

    func test_noRename_manifestCopiedByteIdentical() throws {
        let original =
            #"{"$schema":"s","name":"demo","version":"0.1.0","default_vendor":"claude"}"#
        try write(".ynh-plugin/plugin.json", in: sourceDir, contents: original)

        _ = try HarnessPublishExecutor.execute(
            plan: makePlan(files: [".ynh-plugin"]),
            worktreePath: worktreeDir.path,
            destinationRelativePath: "ynh/demo",
            isUpdate: false
        )

        let copied = try String(
            contentsOf: worktreeDir.appendingPathComponent("ynh/demo/.ynh-plugin/plugin.json"),
            encoding: .utf8)
        XCTAssertEqual(copied, original)
    }
}

// MARK: - YndValidateRunner

final class YndValidateRunnerTests: XCTestCase {

    private struct StubRunner: YNHCommandRunner {
        let result: CommandRunner.Result

        // swiftlint:disable:next function_parameter_count
        func run(
            executable: String,
            arguments: [String],
            environment: [String: String]?,
            currentDirectory: String?,
            onStdoutLine: (@Sendable (String) -> Void)?,
            onStderrLine: (@Sendable (String) -> Void)?
        ) async throws -> CommandRunner.Result {
            result
        }
    }

    func test_validate_success() async throws {
        let runner = YndValidateRunner(
            commandRunner: StubRunner(
                result: CommandRunner.Result(exitCode: 0, stdout: ".: valid\n", stderr: "", duration: 0)))

        let result = try await runner.validate(yndPath: "/usr/bin/ynd", harnessPath: "/tmp/h")
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.findings.isEmpty)
    }

    func test_validate_failure_parsesFindings() async throws {
        let stdout = ".: INVALID\n  - missing property '$schema'\n  - missing property 'version'\n"
        let runner = YndValidateRunner(
            commandRunner: StubRunner(
                result: CommandRunner.Result(
                    exitCode: 1, stdout: stdout, stderr: "Error: validation failed", duration: 0)))

        let result = try await runner.validate(yndPath: "/usr/bin/ynd", harnessPath: "/tmp/h")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(
            result.findings,
            ["missing property '$schema'", "missing property 'version'"])
    }
}
