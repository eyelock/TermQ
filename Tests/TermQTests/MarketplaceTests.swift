import Foundation
import XCTest

@testable import TermQ

// MARK: - Marketplace model tests

final class MarketplaceModelTests: XCTestCase {

    // MARK: MarketplaceVendor

    func test_vendor_displayNames() {
        XCTAssertEqual(MarketplaceVendor.claude.displayName, "Claude")
        XCTAssertEqual(MarketplaceVendor.cursor.displayName, "Cursor")
    }

    func test_vendor_indexPaths() {
        XCTAssertEqual(MarketplaceVendor.claude.indexPath, ".claude-plugin/marketplace.json")
        XCTAssertEqual(MarketplaceVendor.cursor.indexPath, ".cursor-plugin/marketplace.json")
    }

    func test_vendor_codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for vendor in MarketplaceVendor.allCases {
            let data = try encoder.encode(vendor)
            let decoded = try decoder.decode(MarketplaceVendor.self, from: data)
            XCTAssertEqual(decoded, vendor)
        }
    }

    // MARK: PluginSourceType

    func test_sourceType_isRelative() {
        XCTAssertTrue(PluginSourceType.relative.isRelative)
        XCTAssertFalse(PluginSourceType.github.isRelative)
        XCTAssertFalse(PluginSourceType.url.isRelative)
    }

    func test_sourceType_isExternal() {
        XCTAssertFalse(PluginSourceType.relative.isExternal)
        XCTAssertTrue(PluginSourceType.github.isExternal)
        XCTAssertTrue(PluginSourceType.url.isExternal)
        XCTAssertTrue(PluginSourceType.npm.isExternal)
        XCTAssertFalse(PluginSourceType.unknown.isExternal)
    }

    // MARK: PluginSourceSpec — custom decoder

    func test_pluginSourceSpec_decodesFromString_relative() throws {
        let json = #""./plugins/foo""#
        let spec = try JSONDecoder().decode(PluginSourceSpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec.type, .relative)
        XCTAssertEqual(spec.url, "./plugins/foo")
        XCTAssertNil(spec.path)
    }

    func test_pluginSourceSpec_decodesFromString_absolute() throws {
        let json = #""https://example.com/repo""#
        let spec = try JSONDecoder().decode(PluginSourceSpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec.type, .url)
        XCTAssertEqual(spec.url, "https://example.com/repo")
    }

    func test_pluginSourceSpec_decodesFromObject_github() throws {
        let json = #"{"source": "github", "url": "owner/repo", "path": "plugins"}"#
        let spec = try JSONDecoder().decode(PluginSourceSpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec.type, .github)
        XCTAssertEqual(spec.url, "owner/repo")
        XCTAssertEqual(spec.path, "plugins")
    }

    func test_pluginSourceSpec_decodesFromObject_unknownType() throws {
        let json = #"{"source": "future-type", "url": "somewhere"}"#
        let spec = try JSONDecoder().decode(PluginSourceSpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec.type, .unknown)
    }

    // MARK: SkillsLoadState — codable

    func test_skillsLoadState_roundTrip_eager() throws {
        try assertSkillsStateRoundTrip(.eager)
    }

    func test_skillsLoadState_roundTrip_pending() throws {
        try assertSkillsStateRoundTrip(.pending)
    }

    func test_skillsLoadState_roundTrip_failed() throws {
        try assertSkillsStateRoundTrip(.failed("network error"))
    }

    func test_skillsLoadState_loadingEncodesAsPending() throws {
        // .loading is transient — should survive encode/decode as .pending
        let data = try JSONEncoder().encode(SkillsLoadState.loading)
        let decoded = try JSONDecoder().decode(SkillsLoadState.self, from: data)
        XCTAssertEqual(decoded, .pending)
    }

    func test_skillsLoadState_isResolved() {
        XCTAssertTrue(SkillsLoadState.eager.isResolved)
        XCTAssertTrue(SkillsLoadState.failed("x").isResolved)
        XCTAssertFalse(SkillsLoadState.pending.isResolved)
        XCTAssertFalse(SkillsLoadState.loading.isResolved)
    }

    // MARK: RawMarketplaceIndex — owner parsing

    func test_rawMarketplaceIndex_ownerAsString() throws {
        let json = #"{"name": "My Marketplace", "owner": "alice", "plugins": []}"#
        let raw = try JSONDecoder().decode(RawMarketplaceIndex.self, from: Data(json.utf8))
        XCTAssertEqual(raw.name, "My Marketplace")
        XCTAssertEqual(raw.owner, "alice")
        XCTAssertEqual(raw.plugins.count, 0)
    }

    func test_rawMarketplaceIndex_ownerAsObject() throws {
        let json = #"{"owner": {"name": "Bob", "email": "bob@example.com"}, "plugins": []}"#
        let raw = try JSONDecoder().decode(RawMarketplaceIndex.self, from: Data(json.utf8))
        XCTAssertEqual(raw.owner, "Bob")
    }

    func test_rawMarketplaceIndex_ownerMissing() throws {
        let json = #"{"plugins": []}"#
        let raw = try JSONDecoder().decode(RawMarketplaceIndex.self, from: Data(json.utf8))
        XCTAssertNil(raw.owner)
    }

    func test_rawMarketplaceIndex_pluginsParsed() throws {
        let json = """
            {
                "plugins": [
                    {"name": "my-plugin", "version": "1.0", "tags": ["ai"]},
                    {"name": "other-plugin"}
                ]
            }
            """
        let raw = try JSONDecoder().decode(RawMarketplaceIndex.self, from: Data(json.utf8))
        XCTAssertEqual(raw.plugins.count, 2)
        XCTAssertEqual(raw.plugins[0].name, "my-plugin")
        XCTAssertEqual(raw.plugins[0].version, "1.0")
        XCTAssertEqual(raw.plugins[0].tags, ["ai"])
        XCTAssertEqual(raw.plugins[1].name, "other-plugin")
        XCTAssertNil(raw.plugins[1].version)
    }

    // MARK: - Helpers

    private func assertSkillsStateRoundTrip(_ state: SkillsLoadState) throws {
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SkillsLoadState.self, from: data)
        XCTAssertEqual(decoded, state)
    }
}

// MARK: - MarketplaceFetcher.enumerateArtifacts tests

final class MarketplaceFetcherEnumerationTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termq-mkt-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
    }

    func test_enumerate_emptyDirectory_returnsEmpty() {
        XCTAssertEqual(MarketplaceFetcher.enumerateArtifacts(in: tmpDir), [])
    }

    func test_enumerate_skillWithSKILLmd_included() throws {
        let skillDir = tmpDir.appendingPathComponent("skills/my-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try "# My Skill".write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let results = MarketplaceFetcher.enumerateArtifacts(in: tmpDir)
        XCTAssertEqual(results, ["skills/my-skill"])
    }

    func test_enumerate_skillDirectoryWithoutSKILLmd_excluded() throws {
        let skillDir = tmpDir.appendingPathComponent("skills/empty-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        XCTAssertEqual(MarketplaceFetcher.enumerateArtifacts(in: tmpDir), [])
    }

    func test_enumerate_agents_included() throws {
        let agentsDir = tmpDir.appendingPathComponent("agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try "# Agent".write(to: agentsDir.appendingPathComponent("my-agent.md"), atomically: true, encoding: .utf8)

        let results = MarketplaceFetcher.enumerateArtifacts(in: tmpDir)
        XCTAssertEqual(results, ["agents/my-agent"])
    }

    func test_enumerate_commands_included() throws {
        let dir = tmpDir.appendingPathComponent("commands", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "# Cmd".write(to: dir.appendingPathComponent("build.md"), atomically: true, encoding: .utf8)

        XCTAssertEqual(MarketplaceFetcher.enumerateArtifacts(in: tmpDir), ["commands/build"])
    }

    func test_enumerate_rules_included() throws {
        let dir = tmpDir.appendingPathComponent("rules", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "# Rule".write(to: dir.appendingPathComponent("style.md"), atomically: true, encoding: .utf8)

        XCTAssertEqual(MarketplaceFetcher.enumerateArtifacts(in: tmpDir), ["rules/style"])
    }

    func test_enumerate_nonMdFilesInAgents_excluded() throws {
        let dir = tmpDir.appendingPathComponent("agents", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "data".write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "# Agent".write(to: dir.appendingPathComponent("real.md"), atomically: true, encoding: .utf8)

        XCTAssertEqual(MarketplaceFetcher.enumerateArtifacts(in: tmpDir), ["agents/real"])
    }

    func test_enumerate_resultsAreSorted() throws {
        let skillsDir = tmpDir.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        for name in ["zebra", "alpha", "middle"] {
            let dir = skillsDir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }

        let results = MarketplaceFetcher.enumerateArtifacts(in: tmpDir)
        XCTAssertEqual(results, ["skills/alpha", "skills/middle", "skills/zebra"])
    }

    // enumerateArtifacts sorts globally across all artifact types (agents < commands < rules < skills)
    // because results.sorted() is called once on the combined array.
    func test_enumerate_mixedTypes_allIncluded() throws {
        // Skill
        let skillDir = tmpDir.appendingPathComponent("skills/my-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try "".write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // Agent
        let agentsDir = tmpDir.appendingPathComponent("agents")
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try "".write(to: agentsDir.appendingPathComponent("my-agent.md"), atomically: true, encoding: .utf8)

        // Rule
        let rulesDir = tmpDir.appendingPathComponent("rules")
        try FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        try "".write(to: rulesDir.appendingPathComponent("lint.md"), atomically: true, encoding: .utf8)

        let results = MarketplaceFetcher.enumerateArtifacts(in: tmpDir)
        XCTAssertEqual(results, ["agents/my-agent", "rules/lint", "skills/my-skill"])
    }
}

// MARK: - AddMarketplaceSheet.extractOrgRepo tests

final class ExtractOrgRepoTests: XCTestCase {

    func test_https_standard() {
        XCTAssertEqual(AddMarketplaceSheet.extractOrgRepo(from: "https://github.com/owner/repo"), "owner/repo")
    }

    func test_https_dotGit_stripped() {
        XCTAssertEqual(AddMarketplaceSheet.extractOrgRepo(from: "https://github.com/owner/repo.git"), "owner/repo")
    }

    func test_https_trailingSlash() {
        XCTAssertEqual(AddMarketplaceSheet.extractOrgRepo(from: "https://github.com/owner/repo/"), "owner/repo")
    }

    func test_ssh_url() {
        XCTAssertEqual(AddMarketplaceSheet.extractOrgRepo(from: "git@github.com:owner/repo.git"), "owner/repo")
    }

    func test_partialInput_repoOnly() {
        XCTAssertEqual(AddMarketplaceSheet.extractOrgRepo(from: "just-a-repo"), "just-a-repo")
    }

    func test_empty() {
        XCTAssertEqual(AddMarketplaceSheet.extractOrgRepo(from: ""), "")
    }
}

// MARK: - KnownHarnesses tests

final class KnownHarnessesTests: XCTestCase {

    func test_defaults_containsAssistants() {
        XCTAssertTrue(KnownHarnesses.defaultNames.contains("assistants"))
    }

    func test_defaults_containsYnhDev() {
        XCTAssertTrue(KnownHarnesses.defaultNames.contains("ynh-dev"))
    }

    func test_defaults_containsTermqDev() {
        XCTAssertTrue(KnownHarnesses.defaultNames.contains("termq-dev"))
    }

    func test_defaults_areNonEmpty() {
        XCTAssertFalse(KnownHarnesses.defaultNames.isEmpty)
    }
}

// MARK: - KnownMarketplaces tests

final class KnownMarketplacesTests: XCTestCase {

    func test_defaults_containsClaudePluginsOfficial() {
        let urls = KnownMarketplaces.all.map(\.url)
        XCTAssertTrue(
            urls.contains("https://github.com/anthropics/claude-plugins-official"),
            "Expected claude-plugins-official in defaults"
        )
    }

    func test_defaults_containsEyelockAssistants() {
        let urls = KnownMarketplaces.all.map(\.url)
        XCTAssertTrue(
            urls.contains("https://github.com/eyelock/assistants"),
            "Expected eyelock/assistants in defaults"
        )
    }

    func test_defaults_allHaveClaudeVendor() {
        for seed in KnownMarketplaces.all {
            XCTAssertEqual(seed.vendor, .claude, "\(seed.name) should use .claude vendor")
        }
    }

    func test_defaults_allHaveNonEmptyFields() {
        for seed in KnownMarketplaces.all {
            XCTAssertFalse(seed.name.isEmpty, "name should not be empty")
            XCTAssertFalse(seed.owner.isEmpty, "owner should not be empty")
            XCTAssertFalse(seed.url.isEmpty, "url should not be empty")
        }
    }

    func test_defaults_urlsAreUnique() {
        let urls = KnownMarketplaces.all.map(\.url)
        XCTAssertEqual(urls.count, Set(urls).count, "Default marketplace URLs should be unique")
    }
}

// MARK: - PluginSourceSpec.resolved(marketplaceURL:) tests

final class PluginSourceSpecResolvedTests: XCTestCase {

    private let marketplaceURL = "https://github.com/eyelock/assistants"

    func test_resolved_githubSource_expandsShorthand() {
        let spec = PluginSourceSpec(type: .github, url: "owner/repo", path: "plugins")
        let (url, path) = spec.resolved(marketplaceURL: marketplaceURL)
        XCTAssertEqual(url, "github.com/owner/repo")
        XCTAssertEqual(path, "plugins")
    }

    func test_resolved_githubSource_alreadyExpanded_passesThrough() {
        let spec = PluginSourceSpec(type: .github, url: "github.com/owner/repo")
        let (url, path) = spec.resolved(marketplaceURL: marketplaceURL)
        XCTAssertEqual(url, "github.com/owner/repo")
        XCTAssertNil(path)
    }

    func test_resolved_relativeSource_usesMarketplaceURL() {
        let spec = PluginSourceSpec(type: .relative, url: "./skills/infra")
        let (url, path) = spec.resolved(marketplaceURL: marketplaceURL)
        XCTAssertEqual(url, marketplaceURL)
        XCTAssertEqual(path, "skills/infra")
    }

    func test_resolved_relativeSource_withoutDotSlash_usesMarketplaceURL() {
        let spec = PluginSourceSpec(type: .relative, url: "skills/infra")
        let (url, path) = spec.resolved(marketplaceURL: marketplaceURL)
        XCTAssertEqual(url, marketplaceURL)
        XCTAssertEqual(path, "skills/infra")
    }

    func test_resolved_relativeSource_withSubpath_appendsSubpath() {
        let spec = PluginSourceSpec(type: .relative, url: "./plugins/foo", path: "src")
        let (url, path) = spec.resolved(marketplaceURL: marketplaceURL)
        XCTAssertEqual(url, marketplaceURL)
        XCTAssertEqual(path, "plugins/foo/src")
    }

    func test_resolved_relativeSource_rootDot_returnsNilPath() {
        let spec = PluginSourceSpec(type: .relative, url: "./")
        let (url, path) = spec.resolved(marketplaceURL: marketplaceURL)
        XCTAssertEqual(url, marketplaceURL)
        XCTAssertNil(path)
    }

    func test_resolved_urlSource_passesThrough() {
        let spec = PluginSourceSpec(type: .url, url: "https://example.com/pkg.tgz")
        let (url, path) = spec.resolved(marketplaceURL: marketplaceURL)
        XCTAssertEqual(url, "https://example.com/pkg.tgz")
        XCTAssertNil(path)
    }

    func test_resolved_unknownTypeWithDotSlashURL_treatedAsRelative() {
        // After persistence round-trip through old decoder, relative plugins had type=.unknown.
        // resolved() must still resolve them by falling back to the URL prefix.
        let spec = PluginSourceSpec(type: .unknown, url: "./skills/infra")
        let (url, path) = spec.resolved(marketplaceURL: marketplaceURL)
        XCTAssertEqual(url, marketplaceURL)
        XCTAssertEqual(path, "skills/infra")
    }

    func test_resolved_persistenceRoundTrip_preservesRelativeType() throws {
        // Encode then decode — type must survive so resolved() works on reloaded data.
        let spec = PluginSourceSpec(type: .relative, url: "./skills/infra")
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(PluginSourceSpec.self, from: data)
        XCTAssertEqual(decoded.type, .relative)
        let (url, path) = decoded.resolved(marketplaceURL: marketplaceURL)
        XCTAssertEqual(url, marketplaceURL)
        XCTAssertEqual(path, "skills/infra")
    }
}

// MARK: - AuthorStepStatus tests

final class AuthorStepStatusTests: XCTestCase {

    func test_isTerminal_done() {
        XCTAssertTrue(AuthorStepStatus.done.isTerminal)
    }

    func test_isTerminal_failed() {
        XCTAssertTrue(AuthorStepStatus.failed("err").isTerminal)
    }

    func test_isTerminal_pending() {
        XCTAssertFalse(AuthorStepStatus.pending.isTerminal)
    }

    func test_isTerminal_running() {
        XCTAssertFalse(AuthorStepStatus.running.isTerminal)
    }
}
