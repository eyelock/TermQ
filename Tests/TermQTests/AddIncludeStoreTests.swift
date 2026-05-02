import Foundation
import TermQShared
import XCTest

@testable import TermQ

@MainActor
final class AddIncludeStoreTests: XCTestCase {

    private func makeStore(status: YNHStatus = .missing) -> AddIncludeStore {
        AddIncludeStore(detector: MockYNHDetector(status: status))
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

    // MARK: - Source resolution

    func test_resolvedSource_marketplaceMode_nilWithoutSelection() {
        let store = makeStore()
        store.sourceMode = .marketplace
        XCTAssertNil(store.resolvedSource)
        XCTAssertFalse(store.canLeaveSourceStep)
    }

    func test_resolvedSource_marketplaceMode_resolvesViaPluginSpec() {
        let store = makeStore()
        let plugin = makePlugin()
        let market = makeMarketplace(plugins: [plugin])
        store.sourceMode = .marketplace
        store.selectedPlugin = plugin
        store.selectedMarketplace = market
        let resolved = store.resolvedSource
        XCTAssertNotNil(resolved)
        // Relative source resolves to the marketplace URL, with the relative
        // path becoming the path argument.
        XCTAssertEqual(resolved?.url, "https://github.com/owner/repo")
        XCTAssertEqual(resolved?.path, "plugins/test")
    }

    func test_resolvedSource_gitURLMode_emptyURL_returnsNil() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitURL = "  "
        XCTAssertNil(store.resolvedSource)
    }

    func test_resolvedSource_gitURLMode_passesThroughURLAndPath() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitURL = "https://example.com/repo"
        store.gitPath = "subdir"
        let resolved = store.resolvedSource
        XCTAssertEqual(resolved?.url, "https://example.com/repo")
        XCTAssertEqual(resolved?.path, "subdir")
    }

    func test_resolvedSource_gitURLMode_emptyPath_returnsNilPath() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitURL = "https://example.com/repo"
        store.gitPath = ""
        XCTAssertEqual(store.resolvedSource?.path, nil)
    }

    // MARK: - Resolved ref

    func test_resolvedRef_marketplaceInheritsMarketplaceRef() {
        let store = makeStore()
        let market = makeMarketplace()
        store.sourceMode = .marketplace
        store.selectedMarketplace = market
        XCTAssertEqual(store.resolvedRef, "main")
    }

    func test_resolvedRef_gitURL_usesGitRef() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitRef = "feature/x"
        XCTAssertEqual(store.resolvedRef, "feature/x")
    }

    func test_resolvedRef_gitURL_emptyTrimsToNil() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitRef = "   "
        XCTAssertNil(store.resolvedRef)
    }

    // MARK: - Step transitions

    func test_advanceFromSource_marketplaceWithPicks_goesToPicks() {
        let store = makeStore()
        let plugin = makePlugin(picks: ["agents/a.md", "skills/b"])
        let market = makeMarketplace(plugins: [plugin])
        store.sourceMode = .marketplace
        store.selectedPlugin = plugin
        store.selectedMarketplace = market
        store.advanceFromSource()
        XCTAssertEqual(store.step, .picks)
        XCTAssertEqual(store.resolvedPicks, ["agents/a.md", "skills/b"])
        XCTAssertEqual(store.selectedPicks, Set(["agents/a.md", "skills/b"]))
    }

    func test_advanceFromSource_marketplaceNoPicksEager_skipsToReview() {
        let store = makeStore()
        let plugin = makePlugin(picks: [], state: .eager)
        let market = makeMarketplace(plugins: [plugin])
        store.sourceMode = .marketplace
        store.selectedPlugin = plugin
        store.selectedMarketplace = market
        store.advanceFromSource()
        XCTAssertEqual(store.step, .review)
    }

    func test_advanceFromSource_gitURL_skipsPicksAndGoesToReview() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitURL = "https://example.com/repo"
        store.advanceFromSource()
        XCTAssertEqual(store.step, .review)
        XCTAssertTrue(store.resolvedPicks.isEmpty)
    }

    func test_advanceFromSource_invalidSelection_isNoOp() {
        let store = makeStore()
        store.sourceMode = .marketplace
        store.advanceFromSource()
        XCTAssertEqual(store.step, .source)
    }

    func test_goBack_fromReviewWithPicks_returnsToPicks() {
        let store = makeStore()
        store.resolvedPicks = ["a"]
        store.step = .review
        store.goBack()
        XCTAssertEqual(store.step, .picks)
    }

    func test_goBack_fromReviewWithoutPicks_returnsToSource() {
        let store = makeStore()
        store.resolvedPicks = []
        store.step = .review
        store.goBack()
        XCTAssertEqual(store.step, .source)
    }

    func test_goBack_fromPicks_returnsToSource() {
        let store = makeStore()
        store.step = .picks
        store.goBack()
        XCTAssertEqual(store.step, .source)
    }

    // MARK: - Picks toggling

    func test_togglePick_addsAndRemoves() {
        let store = makeStore()
        store.resolvedPicks = ["a", "b"]
        store.selectedPicks = []
        store.togglePick("a")
        XCTAssertEqual(store.selectedPicks, Set(["a"]))
        store.togglePick("a")
        XCTAssertTrue(store.selectedPicks.isEmpty)
    }

    func test_selectAllAndNone() {
        let store = makeStore()
        store.resolvedPicks = ["a", "b", "c"]
        store.selectedPicks = []
        store.selectAllPicks()
        XCTAssertEqual(store.selectedPicks.count, 3)
        store.selectNoPicks()
        XCTAssertTrue(store.selectedPicks.isEmpty)
    }

    // MARK: - Command preview

    func test_commandPreview_basic() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitURL = "https://example.com/repo"
        XCTAssertEqual(
            store.commandPreview(harnessName: "h"),
            "ynh include add h https://example.com/repo"
        )
    }

    func test_commandPreview_includesPath() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitURL = "https://example.com/repo"
        store.gitPath = "sub"
        XCTAssertEqual(
            store.commandPreview(harnessName: "h"),
            "ynh include add h https://example.com/repo --path sub"
        )
    }

    func test_commandPreview_omitsPickFlagWhenAllSelected() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitURL = "u"
        store.resolvedPicks = ["a", "b"]
        store.selectedPicks = ["a", "b"]
        // All selected → no --pick flag (YNH default).
        XCTAssertEqual(
            store.commandPreview(harnessName: "h"),
            "ynh include add h u"
        )
    }

    func test_commandPreview_omitsPickFlagWhenNoneSelected() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitURL = "u"
        store.resolvedPicks = ["a", "b"]
        store.selectedPicks = []
        XCTAssertEqual(
            store.commandPreview(harnessName: "h"),
            "ynh include add h u"
        )
    }

    func test_commandPreview_includesPickFlagWhenSubsetSelected() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitURL = "u"
        store.resolvedPicks = ["a", "b", "c"]
        store.selectedPicks = ["b", "a"]
        XCTAssertEqual(
            store.commandPreview(harnessName: "h"),
            "ynh include add h u --pick a,b"
        )
    }

    // MARK: - Apply gating

    func test_canApply_falseWithoutReadyToolchain() {
        let store = makeStore(status: .missing)
        store.sourceMode = .gitURL
        store.gitURL = "https://example.com/repo"
        XCTAssertFalse(store.canApply)
    }

    func test_canApply_trueWithReadyToolchainAndSource() {
        let store = makeStore(
            status: .ready(
                ynhPath: "/usr/local/bin/ynh",
                yndPath: "/usr/local/bin/ynd",
                paths: YNHPaths(
                    home: "/tmp", config: "/tmp/c", harnesses: "/tmp/h",
                    symlinks: "/tmp/s", cache: "/tmp/c2", run: "/tmp/r", bin: "/tmp/b"
                )
            )
        )
        store.sourceMode = .gitURL
        store.gitURL = "https://example.com/repo"
        XCTAssertTrue(store.canApply)
    }

    // MARK: - Reset

    func test_reset_returnsToInitialState() {
        let store = makeStore()
        store.sourceMode = .gitURL
        store.gitURL = "u"
        store.step = .review
        store.resolvedPicks = ["a"]
        store.reset()
        XCTAssertEqual(store.step, .source)
        XCTAssertEqual(store.sourceMode, .marketplace)
        XCTAssertEqual(store.gitURL, "")
        XCTAssertTrue(store.resolvedPicks.isEmpty)
    }
}
