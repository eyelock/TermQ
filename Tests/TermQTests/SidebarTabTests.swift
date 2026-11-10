import Foundation
import XCTest

@testable import TermQ

/// The sidebar tabs' ⌃⌘ shortcuts: their keys, when each tab is available,
/// and what picking one does.
@MainActor
final class SidebarTabTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "SidebarTabTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_shortcutKeys_areDistinctFirstLetters() {
        let keys = SidebarTab.allCases.map(\.shortcutKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        for tab in SidebarTab.allCases {
            XCTAssertEqual(tab.shortcutKey, Character(tab.label.prefix(1).lowercased()))
        }
    }

    func test_repositories_isAlwaysAvailable() {
        XCTAssertTrue(
            SidebarTab.repositories.isAvailable(
                harnessTabEnabled: false, ynhMissing: true, wheelhouseTabEnabled: false))
    }

    func test_harnessesAndMarketplaces_needTheTabOnAndYnh() {
        for tab in [SidebarTab.harnesses, .marketplaces] {
            XCTAssertTrue(tab.isAvailable(harnessTabEnabled: true, ynhMissing: false, wheelhouseTabEnabled: false))
            XCTAssertFalse(tab.isAvailable(harnessTabEnabled: true, ynhMissing: true, wheelhouseTabEnabled: true))
            XCTAssertFalse(tab.isAvailable(harnessTabEnabled: false, ynhMissing: false, wheelhouseTabEnabled: true))
        }
    }

    func test_wheelhouses_followsItsOwnSetting() {
        XCTAssertTrue(
            SidebarTab.wheelhouses.isAvailable(harnessTabEnabled: false, ynhMissing: true, wheelhouseTabEnabled: true))
        XCTAssertFalse(
            SidebarTab.wheelhouses.isAvailable(harnessTabEnabled: true, ynhMissing: false, wheelhouseTabEnabled: false))
    }

    func test_activatingAnotherTab_leavesWheelhouseFocusMode() {
        let sidebar = SidebarState(defaults: defaults)
        let stage = WheelhouseStage(defaults: defaults)
        stage.focusMode = true
        SidebarTabCommands.activate(.repositories, sidebar: sidebar, stage: stage)
        XCTAssertFalse(stage.focusMode)
        XCTAssertEqual(sidebar.selectedTab, .repositories)
    }

    func test_activatingWheelhouses_keepsFocusMode() {
        let sidebar = SidebarState(defaults: defaults)
        let stage = WheelhouseStage(defaults: defaults)
        stage.focusMode = true
        SidebarTabCommands.activate(.wheelhouses, sidebar: sidebar, stage: stage)
        XCTAssertTrue(stage.focusMode)
        XCTAssertEqual(sidebar.selectedTab, .wheelhouses)
    }
}
