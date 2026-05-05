import Foundation
import TermQShared
import XCTest

@testable import TermQ

@MainActor
final class AddIncludeContextTests: XCTestCase {

    private func makeContext(status: YNHStatus = .missing) -> AddIncludeContext {
        AddIncludeContext(
            harnessName: "test-harness",
            existingIncludes: [],
            editor: HarnessIncludeEditor(detector: MockYNHDetector(status: status)),
            detector: MockYNHDetector(status: status)
        )
    }

    private func makePlugin(picks: [String] = [], state: SkillsLoadState = .eager) -> MarketplacePlugin {
        MarketplacePlugin(
            id: UUID(),
            name: "test-plugin",
            description: "desc",
            version: nil,
            category: nil,
            tags: [],
            source: PluginSourceSpec(type: .relative, url: "./plugins/test", path: nil),
            picks: picks,
            skillsState: state
        )
    }

    private func makeMarketplace(plugins: [MarketplacePlugin] = []) -> Marketplace {
        Marketplace(
            id: UUID(),
            name: "Test Market",
            owner: "owner",
            description: nil,
            vendor: .claude,
            url: "https://github.com/owner/repo",
            ref: "main",
            plugins: plugins,
            lastFetched: nil,
            fetchError: nil
        )
    }

    // MARK: - Library stage

    func test_libraryResolvedSource_nilWhileBrowsing() {
        let context = makeContext()
        XCTAssertNil(context.libraryResolvedSource)
        XCTAssertNil(context.libraryResolvedRef)
    }

    func test_pickPlugin_resolvesViaPluginSpec() {
        let context = makeContext()
        let plugin = makePlugin()
        let market = makeMarketplace(plugins: [plugin])
        context.pickPlugin(plugin, marketplace: market)
        let resolved = context.libraryResolvedSource
        XCTAssertEqual(resolved?.url, "https://github.com/owner/repo")
        XCTAssertEqual(resolved?.path, "plugins/test")
        XCTAssertEqual(context.libraryResolvedRef, "main")
    }

    func test_pickPlugin_seedsPicksFromPluginEager() {
        let context = makeContext()
        let plugin = makePlugin(picks: ["a", "b"], state: .eager)
        let market = makeMarketplace(plugins: [plugin])
        context.pickPlugin(plugin, marketplace: market)
        XCTAssertEqual(context.resolvedPicks, ["a", "b"])
        XCTAssertEqual(context.selectedPicks, Set(["a", "b"]))
    }

    func test_backToBrowsing_clearsConfigureState() {
        let context = makeContext()
        let plugin = makePlugin(picks: ["a"], state: .eager)
        let market = makeMarketplace(plugins: [plugin])
        context.pickPlugin(plugin, marketplace: market)
        context.backToBrowsing()
        XCTAssertNil(context.libraryResolvedSource)
        XCTAssertEqual(context.resolvedPicks, [])
        XCTAssertEqual(context.selectedPicks, [])
    }

    // MARK: - Selection helpers

    func test_selectAllPicks() {
        let context = makeContext()
        let plugin = makePlugin(picks: ["a", "b", "c"], state: .eager)
        let market = makeMarketplace(plugins: [plugin])
        context.pickPlugin(plugin, marketplace: market)
        context.selectedPicks = []
        context.selectAllPicks()
        XCTAssertEqual(context.selectedPicks, Set(["a", "b", "c"]))
    }

    func test_selectNoPicks() {
        let context = makeContext()
        let plugin = makePlugin(picks: ["a", "b"], state: .eager)
        let market = makeMarketplace(plugins: [plugin])
        context.pickPlugin(plugin, marketplace: market)
        context.selectNoPicks()
        XCTAssertEqual(context.selectedPicks, [])
    }

    // MARK: - Command preview (library path)

    func test_libraryCommandPreview_basic() {
        let context = makeContext()
        let plugin = makePlugin(picks: [], state: .eager)
        let market = makeMarketplace(plugins: [plugin])
        context.pickPlugin(plugin, marketplace: market)
        let preview = context.libraryCommandPreview()
        XCTAssertTrue(preview.starts(with: "ynh include add test-harness https://github.com/owner/repo"))
    }

    func test_libraryCommandPreview_includesPath() {
        let context = makeContext()
        let plugin = makePlugin(picks: [], state: .eager)
        let market = makeMarketplace(plugins: [plugin])
        context.pickPlugin(plugin, marketplace: market)
        let preview = context.libraryCommandPreview()
        XCTAssertTrue(preview.contains("--path plugins/test"))
    }

    func test_libraryCommandPreview_omitsPickFlagWhenAllSelected() {
        let context = makeContext()
        let plugin = makePlugin(picks: ["a", "b"], state: .eager)
        let market = makeMarketplace(plugins: [plugin])
        context.pickPlugin(plugin, marketplace: market)
        // Default selection covers all picks.
        let preview = context.libraryCommandPreview()
        XCTAssertFalse(preview.contains("--pick"))
    }

    func test_libraryCommandPreview_omitsPickFlagWhenNoneSelected() {
        let context = makeContext()
        let plugin = makePlugin(picks: ["a", "b"], state: .eager)
        let market = makeMarketplace(plugins: [plugin])
        context.pickPlugin(plugin, marketplace: market)
        context.selectedPicks = []
        let preview = context.libraryCommandPreview()
        XCTAssertFalse(preview.contains("--pick"))
    }

    func test_libraryCommandPreview_includesPickFlagWhenSubsetSelected() {
        let context = makeContext()
        let plugin = makePlugin(picks: ["a", "b", "c"], state: .eager)
        let market = makeMarketplace(plugins: [plugin])
        context.pickPlugin(plugin, marketplace: market)
        context.selectedPicks = ["a"]
        let preview = context.libraryCommandPreview()
        XCTAssertTrue(preview.contains("--pick a"))
    }

    // MARK: - Command preview (git URL path)

    func test_gitURLCommandPreview_emptyShowsPlaceholder() {
        let context = makeContext()
        XCTAssertTrue(context.gitURLCommandPreview().contains("<url>"))
    }

    func test_gitURLCommandPreview_basic() {
        let context = makeContext()
        context.gitURL = "https://example.com/repo"
        let preview = context.gitURLCommandPreview()
        XCTAssertTrue(preview.contains("https://example.com/repo"))
        XCTAssertFalse(preview.contains("--path"))
        XCTAssertFalse(preview.contains("--pick"))
    }

    func test_gitURLCommandPreview_includesPath() {
        let context = makeContext()
        context.gitURL = "https://example.com/repo"
        context.gitPath = "subdir"
        let preview = context.gitURLCommandPreview()
        XCTAssertTrue(preview.contains("--path subdir"))
    }
}
