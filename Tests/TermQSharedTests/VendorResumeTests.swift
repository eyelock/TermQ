import XCTest

@testable import TermQShared

/// `supports_resume` is a safety gate, not a nicety: a YNH that predates
/// `--resume` forwards unrecognised flags straight to the vendor CLI, where a
/// bare `--resume` opens an interactive session picker and hangs the pane.
/// Such a binary simply omits the field, so absent must decode to false.
final class VendorResumeTests: XCTestCase {

    private func decode(_ json: String) throws -> Vendor {
        try JSONDecoder().decode(Vendor.self, from: Data(json.utf8))
    }

    func test_supportsResume_decodesTrue() throws {
        let vendor = try decode(
            """
            {"name":"claude","display_name":"Claude Code","cli":"claude",
             "config_dir":".claude","available":true,
             "supports_initial_prompt":true,"supports_resume":true}
            """)

        XCTAssertTrue(vendor.supportsResume)
    }

    func test_supportsResume_decodesFalse() throws {
        let vendor = try decode(
            """
            {"name":"cursor","display_name":"Cursor","cli":"agent",
             "config_dir":".cursor","available":true,
             "supports_initial_prompt":true,"supports_resume":false}
            """)

        XCTAssertFalse(vendor.supportsResume)
    }

    /// The output shape of a YNH released before this feature.
    func test_supportsResume_absentFieldDecodesToFalse() throws {
        let vendor = try decode(
            """
            {"name":"claude","display_name":"Claude Code","cli":"claude",
             "config_dir":".claude","available":true,
             "supports_initial_prompt":true}
            """)

        XCTAssertFalse(vendor.supportsResume)
        XCTAssertTrue(vendor.supportsInitialPrompt, "unrelated fields must still decode")
    }
}
