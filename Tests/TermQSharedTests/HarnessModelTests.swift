import Foundation
import XCTest

@testable import TermQShared

final class HarnessModelTests: XCTestCase {

    // MARK: - HarnessArtifactCounts

    func testArtifactCounts_total() {
        let counts = HarnessArtifactCounts(skills: 2, agents: 3, rules: 1, commands: 4)
        XCTAssertEqual(counts.total, 10)
    }

    func testArtifactCounts_zeroTotal() {
        let counts = HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        XCTAssertEqual(counts.total, 0)
    }

    func testArtifactCounts_codable() throws {
        let original = HarnessArtifactCounts(skills: 5, agents: 2, rules: 0, commands: 3)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HarnessArtifactCounts.self, from: data)
        XCTAssertEqual(decoded.total, original.total)
        XCTAssertEqual(decoded.skills, 5)
    }

    // MARK: - HarnessProvenance

    func testHarnessProvenance_codable() throws {
        let json = """
            {
                "source_type": "registry",
                "source": "https://registry.example.com",
                "path": null,
                "registry_name": "official",
                "installed_at": "2024-01-01T00:00:00Z"
            }
            """
        let provenance = try JSONDecoder().decode(
            HarnessProvenance.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(provenance.sourceType, "registry")
        XCTAssertEqual(provenance.source, "https://registry.example.com")
        XCTAssertNil(provenance.path)
        XCTAssertEqual(provenance.registryName, "official")
        XCTAssertEqual(provenance.installedAt, "2024-01-01T00:00:00Z")
    }

    func testHarnessProvenance_equatable() {
        let p1 = try! JSONDecoder().decode(
            HarnessProvenance.self,
            from: """
                {"source_type":"git","source":"git@github.com:foo/bar","path":null,"registry_name":null,"installed_at":"2024"}
                """.data(using: .utf8)!
        )
        let p2 = try! JSONDecoder().decode(
            HarnessProvenance.self,
            from: """
                {"source_type":"git","source":"git@github.com:foo/bar","path":null,"registry_name":null,"installed_at":"2024"}
                """.data(using: .utf8)!
        )
        XCTAssertEqual(p1, p2)
    }

    // MARK: - HarnessInclude / HarnessDelegate

    func testHarnessInclude_codable() throws {
        let json = """
            {"git":"git@github.com:foo/bar","ref":"main","path":null,"pick":["skill1","skill2"]}
            """
        let include = try JSONDecoder().decode(HarnessInclude.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(include.git, "git@github.com:foo/bar")
        XCTAssertEqual(include.ref, "main")
        XCTAssertNil(include.path)
        XCTAssertEqual(include.pick, ["skill1", "skill2"])
    }

    func testHarnessDelegate_codable() throws {
        let json = """
            {"git":"git@github.com:foo/baz","ref":null,"path":"/sub"}
            """
        let delegate = try JSONDecoder().decode(HarnessDelegate.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(delegate.git, "git@github.com:foo/baz")
        XCTAssertNil(delegate.ref)
        XCTAssertEqual(delegate.path, "/sub")
    }

    // MARK: - Harness

    func testHarness_id_equalsName() {
        let h = Harness(
            name: "my-harness",
            version: "1.0.0",
            defaultVendor: "claude",
            path: "/path",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        XCTAssertEqual(h.id, "my-harness")
    }

    func testHarness_equatable() {
        let artifacts = HarnessArtifactCounts(skills: 1, agents: 0, rules: 0, commands: 0)
        let h1 = Harness(
            name: "dev", version: "1.0", defaultVendor: "claude", path: "/p", artifacts: artifacts)
        let h2 = Harness(
            name: "dev", version: "1.0", defaultVendor: "claude", path: "/p", artifacts: artifacts)
        XCTAssertEqual(h1, h2)
    }

    func testHarness_inequitable_differentName() {
        let artifacts = HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        let h1 = Harness(
            name: "a", version: "1.0", defaultVendor: "claude", path: "/p", artifacts: artifacts)
        let h2 = Harness(
            name: "b", version: "1.0", defaultVendor: "claude", path: "/p", artifacts: artifacts)
        XCTAssertNotEqual(h1, h2)
    }

    /// YNH 0.2.x emits `version` (not `version_installed`) on `ynh ls`/`ynh info`
    /// payloads. TermQ must accept that legacy key so 0.9.7 does not regress users
    /// still on Homebrew-shipped YNH 0.2.3.
    func testHarness_codable_acceptsLegacyVersionKey() throws {
        let json = """
            {
                "name": "legacy",
                "version": "0.1.0",
                "default_vendor": "claude",
                "path": "/p",
                "artifacts": {"skills": 0, "agents": 0, "rules": 0, "commands": 0},
                "includes": [],
                "delegates_to": []
            }
            """
        let h = try JSONDecoder().decode(Harness.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(h.version, "0.1.0")
    }

    func testHarnessInfo_codable_acceptsLegacyVersionKey() throws {
        let json = """
            {"name":"h","version":"v","default_vendor":"claude","path":"/p"}
            """
        let info = try JSONDecoder().decode(HarnessInfo.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(info.version, "v")
    }

    func testHarness_codable_minimal() throws {
        let json = """
            {
                "name": "my-harness",
                "version_installed": "1.2.3",
                "description": "A test harness",
                "default_vendor": "claude",
                "path": "/home/user/.ynh/harnesses/my-harness",
                "installed_from": null,
                "artifacts": {"skills": 2, "agents": 1, "rules": 0, "commands": 3},
                "includes": [],
                "delegates_to": []
            }
            """
        let h = try JSONDecoder().decode(Harness.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(h.name, "my-harness")
        XCTAssertEqual(h.version, "1.2.3")
        XCTAssertEqual(h.description, "A test harness")
        XCTAssertEqual(h.defaultVendor, "claude")
        XCTAssertEqual(h.artifacts.total, 6)
        XCTAssertNil(h.installedFrom)
        XCTAssertTrue(h.includes.isEmpty)
        XCTAssertTrue(h.delegatesTo.isEmpty)
    }

    func testHarness_codable_withProvenance() throws {
        let json = """
            {
                "name": "test",
                "version_installed": "0.1",
                "default_vendor": "claude",
                "path": "/path",
                "installed_from": {
                    "source_type": "git",
                    "source": "git@github.com:foo/test",
                    "path": null,
                    "registry_name": null,
                    "installed_at": "2024-06-01T12:00:00Z"
                },
                "artifacts": {"skills": 0, "agents": 0, "rules": 0, "commands": 0},
                "includes": [],
                "delegates_to": []
            }
            """
        let h = try JSONDecoder().decode(Harness.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(h.installedFrom)
        XCTAssertEqual(h.installedFrom?.sourceType, "git")
    }

    func testHarness_codable_withIncludes() throws {
        let json = """
            {
                "name": "test",
                "version_installed": "0.1",
                "default_vendor": "claude",
                "path": "/path",
                "artifacts": {"skills": 0, "agents": 0, "rules": 0, "commands": 0},
                "includes": [{"git": "git@github.com:foo/bar", "ref": "main", "path": null, "pick": ["skill1"]}],
                "delegates_to": [{"git": "git@github.com:foo/baz", "ref": null, "path": null}]
            }
            """
        let h = try JSONDecoder().decode(Harness.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(h.includes.count, 1)
        XCTAssertEqual(h.includes[0].git, "git@github.com:foo/bar")
        XCTAssertEqual(h.delegatesTo.count, 1)
    }

    func testHarness_nilDescription() throws {
        let json = """
            {
                "name": "x",
                "version_installed": "1",
                "default_vendor": "c",
                "path": "/p",
                "artifacts": {"skills": 0, "agents": 0, "rules": 0, "commands": 0},
                "includes": [],
                "delegates_to": []
            }
            """
        let h = try JSONDecoder().decode(Harness.self, from: json.data(using: .utf8)!)
        XCTAssertNil(h.description)
    }

    // MARK: - Harness uninstall provenance

    /// A harness with no install record (e.g. a locally-authored harness that was never
    /// `ynh install`ed) must have `installedFrom == nil`. The UI uses this to skip
    /// `ynh uninstall` and delete the directory directly.
    func testHarness_noInstallRecord_hasNilProvenance() throws {
        let json = """
            {
                "name": "github-tester",
                "version_installed": "0.1.0",
                "default_vendor": "claude",
                "path": "/Users/dev/harnesses/github-tester",
                "installed_from": null,
                "artifacts": {"skills": 0, "agents": 0, "rules": 0, "commands": 0},
                "includes": [],
                "delegates_to": []
            }
            """
        let h = try JSONDecoder().decode(Harness.self, from: json.data(using: .utf8)!)
        XCTAssertNil(h.installedFrom)
    }

    /// A harness installed via `ynh install ./local-path` has `source_type == "local"`.
    /// The UI routes these through `ynh uninstall`, which succeeds because ynh has an install record.
    func testHarness_locallyInstalledViaYNH_hasLocalSourceType() throws {
        let json = """
            {
                "name": "assistants-dev",
                "version_installed": "0.1.0",
                "default_vendor": "claude",
                "path": "/Users/dev/.ynh/harnesses/assistants-dev",
                "installed_from": {
                    "source_type": "local",
                    "source": "/Users/dev/harnesses/assistants-dev",
                    "path": null,
                    "registry_name": null,
                    "installed_at": "2026-01-01T00:00:00Z"
                },
                "artifacts": {"skills": 1, "agents": 0, "rules": 0, "commands": 0},
                "includes": [],
                "delegates_to": []
            }
            """
        let h = try JSONDecoder().decode(Harness.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(h.installedFrom)
        XCTAssertEqual(h.installedFrom?.sourceType, "local")
    }

    /// A harness with no install record uninstalled from HarnessDetailView shows the untracked
    /// alert message, not the generic or local-specific one.
    func testHarness_noInstallRecord_isDistinctFromLocalSourceType() throws {
        let nilProvenanceJSON = """
            {
                "name": "untracked",
                "version_installed": "0.1.0",
                "default_vendor": "claude",
                "path": "/Users/dev/harnesses/untracked",
                "installed_from": null,
                "artifacts": {"skills": 0, "agents": 0, "rules": 0, "commands": 0},
                "includes": [],
                "delegates_to": []
            }
            """
        let localJSON = """
            {
                "name": "assistants-dev",
                "version_installed": "0.1.0",
                "default_vendor": "claude",
                "path": "/Users/dev/.ynh/harnesses/assistants-dev",
                "installed_from": {
                    "source_type": "local",
                    "source": "/Users/dev/harnesses/assistants-dev",
                    "path": null,
                    "registry_name": null,
                    "installed_at": "2026-01-01T00:00:00Z"
                },
                "artifacts": {"skills": 0, "agents": 0, "rules": 0, "commands": 0},
                "includes": [],
                "delegates_to": []
            }
            """
        let untracked = try JSONDecoder().decode(Harness.self, from: nilProvenanceJSON.data(using: .utf8)!)
        let local = try JSONDecoder().decode(Harness.self, from: localJSON.data(using: .utf8)!)
        XCTAssertNil(untracked.installedFrom)
        XCTAssertNotNil(local.installedFrom)
        XCTAssertEqual(local.installedFrom?.sourceType, "local")
        XCTAssertNotEqual(untracked.installedFrom?.sourceType, local.installedFrom?.sourceType)
    }

    /// A registry harness has `source_type == "registry"` and is always uninstalled via ynh.
    func testHarness_registryInstalled_hasRegistrySourceType() throws {
        let json = """
            {
                "name": "david",
                "version_installed": "0.1.0",
                "default_vendor": "claude",
                "path": "/Users/dev/.ynh/harnesses/david",
                "installed_from": {
                    "source_type": "registry",
                    "source": "https://github.com/eyelock/assistants",
                    "path": null,
                    "registry_name": "eyelock-assistants",
                    "installed_at": "2026-01-01T00:00:00Z"
                },
                "artifacts": {"skills": 2, "agents": 1, "rules": 0, "commands": 0},
                "includes": [],
                "delegates_to": []
            }
            """
        let h = try JSONDecoder().decode(Harness.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(h.installedFrom)
        XCTAssertEqual(h.installedFrom?.sourceType, "registry")
    }

    // MARK: - JSONFragment

    func testJSONFragment_decodesObject() throws {
        let json = """
            {"name": "test", "value": 42}
            """
        let fragment = try JSONDecoder().decode(JSONFragment.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(fragment.rawString.contains("name"))
        XCTAssertTrue(fragment.rawString.contains("value"))
    }

    func testJSONFragment_decodesArray() throws {
        let fragment = try JSONDecoder().decode(
            JSONFragment.self, from: "[1,2,3]".data(using: .utf8)!)
        XCTAssertTrue(fragment.rawString.contains("1"))
    }

    func testJSONFragment_decodesObjectWithMixedTypes() throws {
        let json = """
            {"str":"hello","num":3.14,"bool":true,"null":null,"arr":[1,2]}
            """
        let fragment = try JSONDecoder().decode(JSONFragment.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(fragment.rawString.contains("hello"))
        XCTAssertTrue(fragment.rawString.contains("3.14"))
        XCTAssertTrue(fragment.rawString.contains("true"))
    }

    func testJSONFragment_decodesArrayOfObjects() throws {
        let json = """
            [{"a":1},{"b":2}]
            """
        let fragment = try JSONDecoder().decode(JSONFragment.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(fragment.rawString.contains("a"))
        XCTAssertTrue(fragment.rawString.contains("b"))
    }

    func testJSONFragment_encodesBack() throws {
        let json = """
            {"key":"value"}
            """
        let fragment = try JSONDecoder().decode(JSONFragment.self, from: json.data(using: .utf8)!)
        let encoded = try JSONEncoder().encode(fragment)
        XCTAssertFalse(encoded.isEmpty)
    }

    func testJSONFragment_equatable() throws {
        let json = "{\"a\":1}"
        let f1 = try JSONDecoder().decode(JSONFragment.self, from: json.data(using: .utf8)!)
        let f2 = try JSONDecoder().decode(JSONFragment.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(f1, f2)
    }

    func testJSONFragment_nestedObject() throws {
        let json = """
            {"outer": {"inner": "value"}}
            """
        let fragment = try JSONDecoder().decode(JSONFragment.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(fragment.rawString.contains("inner"))
    }

    // MARK: - HarnessInfo

    func testHarnessInfo_codable_noManifest() throws {
        let json = """
            {
                "name": "test-harness",
                "version_installed": "1.0",
                "description": null,
                "default_vendor": "claude",
                "path": "/path/to/harness"
            }
            """
        let info = try JSONDecoder().decode(HarnessInfo.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(info.name, "test-harness")
        XCTAssertEqual(info.version, "1.0")
        XCTAssertNil(info.description)
        XCTAssertEqual(info.defaultVendor, "claude")
        XCTAssertNil(info.manifest)
        XCTAssertNil(info.installedFrom)
    }

    func testHarnessInfo_codable_withManifest() throws {
        let json = """
            {
                "name": "test",
                "version_installed": "2.0",
                "default_vendor": "codex",
                "path": "/path",
                "manifest": {"tool": "termq", "version": "1"}
            }
            """
        let info = try JSONDecoder().decode(HarnessInfo.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(info.manifest)
        XCTAssertTrue(info.manifest!.rawString.contains("tool"))
    }

    func testHarnessInfo_codable_withInstalledFrom() throws {
        let json = """
            {
                "name": "test",
                "version_installed": "1.0",
                "default_vendor": "claude",
                "path": "/p",
                "installed_from": {
                    "source_type": "local",
                    "source": "/local/path",
                    "path": null,
                    "registry_name": null,
                    "installed_at": "2025-01-01"
                }
            }
            """
        let info = try JSONDecoder().decode(HarnessInfo.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(info.installedFrom)
        XCTAssertEqual(info.installedFrom?.sourceType, "local")
    }

    func testHarnessInfo_customCodingKeys() throws {
        let json = """
            {"name":"h","version_installed":"v","default_vendor":"claude","path":"/p"}
            """
        let info = try JSONDecoder().decode(HarnessInfo.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(info.defaultVendor, "claude")
    }

    // MARK: - HarnessDetail

    func testHarnessDetail_init() throws {
        let infoJSON = """
            {"name":"h","version_installed":"1","default_vendor":"claude","path":"/p"}
            """
        let compositionJSON = """
            {
                "name": "h", "version": "1", "default_vendor": "claude",
                "artifacts": {"skills":[],"agents":[],"rules":[],"commands":[]},
                "includes": [], "delegates_to": [], "profiles": [],
                "counts": {"skills":0,"agents":0,"rules":0,"commands":0}
            }
            """
        let info = try JSONDecoder().decode(HarnessInfo.self, from: infoJSON.data(using: .utf8)!)
        let composition = try JSONDecoder().decode(
            HarnessComposition.self, from: compositionJSON.data(using: .utf8)!)
        let detail = HarnessDetail(info: info, composition: composition)
        XCTAssertEqual(detail.info.name, "h")
        XCTAssertEqual(detail.composition.name, "h")
    }
}
