import Foundation
import XCTest

@testable import TermQ

/// Smoke tests for the four owner types extracted from ad-hoc `@AppStorage`
/// sites: `MarketplaceStore.autoRefresh`, `HarnessAuthorPreferences`,
/// `SidebarState`, and `GitConfigStore`. Each owner persists to a UserDefaults
/// suite isolated per test.
@MainActor
final class AppStorageOwnerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "AppStorageOwnerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
    }

    // MARK: - MarketplaceStore.autoRefresh

    func test_marketplaceStore_autoRefresh_defaultsToTrue() {
        let store = MarketplaceStore(fileURL: tempFile(), defaults: defaults)
        XCTAssertTrue(store.autoRefresh)
    }

    func test_marketplaceStore_autoRefresh_persists() {
        let first = MarketplaceStore(fileURL: tempFile(), defaults: defaults)
        first.autoRefresh = false

        let second = MarketplaceStore(fileURL: tempFile(), defaults: defaults)
        XCTAssertFalse(second.autoRefresh)
    }

    // MARK: - HarnessAuthorPreferences

    func test_authorPreferences_defaultDirectory_emptyByDefault() {
        let prefs = HarnessAuthorPreferences(defaults: defaults)
        XCTAssertEqual(prefs.defaultDirectory, "")
    }

    func test_authorPreferences_defaultDirectory_persists() {
        let first = HarnessAuthorPreferences(defaults: defaults)
        first.defaultDirectory = "/tmp/harnesses"

        let second = HarnessAuthorPreferences(defaults: defaults)
        XCTAssertEqual(second.defaultDirectory, "/tmp/harnesses")
    }

    func test_authorPreferences_resetToEmpty_persists() {
        let prefs = HarnessAuthorPreferences(defaults: defaults)
        prefs.defaultDirectory = "/tmp/harnesses"
        prefs.defaultDirectory = ""

        let reload = HarnessAuthorPreferences(defaults: defaults)
        XCTAssertEqual(reload.defaultDirectory, "")
    }

    // MARK: - SidebarState

    func test_sidebarState_selectedTab_defaultsToRepositories() {
        let state = SidebarState(defaults: defaults)
        XCTAssertEqual(state.selectedTab, .repositories)
    }

    func test_sidebarState_selectedTab_persists() {
        let first = SidebarState(defaults: defaults)
        first.selectedTab = .marketplaces

        let second = SidebarState(defaults: defaults)
        XCTAssertEqual(second.selectedTab, .marketplaces)
    }

    func test_sidebarState_unknownStoredValue_fallsBackToRepositories() {
        defaults.set("not-a-real-tab", forKey: "sidebar.selectedTab")
        let state = SidebarState(defaults: defaults)
        XCTAssertEqual(state.selectedTab, .repositories)
    }

    // MARK: - GitConfigStore

    func test_gitConfig_protectedBranches_emptyByDefault() {
        let store = GitConfigStore(defaults: defaults)
        XCTAssertEqual(store.globalProtectedBranches, "")
    }

    func test_gitConfig_protectedBranches_persists() {
        let first = GitConfigStore(defaults: defaults)
        first.globalProtectedBranches = "main,develop"

        let second = GitConfigStore(defaults: defaults)
        XCTAssertEqual(second.globalProtectedBranches, "main,develop")
    }

    // MARK: - Helpers

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStorageOwnerTests-\(UUID().uuidString).json")
    }
}
