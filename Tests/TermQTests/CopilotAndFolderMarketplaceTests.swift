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

    // MARK: URL shorthand

    func test_normalizeRepoURL() {
        let want = "https://github.com/github/awesome-copilot"
        XCTAssertEqual(Marketplace.normalizeRepoURL("github.com/github/awesome-copilot"), want)
        XCTAssertEqual(Marketplace.normalizeRepoURL("  github/awesome-copilot "), want)
        XCTAssertEqual(Marketplace.normalizeRepoURL(want), want)
        XCTAssertEqual(Marketplace.normalizeRepoURL("git@github.com:o/r.git"), "git@github.com:o/r.git")
        XCTAssertEqual(Marketplace.normalizeRepoURL("/Users/me/mkt"), "/Users/me/mkt")
        XCTAssertEqual(Marketplace.normalizeRepoURL("file:///x/y"), "file:///x/y")
        XCTAssertEqual(Marketplace.normalizeRepoURL("a/b/c"), "a/b/c")
    }

    func test_sourceString_withoutDotSlashIsRelative() throws {
        func decode(_ s: String) throws -> PluginSourceSpec {
            try JSONDecoder().decode(PluginSourceSpec.self, from: Data("\"\(s)\"".utf8))
        }
        XCTAssertEqual(try decode("plugins/foo").type, .relative)
        XCTAssertEqual(try decode("./plugins/foo").type, .relative)
        XCTAssertEqual(try decode("https://github.com/o/r").type, .url)
        XCTAssertEqual(try decode("git@github.com:o/r.git").type, .url)
        XCTAssertEqual(try decode("github.com/o/r").type, .url)
        let r = try decode("plugins/foo").resolved(marketplaceURL: "https://github.com/o/r", folder: nil)
        XCTAssertEqual(r.url, "https://github.com/o/r")
        XCTAssertEqual(r.path, "plugins/foo")
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

    func test_parseIndex_detectsVendorFromLayout() throws {
        let root = try tempDir()
        let idx = root.appendingPathComponent(".github/plugin")
        try FileManager.default.createDirectory(at: idx, withIntermediateDirectories: true)
        try #"{"name":"AC","plugins":[]}"#
            .write(to: idx.appendingPathComponent("marketplace.json"), atomically: true, encoding: .utf8)
        // Added as Claude, but the repo only has the Copilot layout.
        let result = try MarketplaceFetcher.parseIndex(in: root, for: make(vendor: .claude))
        XCTAssertEqual(result.vendor, .copilot)
        XCTAssertEqual(result.name, "AC")
        // Chosen vendor still wins when its own layout exists.
        let own = try MarketplaceFetcher.parseIndex(in: root, for: make(vendor: .copilot))
        XCTAssertEqual(own.vendor, .copilot)
    }

    func test_parseIndex_followsPluginJsonRedirectToRepoRoot() throws {
        let root = try tempDir()
        let fm = FileManager.default
        func write(_ path: String, _ text: String) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(
            ".github/plugin/marketplace.json",
            #"{"name":"AC","plugins":[{"name":"p","source":"plugins/p"},{"name":"ext","source":"plugins/ext"}]}"#)
        try write(
            "plugins/p/plugin.json",
            #"{"extensions":{"com.github.awesome-copilot":{"skills":["./skills/s/"],"agents":["./agents/a.md"]}}}"#)
        try write(
            "plugins/ext/plugin.json",
            #"{"extensions":{"com.github.awesome-copilot":{"extensions":["./extensions/e"]}}}"#)
        try write("skills/s/SKILL.md", "x")
        try write("agents/a.agent.md", "x")

        let result = try MarketplaceFetcher.parseIndex(in: root, for: make(vendor: .copilot))
        let p = try XCTUnwrap(result.plugins.first { $0.name == "p" })
        XCTAssertEqual(p.picks, ["agents/a.agent.md", "skills/s"])
        // Redirected content lives at the repo root, so the include is re-rooted there.
        XCTAssertNil(p.source.resolved(marketplaceURL: "https://github.com/o/r", folder: nil).path)
        // Extension-only plugins have nothing pickable and keep their own path.
        let ext = try XCTUnwrap(result.plugins.first { $0.name == "ext" })
        XCTAssertEqual(ext.picks, [])
        XCTAssertEqual(ext.skillsState, .unsupported("extensions"))
        XCTAssertEqual(p.skillsState, .eager)
        XCTAssertEqual(ext.source.resolved(marketplaceURL: "u", folder: nil).path, "plugins/ext")
    }

    func test_redirectedArtifacts_rejectsOffLayoutAndEscapingPaths() throws {
        let root = try tempDir()
        let fm = FileManager.default
        func write(_ path: String, _ text: String) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let outside = try tempDir()
        try "x".write(to: outside.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: root.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("skills/evil"), withDestinationURL: outside)
        try write("other/foo/SKILL.md", "x")
        try write("skills/ok/SKILL.md", "x")
        try write(
            "plugins/p/plugin.json",
            #"{"extensions":{"com.github.awesome-copilot":{"skills":["./skills/ok/","./other/foo/","./skills/evil/","./skills/../other/foo/"]}}}"#
        )
        let picks = MarketplaceFetcher.redirectedArtifacts(
            pluginDir: root.appendingPathComponent("plugins/p"), marketplaceRoot: root)
        XCTAssertEqual(picks, ["skills/ok"])
    }

    // MARK: Pinned plugin sources

    func test_pluginSource_decodesRefAndShaAndPrefersSha() throws {
        let json =
            #"{"source":"github","repo":"o/r","path":"p","ref":"v1.2.0","sha":"44594ff1f61b8c8ff3fd1a26dd6744655a9204dd"}"#
        let spec = try JSONDecoder().decode(PluginSourceSpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec.ref, "v1.2.0")
        XCTAssertEqual(spec.pin, "44594ff1f61b8c8ff3fd1a26dd6744655a9204dd")
        let refOnly = try JSONDecoder().decode(
            PluginSourceSpec.self, from: Data(#"{"source":"github","repo":"o/r","ref":"v1"}"#.utf8))
        XCTAssertEqual(refOnly.pin, "v1")
        let none = try JSONDecoder().decode(
            PluginSourceSpec.self, from: Data(#"{"source":"github","repo":"o/r"}"#.utf8))
        XCTAssertNil(none.pin)
    }

    func test_pluginSource_pinSurvivesPersistenceRoundTrip() throws {
        let spec = PluginSourceSpec(type: .github, url: "https://github.com/o/r", ref: "v1", sha: "abc1234")
        let back = try JSONDecoder().decode(PluginSourceSpec.self, from: try JSONEncoder().encode(spec))
        XCTAssertEqual(back.ref, "v1")
        XCTAssertEqual(back.sha, "abc1234")
    }

    func test_effectiveRef_marketplaceRefOnlyForRelativePlugins() {
        let relative = PluginSourceSpec(type: .relative, url: "./plugins/x")
        XCTAssertEqual(relative.effectiveRef(marketplaceRef: "main"), "main")
        XCTAssertNil(relative.effectiveRef(marketplaceRef: nil))
        XCTAssertNil(relative.effectiveRef(marketplaceRef: ""))
        // An external plugin is a different repo: the marketplace's ref must not leak onto it.
        let external = PluginSourceSpec(type: .github, url: "https://github.com/o/r", ref: "v1", sha: "abc1234")
        XCTAssertEqual(external.effectiveRef(marketplaceRef: "main"), "abc1234")
        let unpinned = PluginSourceSpec(type: .github, url: "https://github.com/o/r")
        XCTAssertNil(unpinned.effectiveRef(marketplaceRef: "main"))
    }

    func test_unsupportedState_roundTripsAndIsResolved() throws {
        let data = try JSONEncoder().encode(SkillsLoadState.unsupported("extensions"))
        XCTAssertEqual(try JSONDecoder().decode(SkillsLoadState.self, from: data), .unsupported("extensions"))
        XCTAssertTrue(SkillsLoadState.unsupported("x").isResolved)
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
