import Foundation
import TermQShared
import XCTest

@testable import TermQ

final class HarnessPublishPlannerTests: XCTestCase {

    private var sourceDir: URL!

    override func setUpWithError() throws {
        sourceDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("publish-planner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sourceDir)
    }

    // MARK: - Fixture helpers

    /// Write a minimal valid manifest, optionally with extra top-level keys
    /// (hooks, profiles, mcp_servers, sensors) merged in.
    private func writeManifest(extra: [String: Any] = [:]) throws {
        var json: [String: Any] = [
            "name": "demo",
            "version": "0.1.0",
            "default_vendor": "claude",
        ]
        for (key, value) in extra { json[key] = value }
        let dir = sourceDir.appendingPathComponent(".ynh-plugin")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try data.write(to: dir.appendingPathComponent("plugin.json"))
    }

    private func touch(_ relative: String) throws {
        let url = sourceDir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    private func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent(relative), withIntermediateDirectories: true)
    }

    /// Decode a `HarnessComposition` from compose-shaped JSON. Artifacts are
    /// (name, source) pairs per category.
    private func makeComposition(
        skills: [(String, String)] = [],
        agents: [(String, String)] = [],
        rules: [(String, String)] = [],
        commands: [(String, String)] = []
    ) throws -> HarnessComposition {
        func artifacts(_ pairs: [(String, String)]) -> [[String: String]] {
            pairs.map { ["name": $0.0, "source": $0.1] }
        }
        let json: [String: Any] = [
            "name": "demo",
            "version": "0.1.0",
            "default_vendor": "claude",
            "artifacts": [
                "skills": artifacts(skills),
                "agents": artifacts(agents),
                "rules": artifacts(rules),
                "commands": artifacts(commands),
            ],
            "includes": [],
            "delegates_to": [],
            "profiles": [:],
            "counts": [
                "skills": skills.count,
                "agents": agents.count,
                "rules": rules.count,
                "commands": commands.count,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(HarnessComposition.self, from: data)
    }

    private func plan(
        composition: HarnessComposition? = nil,
        mode: HarnessPublishPlan.CopyMode? = nil
    ) throws -> HarnessPublishPlan {
        try HarnessPublishPlanner.plan(
            sourcePath: sourceDir.path,
            harnessName: "demo",
            composition: composition,
            mode: mode
        )
    }

    // MARK: - Default mode

    func test_defaultMode_selfContained_isEntireDirectory() {
        XCTAssertEqual(
            HarnessPublishPlanner.defaultMode(forSourceAt: sourceDir.path), .entireDirectory)
    }

    func test_defaultMode_gitDirectory_isEnumerated() throws {
        try mkdir(".git")
        XCTAssertEqual(HarnessPublishPlanner.defaultMode(forSourceAt: sourceDir.path), .enumerated)
    }

    func test_defaultMode_gitFile_worktree_isEnumerated() throws {
        try touch(".git")
        XCTAssertEqual(HarnessPublishPlanner.defaultMode(forSourceAt: sourceDir.path), .enumerated)
    }

    // MARK: - Error cases

    func test_plan_missingSource_throws() {
        XCTAssertThrowsError(
            try HarnessPublishPlanner.plan(
                sourcePath: sourceDir.appendingPathComponent("nope").path,
                harnessName: "demo",
                composition: nil
            )
        ) { error in
            guard case HarnessPublishPlannerError.sourceNotFound = error else {
                return XCTFail("expected sourceNotFound, got \(error)")
            }
        }
    }

    func test_plan_missingManifest_throws() {
        XCTAssertThrowsError(try plan()) { error in
            guard case HarnessPublishPlannerError.manifestNotFound = error else {
                return XCTFail("expected manifestNotFound, got \(error)")
            }
        }
    }

    func test_plan_malformedManifest_throws() throws {
        let dir = sourceDir.appendingPathComponent(".ynh-plugin")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("plugin.json"))
        XCTAssertThrowsError(try plan()) { error in
            guard case HarnessPublishPlannerError.manifestInvalid = error else {
                return XCTFail("expected manifestInvalid, got \(error)")
            }
        }
    }

    func test_plan_enumeratedWithoutComposition_throws() throws {
        try writeManifest()
        XCTAssertThrowsError(try plan(mode: .enumerated)) { error in
            guard case HarnessPublishPlannerError.compositionRequired = error else {
                return XCTFail("expected compositionRequired, got \(error)")
            }
        }
    }

    // MARK: - Entire-directory mode

    func test_entireDirectory_listsTopLevelMinusJunk() throws {
        try writeManifest()
        try mkdir("skills/alpha")
        try touch("README.md")
        try mkdir("node_modules/pkg")
        try mkdir(".git")
        try touch(".DS_Store")

        let result = try plan(mode: .entireDirectory)
        XCTAssertEqual(result.files, [".ynh-plugin", "README.md", "skills"])
        XCTAssertTrue(result.unresolvedReferences.isEmpty)
    }

    // MARK: - Enumerated mode: artifacts

    func test_enumerated_includesOwnedArtifacts_excludesIncludeContributed() throws {
        try writeManifest()
        try touch("skills/mine/SKILL.md")
        try touch("agents/helper.md")
        let composition = try makeComposition(
            skills: [("mine", "demo"), ("theirs", "eyelock/assistants")],
            agents: [("helper", "demo"), ("reviewer", "gitflow")]
        )

        let result = try plan(composition: composition, mode: .enumerated)
        XCTAssertEqual(result.files, [".ynh-plugin", "agents/helper.md", "skills/mine"])
        XCTAssertTrue(result.unresolvedReferences.isEmpty)
    }

    func test_enumerated_missingOwnedArtifact_isUnresolved() throws {
        try writeManifest()
        let composition = try makeComposition(skills: [("ghost", "demo")])

        let result = try plan(composition: composition, mode: .enumerated)
        XCTAssertEqual(result.files, [".ynh-plugin"])
        XCTAssertEqual(result.unresolvedReferences, ["skills/ghost"])
    }

    func test_enumerated_agentDirectoryForm_tolerated() throws {
        try writeManifest()
        try touch("agents/composite/AGENT.md")
        let composition = try makeComposition(agents: [("composite", "demo")])

        let result = try plan(composition: composition, mode: .enumerated)
        XCTAssertEqual(result.files, [".ynh-plugin", "agents/composite"])
    }

    // MARK: - Enumerated mode: script references

    func test_enumerated_collectsHookProfileMcpAndSensorScripts() throws {
        try touch("tools/hooks/guard.sh")
        try touch("tools/hooks/build.sh")
        try touch("tools/mcp/server.sh")
        try touch("tools/sensors/probe.sh")
        try writeManifest(extra: [
            "hooks": [
                "before_tool": [["command": "./tools/hooks/guard.sh", "matcher": "Bash"]]
            ],
            "profiles": [
                "strict": [
                    "hooks": [
                        "after_tool": [["command": "./tools/hooks/build.sh --fast"]]
                    ]
                ]
            ],
            "mcp_servers": [
                "local": ["command": "./tools/mcp/server.sh", "args": ["--format", "json"]]
            ],
            "sensors": [
                "probe": ["command": "./tools/sensors/probe.sh"]
            ],
        ])

        let result = try plan(composition: try makeComposition(), mode: .enumerated)
        XCTAssertEqual(
            result.files,
            [
                ".ynh-plugin",
                "tools/hooks/build.sh",
                "tools/hooks/guard.sh",
                "tools/mcp/server.sh",
                "tools/sensors/probe.sh",
            ]
        )
        XCTAssertTrue(result.unresolvedReferences.isEmpty)
    }

    func test_enumerated_sensorSourceFiles_neverCollected() throws {
        // The referenced file exists on disk — it must STILL not be copied,
        // because sensor source.files are runtime reads, not content.
        try touch("tests/e2e/last-run.json")
        try writeManifest(extra: [
            "sensors": [
                "e2e": ["source": ["files": ["./tests/e2e/last-run.json"]]]
            ]
        ])

        let result = try plan(composition: try makeComposition(), mode: .enumerated)
        XCTAssertEqual(result.files, [".ynh-plugin"])
        XCTAssertTrue(result.unresolvedReferences.isEmpty)
    }

    func test_enumerated_nonRelativeCommandsAndFlags_ignoredSilently() throws {
        try writeManifest(extra: [
            "mcp_servers": [
                "npx": ["command": "npx", "args": ["-y", "@some/package"]],
                "abs": ["command": "/usr/bin/true"],
            ]
        ])

        let result = try plan(composition: try makeComposition(), mode: .enumerated)
        XCTAssertEqual(result.files, [".ynh-plugin"])
        XCTAssertTrue(result.unresolvedReferences.isEmpty)
    }

    func test_enumerated_missingScript_isUnresolved() throws {
        try writeManifest(extra: [
            "hooks": ["on_stop": [["command": "./tools/hooks/gone.sh"]]]
        ])

        let result = try plan(composition: try makeComposition(), mode: .enumerated)
        XCTAssertEqual(result.files, [".ynh-plugin"])
        XCTAssertEqual(result.unresolvedReferences, ["tools/hooks/gone.sh"])
    }

    func test_enumerated_escapingReference_isUnresolved() throws {
        try writeManifest(extra: [
            "hooks": ["on_stop": [["command": "./../outside/evil.sh"]]]
        ])

        let result = try plan(composition: try makeComposition(), mode: .enumerated)
        XCTAssertEqual(result.files, [".ynh-plugin"])
        XCTAssertEqual(result.unresolvedReferences, ["./../outside/evil.sh"])
    }

    func test_enumerated_fileRootsCoveredByDirectoryRoots_dropped() throws {
        try writeManifest(extra: [
            "hooks": ["on_stop": [["command": "./skills/mine/run.sh"]]]
        ])
        try touch("skills/mine/SKILL.md")
        try touch("skills/mine/run.sh")
        let composition = try makeComposition(skills: [("mine", "demo")])

        let result = try plan(composition: composition, mode: .enumerated)
        XCTAssertEqual(result.files, [".ynh-plugin", "skills/mine"])
    }

    func test_enumerated_duplicateScriptRefs_deduped() throws {
        try touch("tools/hooks/build.sh")
        try writeManifest(extra: [
            "profiles": [
                "coverage": ["hooks": ["after_tool": [["command": "./tools/hooks/build.sh"]]]],
                "strict": ["hooks": ["after_tool": [["command": "./tools/hooks/build.sh --strict"]]]],
            ]
        ])

        let result = try plan(composition: try makeComposition(), mode: .enumerated)
        XCTAssertEqual(result.files, [".ynh-plugin", "tools/hooks/build.sh"])
    }
}
