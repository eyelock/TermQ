import XCTest

@testable import TermQShared

final class AppProfileTests: XCTestCase {
    /// Verify production identifiers match expected values
    func testProductionIdentifiers() {
        XCTAssertEqual(AppProfile.Production.bundleIdentifier, "net.eyelock.termq.app")
        XCTAssertEqual(AppProfile.Production.cliBinaryName, "termqcli")
        XCTAssertEqual(AppProfile.Production.mcpBinaryName, "termqmcp")
        XCTAssertEqual(AppProfile.Production.appBundleName, "TermQ.app")
        XCTAssertEqual(AppProfile.Production.dataDirectoryName, "TermQ")
        XCTAssertEqual(AppProfile.Production.urlScheme, "termq")
        XCTAssertEqual(AppProfile.Production.displayName, "TermQ")
    }

    /// Verify debug identifiers match expected values
    func testDebugIdentifiers() {
        XCTAssertEqual(AppProfile.Debug.bundleIdentifier, "net.eyelock.termq.app.debug")
        XCTAssertEqual(AppProfile.Debug.cliBinaryName, "termqclid")
        XCTAssertEqual(AppProfile.Debug.mcpBinaryName, "termqmcpd")
        XCTAssertEqual(AppProfile.Debug.appBundleName, "TermQDebug.app")
        XCTAssertEqual(AppProfile.Debug.dataDirectoryName, "TermQ-Debug")
        XCTAssertEqual(AppProfile.Debug.urlScheme, "termq-debug")
        XCTAssertEqual(AppProfile.Debug.displayName, "TermQ Debug")
    }

    /// Verify allBundleIdentifiers contains no duplicates
    func testAllBundleIdentifiersUnique() {
        let ids = AppProfile.allBundleIdentifiers
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate bundle IDs found in allBundleIdentifiers")
    }

    /// Verify allBundleIdentifiers contains production, debug, and legacy IDs
    func testAllBundleIdentifiersComplete() {
        let ids = AppProfile.allBundleIdentifiers
        XCTAssertTrue(ids.contains(AppProfile.Production.bundleIdentifier))
        XCTAssertTrue(ids.contains(AppProfile.Debug.bundleIdentifier))
        XCTAssertTrue(ids.contains(AppProfile.Legacy.oldBundleIdentifier))
    }

    /// Verify Current enum resolves to production or debug based on build flags
    func testCurrentResolves() {
        #if TERMQ_DEBUG_BUILD
            XCTAssertEqual(AppProfile.Current.bundleIdentifier, AppProfile.Debug.bundleIdentifier)
            XCTAssertEqual(AppProfile.Current.urlScheme, AppProfile.Debug.urlScheme)
            XCTAssertEqual(AppProfile.Current.dataDirectoryName, AppProfile.Debug.dataDirectoryName)
        #else
            XCTAssertEqual(AppProfile.Current.bundleIdentifier, AppProfile.Production.bundleIdentifier)
            XCTAssertEqual(AppProfile.Current.urlScheme, AppProfile.Production.urlScheme)
            XCTAssertEqual(AppProfile.Current.dataDirectoryName, AppProfile.Production.dataDirectoryName)
        #endif
    }

    /// Verify Services constants are set correctly
    func testServicesConstants() {
        XCTAssertEqual(AppProfile.Services.keychainService, "net.eyelock.termq.secrets")
    }

    /// Verify Legacy constants are set correctly
    func testLegacyConstants() {
        XCTAssertEqual(AppProfile.Legacy.oldBundleIdentifier, "com.eyelock.TermQ")
    }
}
