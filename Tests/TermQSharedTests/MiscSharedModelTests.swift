import Foundation
import XCTest

@testable import TermQShared

final class MiscSharedModelTests: XCTestCase {

    // MARK: - YNHPaths

    func testYNHPaths_init() {
        let paths = YNHPaths(
            home: "/home/user/.ynh",
            config: "/home/user/.ynh/config",
            harnesses: "/home/user/.ynh/harnesses",
            symlinks: "/home/user/.ynh/bin",
            cache: "/home/user/.ynh/cache",
            run: "/home/user/.ynh/run",
            bin: "/usr/local/bin"
        )
        XCTAssertEqual(paths.home, "/home/user/.ynh")
        XCTAssertEqual(paths.config, "/home/user/.ynh/config")
        XCTAssertEqual(paths.harnesses, "/home/user/.ynh/harnesses")
        XCTAssertEqual(paths.symlinks, "/home/user/.ynh/bin")
        XCTAssertEqual(paths.cache, "/home/user/.ynh/cache")
        XCTAssertEqual(paths.run, "/home/user/.ynh/run")
        XCTAssertEqual(paths.bin, "/usr/local/bin")
    }

    func testYNHPaths_equatable() {
        let p1 = YNHPaths(
            home: "/a", config: "/b", harnesses: "/c",
            symlinks: "/d", cache: "/e", run: "/f", bin: "/g")
        let p2 = YNHPaths(
            home: "/a", config: "/b", harnesses: "/c",
            symlinks: "/d", cache: "/e", run: "/f", bin: "/g")
        XCTAssertEqual(p1, p2)
    }

    func testYNHPaths_inequitable() {
        let p1 = YNHPaths(
            home: "/a", config: "/b", harnesses: "/c",
            symlinks: "/d", cache: "/e", run: "/f", bin: "/g")
        let p2 = YNHPaths(
            home: "/x", config: "/b", harnesses: "/c",
            symlinks: "/d", cache: "/e", run: "/f", bin: "/g")
        XCTAssertNotEqual(p1, p2)
    }

    func testYNHPaths_codable() throws {
        let json = """
            {
                "home": "/home/user/.ynh",
                "config": "/home/user/.ynh/config",
                "harnesses": "/home/user/.ynh/harnesses",
                "symlinks": "/home/user/.ynh/symlinks",
                "cache": "/home/user/.ynh/cache",
                "run": "/home/user/.ynh/run",
                "bin": "/home/user/.ynh/bin"
            }
            """
        let paths = try JSONDecoder().decode(YNHPaths.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(paths.home, "/home/user/.ynh")
        XCTAssertEqual(paths.run, "/home/user/.ynh/run")
    }

    func testYNHPaths_codableRoundTrip() throws {
        let original = YNHPaths(
            home: "/h", config: "/c", harnesses: "/hr",
            symlinks: "/s", cache: "/ca", run: "/r", bin: "/b")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(YNHPaths.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - ExternalEditor

    func testExternalEditor_init() {
        let editor = ExternalEditor(
            kind: .vscode,
            displayName: "VS Code",
            appURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        )
        XCTAssertEqual(editor.kind, .vscode)
        XCTAssertEqual(editor.displayName, "VS Code")
        XCTAssertEqual(editor.id, .vscode)
    }

    func testExternalEditor_allKinds() {
        let kinds: [ExternalEditor.Kind] = [.xcode, .vscode, .cursor, .intellij, .intellijCE]
        for kind in kinds {
            let editor = ExternalEditor(
                kind: kind,
                displayName: "Test",
                appURL: URL(fileURLWithPath: "/tmp"))
            XCTAssertEqual(editor.id, kind)
        }
    }

    func testExternalEditor_kindRawValues() {
        XCTAssertEqual(ExternalEditor.Kind.xcode.rawValue, "xcode")
        XCTAssertEqual(ExternalEditor.Kind.vscode.rawValue, "vscode")
        XCTAssertEqual(ExternalEditor.Kind.cursor.rawValue, "cursor")
        XCTAssertEqual(ExternalEditor.Kind.intellij.rawValue, "intellij")
        XCTAssertEqual(ExternalEditor.Kind.intellijCE.rawValue, "intellijCE")
    }

    // MARK: - Vendor

    func testVendor_codable_customKeys() throws {
        let json = """
            {
                "name": "claude",
                "display_name": "Claude Code",
                "cli": "claude",
                "config_dir": ".claude",
                "available": true
            }
            """
        let vendor = try JSONDecoder().decode(Vendor.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(vendor.vendorID, "claude")
        XCTAssertEqual(vendor.displayName, "Claude Code")
        XCTAssertEqual(vendor.binary, "claude")
        XCTAssertEqual(vendor.configDir, ".claude")
        XCTAssertTrue(vendor.available)
        XCTAssertEqual(vendor.id, "claude")
    }

    func testVendor_unavailable() throws {
        let json = """
            {"name":"codex","display_name":"Codex","cli":"codex","config_dir":".codex","available":false}
            """
        let vendor = try JSONDecoder().decode(Vendor.self, from: json.data(using: .utf8)!)
        XCTAssertFalse(vendor.available)
        XCTAssertEqual(vendor.id, "codex")
    }

    func testVendor_codableRoundTrip() throws {
        let json = """
            {"name":"cursor","display_name":"Cursor","cli":"cursor","config_dir":".cursor","available":true}
            """
        let vendor = try JSONDecoder().decode(Vendor.self, from: json.data(using: .utf8)!)
        let data = try JSONEncoder().encode(vendor)
        let decoded = try JSONDecoder().decode(Vendor.self, from: data)
        XCTAssertEqual(decoded.vendorID, vendor.vendorID)
        XCTAssertEqual(decoded.displayName, vendor.displayName)
    }

    // MARK: - YNHSource

    func testYNHSource_codable() throws {
        let json = """
            {"name":"local","path":"/home/user/harnesses","description":"Local harnesses","harnesses":5}
            """
        let source = try JSONDecoder().decode(YNHSource.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(source.name, "local")
        XCTAssertEqual(source.path, "/home/user/harnesses")
        XCTAssertEqual(source.description, "Local harnesses")
        XCTAssertEqual(source.harnesses, 5)
        XCTAssertEqual(source.id, "local")
    }

    func testYNHSource_nilDescription() throws {
        let json = """
            {"name":"empty","path":"/path","description":null,"harnesses":0}
            """
        let source = try JSONDecoder().decode(YNHSource.self, from: json.data(using: .utf8)!)
        XCTAssertNil(source.description)
        XCTAssertEqual(source.harnesses, 0)
    }

    func testYNHSource_codableRoundTrip() throws {
        let json = """
            {"name":"x","path":"/x","description":"desc","harnesses":2}
            """
        let source = try JSONDecoder().decode(YNHSource.self, from: json.data(using: .utf8)!)
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(YNHSource.self, from: data)
        XCTAssertEqual(decoded.name, source.name)
        XCTAssertEqual(decoded.harnesses, source.harnesses)
    }

    // MARK: - SearchResult

    func testSearchResult_codable() throws {
        let json = """
            {
                "name": "dev-workflow",
                "description": "Development workflow harness",
                "keywords": ["dev", "workflow"],
                "repo": "git@github.com:foo/bar",
                "vendors": ["claude"],
                "version": "1.0.0",
                "from": {"type": "registry", "name": "official"}
            }
            """
        let result = try JSONDecoder().decode(SearchResult.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(result.name, "dev-workflow")
        XCTAssertEqual(result.description, "Development workflow harness")
        XCTAssertEqual(result.keywords, ["dev", "workflow"])
        XCTAssertEqual(result.vendors, ["claude"])
        XCTAssertEqual(result.version, "1.0.0")
        XCTAssertEqual(result.from.type, .registry)
        XCTAssertEqual(result.from.name, "official")
    }

    func testSearchResult_id_registryFormat() throws {
        let json = """
            {"name":"my-harness","from":{"type":"registry","name":"official"}}
            """
        let result = try JSONDecoder().decode(SearchResult.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(result.id, "registry:official:my-harness")
    }

    func testSearchResult_id_sourceFormat() throws {
        let json = """
            {"name":"local-h","from":{"type":"source","name":"local"}}
            """
        let result = try JSONDecoder().decode(SearchResult.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(result.id, "source:local:local-h")
    }

    func testSearchResult_nilOptionalFields() throws {
        let json = """
            {"name":"x","from":{"type":"source","name":"s"}}
            """
        let result = try JSONDecoder().decode(SearchResult.self, from: json.data(using: .utf8)!)
        XCTAssertNil(result.description)
        XCTAssertNil(result.keywords)
        XCTAssertNil(result.repo)
        XCTAssertNil(result.path)
        XCTAssertNil(result.vendors)
        XCTAssertNil(result.version)
    }

    func testOriginType_rawValues() {
        XCTAssertEqual(OriginType.registry.rawValue, "registry")
        XCTAssertEqual(OriginType.source.rawValue, "source")
    }

    // MARK: - ComposedArtifacts

    func testComposedArtifacts_all_combines() throws {
        let json = """
            {
                "skills": [{"name": "s1", "source": "main"}],
                "agents": [{"name": "a1", "source": "main"}, {"name": "a2", "source": "inc"}],
                "rules": [],
                "commands": [{"name": "c1", "source": "main"}]
            }
            """
        let artifacts = try JSONDecoder().decode(ComposedArtifacts.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(artifacts.all.count, 4)
        XCTAssertEqual(artifacts.skills.count, 1)
        XCTAssertEqual(artifacts.agents.count, 2)
        XCTAssertEqual(artifacts.rules.count, 0)
        XCTAssertEqual(artifacts.commands.count, 1)
    }

    func testComposedCounts_total() throws {
        let json = """
            {"skills":1,"agents":2,"rules":3,"commands":4}
            """
        let counts = try JSONDecoder().decode(ComposedCounts.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(counts.total, 10)
    }

    func testComposedArtifact_id() throws {
        let json = """
            {"name":"my-skill","source":"main"}
            """
        let artifact = try JSONDecoder().decode(ComposedArtifact.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(artifact.id, "main/my-skill")
    }
}
