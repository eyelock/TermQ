import XCTest
@testable import MCPServerLib

final class ServerTests: XCTestCase {
    func testServerInitialization() {
        // Test that server can be created with default data directory
        let server = TermQMCPServer()
        XCTAssertNotNil(server)
    }

    func testServerName() {
        XCTAssertEqual(TermQMCPServer.serverName, "termq")
    }

    func testServerVersion() {
        XCTAssertEqual(TermQMCPServer.serverVersion, "1.0.0")
    }
}
