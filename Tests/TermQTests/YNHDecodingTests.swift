import Foundation
import TermQShared
import XCTest

@testable import TermQ

/// Decode tests for YNH 0.2 JSON shapes.
///
/// Fixtures are inlined from actual `ynh ls`, `ynh search`, and `ynh paths` output.
/// They serve as a contract test: if YNH changes its JSON shape, these fail first.
final class YNHHarnessDecodingTests: XCTestCase {

    // MARK: - ynh ls --format json

    func test_ynh_ls_decodesHarnessArray() throws {
        let json = """
            [
              {
                "name": "assistants-dev",
                "version": "0.1.0",
                "description": "A harness for adding to eyelock-assistants",
                "default_vendor": "claude",
                "path": "/Users/test/.ynh/harnesses/assistants-dev",
                "installed_from": {
                  "source_type": "local",
                  "source": "/projects/assistants-dev",
                  "installed_at": "2026-04-21T17:55:38Z"
                },
                "artifacts": { "skills": 0, "agents": 0, "rules": 0, "commands": 0 },
                "includes": [
                  { "git": "https://github.com/eyelock/assistants", "path": "plugins/gitflow" }
                ],
                "delegates_to": []
              }
            ]
            """
        let harnesses = try JSONDecoder().decode([Harness].self, from: Data(json.utf8))
        XCTAssertEqual(harnesses.count, 1)
        let h = harnesses[0]
        XCTAssertEqual(h.name, "assistants-dev")
        XCTAssertEqual(h.version, "0.1.0")
        XCTAssertEqual(h.defaultVendor, "claude")
        XCTAssertNil(h.namespace)
        XCTAssertEqual(h.id, "assistants-dev")  // no namespace → id == name
        XCTAssertEqual(h.includes.count, 1)
        XCTAssertEqual(h.includes[0].git, "https://github.com/eyelock/assistants")
    }

    func test_ynh_ls_decodesProvenanceFields() throws {
        let json = """
            [
              {
                "name": "my-harness",
                "version": "0.1.0",
                "default_vendor": "claude",
                "path": "/Users/test/.ynh/harnesses/my-harness",
                "installed_from": {
                  "source_type": "registry",
                  "source": "github.com/eyelock/assistants",
                  "registry_name": "eyelock-assistants",
                  "installed_at": "2026-04-21T00:00:00Z",
                  "ref": "main",
                  "sha": "abc1234",
                  "namespace": "eyelock/assistants"
                },
                "artifacts": { "skills": 2, "agents": 1, "rules": 0, "commands": 1 },
                "includes": [],
                "delegates_to": []
              }
            ]
            """
        let harnesses = try JSONDecoder().decode([Harness].self, from: Data(json.utf8))
        let prov = try XCTUnwrap(harnesses[0].installedFrom)
        XCTAssertEqual(prov.sourceType, "registry")
        XCTAssertEqual(prov.registryName, "eyelock-assistants")
        XCTAssertEqual(prov.ref, "main")
        XCTAssertEqual(prov.sha, "abc1234")
        XCTAssertEqual(prov.namespace, "eyelock/assistants")
    }

    func test_ynh_ls_decodesNamespacedHarness() throws {
        let json = """
            [
              {
                "name": "tester",
                "version": "0.2.0",
                "default_vendor": "claude",
                "namespace": "eyelock/assistants",
                "path": "/Users/test/.ynh/harnesses/eyelock--assistants/tester",
                "artifacts": { "skills": 1, "agents": 0, "rules": 0, "commands": 0 },
                "includes": [],
                "delegates_to": []
              }
            ]
            """
        let harnesses = try JSONDecoder().decode([Harness].self, from: Data(json.utf8))
        let h = harnesses[0]
        XCTAssertEqual(h.namespace, "eyelock/assistants")
        XCTAssertEqual(h.id, "eyelock/assistants/tester")  // namespace-qualified id
    }

    func test_harness_id_isNamespaceQualifiedWhenPresent() {
        let h = Harness(
            name: "my-harness",
            version: "1.0.0",
            defaultVendor: "claude",
            namespace: "acme/tools",
            path: "/tmp/my-harness",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        XCTAssertEqual(h.id, "acme/tools/my-harness")
    }

    func test_harness_id_isFlatNameWhenNamespaceIsNil() {
        let h = Harness(
            name: "my-harness",
            version: "1.0.0",
            defaultVendor: "claude",
            path: "/tmp/my-harness",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        XCTAssertEqual(h.id, "my-harness")
    }

    func test_harness_id_isFlatNameWhenNamespaceIsEmpty() {
        let h = Harness(
            name: "my-harness",
            version: "1.0.0",
            defaultVendor: "claude",
            namespace: "",
            path: "/tmp/my-harness",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        XCTAssertEqual(h.id, "my-harness")
    }

    func test_harness_id_collisionAvoidedByNamespace() {
        let a = Harness(
            name: "tools",
            version: "1.0.0",
            defaultVendor: "claude",
            namespace: "acme/tools",
            path: "/tmp/a",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        let b = Harness(
            name: "tools",
            version: "1.0.0",
            defaultVendor: "claude",
            namespace: "eyelock/tools",
            path: "/tmp/b",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - ynh search --format json

    func test_ynh_search_decodesSearchResultArray() throws {
        let json = """
            [
              {
                "name": "david",
                "description": "David full-stack persona",
                "keywords": ["go", "development"],
                "repo": "github.com/eyelock/assistants",
                "path": "ynh/david",
                "version": "0.1.0",
                "from": { "type": "registry", "name": "eyelock-assistants" }
              },
              {
                "name": "local-tool",
                "description": "A local harness",
                "from": { "type": "source", "name": "my-source" }
              }
            ]
            """
        let results = try JSONDecoder().decode([SearchResult].self, from: Data(json.utf8))
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].from.type, .registry)
        XCTAssertEqual(results[0].from.name, "eyelock-assistants")
        XCTAssertEqual(results[1].from.type, .source)
        XCTAssertNil(results[0].vendors)  // vendors not emitted in 0.2
    }

    func test_ynh_search_toleratesAbsentVendors() throws {
        let json = """
            [{"name":"x","from":{"type":"registry","name":"r"},"version":"1.0"}]
            """
        let results = try JSONDecoder().decode([SearchResult].self, from: Data(json.utf8))
        XCTAssertNil(results[0].vendors)
    }

    // MARK: - ynh paths --format json

    func test_ynh_paths_decodesAllFields() throws {
        let json = """
            {
              "home": "/Users/test/.ynh",
              "config": "/Users/test/.ynh/config.json",
              "harnesses": "/Users/test/.ynh/harnesses",
              "symlinks": "/Users/test/.ynh/symlinks.json",
              "cache": "/Users/test/.ynh/cache",
              "run": "/Users/test/.ynh/run",
              "bin": "/Users/test/.ynh/bin"
            }
            """
        let paths = try JSONDecoder().decode(YNHPaths.self, from: Data(json.utf8))
        XCTAssertEqual(paths.home, "/Users/test/.ynh")
        XCTAssertEqual(paths.bin, "/Users/test/.ynh/bin")
        XCTAssertEqual(paths.run, "/Users/test/.ynh/run")
    }

    // MARK: - ynh version --format json

    func test_ynh_version_decodesCapabilities() throws {
        let json = """
            {"version": "dev-develop-66048e1", "capabilities": "0.2.0"}
            """

        struct VersionInfo: Decodable {
            let version: String?
            let capabilities: String?
        }

        let info = try JSONDecoder().decode(VersionInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.capabilities, "0.2.0")
        XCTAssertTrue(YNHDetector.capabilityMeets("0.2.0", minimum: "0.2.0"))
        XCTAssertFalse(YNHDetector.capabilityMeets("0.1.5", minimum: "0.2.0"))
    }
}
