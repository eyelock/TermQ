import XCTest

@testable import TermQ

/// The Settings sidebar shows everything there is to configure: every group
/// of settings lands in exactly one section.
@MainActor
final class SettingsSectionsTests: XCTestCase {
    func testEveryGeneralGroupIsInExactlyOneSection() {
        for part in SettingsGeneralView.Part.allCases {
            let sections = SettingsView.SettingsTab.allCases.filter { $0.generalParts.contains(part) }
            XCTAssertEqual(sections.count, 1, "\(part)")
        }
    }

    func testEveryToolsGroupIsInExactlyOneSection() {
        for part in ToolsTabContent.Part.allCases {
            let sections = SettingsView.SettingsTab.allCases.filter { $0.toolsParts.contains(part) }
            XCTAssertEqual(sections.count, 1, "\(part)")
        }
    }

    func testSectionsAreInTheAgreedOrder() {
        XCTAssertEqual(
            SettingsView.SettingsTab.allCases,
            [
                .general, .terminal, .environment, .gitAndStacks, .integrations, .harnesses, .wheelhouses,
                .marketplaces, .dataAndSecurity,
            ])
    }

    func testEverySectionHasASymbolAndATitle() {
        for tab in SettingsView.SettingsTab.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: tab.icon, accessibilityDescription: nil), tab.icon)
            XCTAssertFalse(tab.title.isEmpty)
        }
    }

    /// Repository Settings and Harness Tools open these sections.
    func testDeepLinkedSectionsHoldWhatTheirMenuItemsPromise() {
        XCTAssertTrue(SettingsView.SettingsTab.gitAndStacks.generalParts.contains(.git))
        XCTAssertTrue(SettingsView.SettingsTab.gitAndStacks.toolsParts.contains(.gh))
        XCTAssertEqual(SettingsView.SettingsTab.harnesses.toolsParts, [.ynh])
    }

    func testOwnViewSectionsTakeNoSharedGroups() {
        for tab in [SettingsView.SettingsTab.environment, .wheelhouses, .marketplaces, .dataAndSecurity] {
            XCTAssertTrue(tab.generalParts.isEmpty, "\(tab)")
            XCTAssertTrue(tab.toolsParts.isEmpty, "\(tab)")
        }
    }
}
