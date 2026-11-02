import Foundation
import XCTest

@testable import TermQ

final class CopilotAndFolderMarketplaceTests: XCTestCase {

    private func make(
        name: String = "n", url: String = "https://github.com/o/r", vendor: MarketplaceVendor = .claude,
        folder: String? = nil, customName: String? = nil
    ) -> Marketplace {
        Marketplace(
            id: UUID(), name: name, owner: "o", description: nil, vendor: vendor, url: url, ref: nil,
            plugins: [], lastFetched: nil, fetchError: nil, folder: folder, customName: customName)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mkt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: Display name

    func test_displayName_prefersCustomThenIndexNameThenShortURL() {
        XCTAssertEqual(make(name: "Index", customName: "Mine").displayName, "Mine")
        XCTAssertEqual(make(name: "Index", customName: "  ").displayName, "Index")
        XCTAssertEqual(make(name: "").displayName, GitURLHelper.shortURL("https://github.com/o/r"))
    }

    // MARK: Folder

    func test_normalizeFolder() {
        XCTAssertNil(Marketplace.normalizeFolder(nil))
        XCTAssertNil(Marketplace.normalizeFolder("  "))
        XCTAssertNil(Marketplace.normalizeFolder("/"))
        XCTAssertEqual(Marketplace.normalizeFolder("./plugins/a/"), "plugins/a")
        XCTAssertEqual(Marketplace.normalizeFolder("/sub"), "sub")
        XCTAssertNil(Marketplace.normalizeFolder("../x"))
        XCTAssertNil(Marketplace.normalizeFolder("a/../../x"))
    }

    func test_resolved_prefixesFolderForRelativeSources() {
        let spec = PluginSourceSpec(type: .relative, url: "./plugins/foo")
        let r = spec.resolved(marketplaceURL: "https://github.com/o/r", folder: "tools/")
        XCTAssertEqual(r.url, "https://github.com/o/r")
        XCTAssertEqual(r.path, "tools/plugins/foo")
        XCTAssertEqual(spec.resolved(marketplaceURL: "u", folder: nil).path, "plugins/foo")
    }

    func test_resolved_externalSourceIgnoresFolder() {
        let spec = PluginSourceSpec(type: .url, url: "https://example.com/x.git")
        XCTAssertEqual(spec.resolved(marketplaceURL: "u", folder: "tools").url, "https://example.com/x.git")
    }

    func test_codable_legacyJSONWithoutNewFieldsDecodes() throws {
        let data = try JSONEncoder().encode(make(folder: "a", customName: "b"))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "folder")
        obj.removeValue(forKey: "customName")
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(Marketplace.self, from: legacy)
        XCTAssertNil(decoded.folder)
        XCTAssertNil(decoded.customName)
    }

    func test_parseIndex_readsFromFolder() throws {
        let root = try tempDir()
        let idx = root.appendingPathComponent("tools/.claude-plugin")
        try FileManager.default.createDirectory(at: idx, withIntermediateDirectories: true)
        try #"{"name":"Sub","plugins":[{"name":"p","source":"./plugins/p"}]}"#
            .write(to: idx.appendingPathComponent("marketplace.json"), atomically: true, encoding: .utf8)
        let pdir = root.appendingPathComponent("tools/plugins/p/skills/s")
        try FileManager.default.createDirectory(at: pdir, withIntermediateDirectories: true)
        try "x".write(to: pdir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let result = try MarketplaceFetcher.parseIndex(in: root, for: make(folder: "tools"))
        XCTAssertEqual(result.name, "Sub")
        XCTAssertEqual(result.plugins.first?.picks, ["skills/s"])

        XCTAssertThrowsError(try MarketplaceFetcher.parseIndex(in: root, for: make()))
    }

    func test_parseIndex_customNameSurvivesRefresh() throws {
        let root = try tempDir()
        let idx = root.appendingPathComponent(".claude-plugin")
        try FileManager.default.createDirectory(at: idx, withIntermediateDirectories: true)
        try #"{"name":"Index Name","plugins":[]}"#
            .write(to: idx.appendingPathComponent("marketplace.json"), atomically: true, encoding: .utf8)
        let result = try MarketplaceFetcher.parseIndex(in: root, for: make(customName: "Short"))
        XCTAssertEqual(result.displayName, "Short")
    }

    // MARK: Copilot

    func test_copilotVendor_indexPathsIncludeClaudeFallback() {
        XCTAssertEqual(MarketplaceVendor.copilot.displayName, "Copilot")
        XCTAssertEqual(MarketplaceVendor.copilot.indexPath, ".github/plugin/marketplace.json")
        XCTAssertEqual(
            MarketplaceVendor.copilot.indexPaths,
            [".github/plugin/marketplace.json", ".claude-plugin/marketplace.json"])
    }

    func test_parseIndex_copilotFallsBackToClaudeLayout() throws {
        let root = try tempDir()
        let idx = root.appendingPathComponent(".claude-plugin")
        try FileManager.default.createDirectory(at: idx, withIntermediateDirectories: true)
        try #"{"name":"C","plugins":[]}"#
            .write(to: idx.appendingPathComponent("marketplace.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try MarketplaceFetcher.parseIndex(in: root, for: make(vendor: .copilot)).name, "C")
    }

    func test_importer_parsesSettings() throws {
        let json = """
            {"extraKnownMarketplaces":{
              "gh":{"source":{"source":"github","repo":"github/copilot-plugins"}},
              "dir":{"source":{"source":"directory","path":"/tmp/m"}},
              "g":{"source":{"source":"git","url":"https://example.com/x.git","ref":"main"}},
              "bad":{"source":{"source":"weird"}}}}
            """
        let found = try XCTUnwrap(CopilotMarketplaceImporter.parse(Data(json.utf8)))
        XCTAssertEqual(found.map(\.name), ["dir", "g", "gh"])
        XCTAssertTrue(found.allSatisfy { $0.vendor == .copilot })
        XCTAssertEqual(found.first { $0.name == "gh" }?.url, "https://github.com/github/copilot-plugins")
        XCTAssertTrue(found.first { $0.name == "dir" }?.isLocal == true)
        XCTAssertEqual(found.first { $0.name == "g" }?.ref, "main")
    }

    func test_importer_missingFileYieldsBuiltInOnly() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID()).json")
        let found = CopilotMarketplaceImporter.load(from: missing)
        XCTAssertEqual(found.map(\.url), ["https://github.com/github/awesome-copilot"])
    }

    func test_importer_noDuplicateOfBuiltIn() throws {
        let file = try tempDir().appendingPathComponent("settings.json")
        try #"{"extraKnownMarketplaces":{"a":{"source":{"source":"github","repo":"github/awesome-copilot"}}}}"#
            .write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(CopilotMarketplaceImporter.load(from: file).count, 1)
    }
}
