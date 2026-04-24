import Foundation
import TermQShared
import XCTest

@testable import TermQ

@MainActor
final class VendorServiceTests: XCTestCase {

    // MARK: - Initial state

    func testInitialState_hasEmptyVendors() {
        let service = VendorService(ynhDetector: MockYNHDetector(status: .missing))
        XCTAssertTrue(service.vendors.isEmpty)
        XCTAssertFalse(service.isLoading)
    }

    // MARK: - refresh() — status gates

    func testRefresh_whenStatusMissing_clearsVendorsAndReturnsEarly() async {
        let service = VendorService(ynhDetector: MockYNHDetector(status: .missing))
        await service.refresh()

        XCTAssertTrue(service.vendors.isEmpty)
        XCTAssertFalse(service.isLoading)
    }

    func testRefresh_whenStatusBinaryOnly_clearsVendorsAndReturnsEarly() async {
        let service = VendorService(
            ynhDetector: MockYNHDetector(status: .binaryOnly(ynhPath: "/usr/local/bin/ynh")))
        await service.refresh()

        XCTAssertTrue(service.vendors.isEmpty)
        XCTAssertFalse(service.isLoading)
    }

    // MARK: - refresh() — ready status with a non-existent binary

    func testRefresh_whenStatusReadyButBinaryMissing_clearsVendors() async {
        // A `.ready` status with a bogus ynhPath will execute the subprocess path,
        // fail to launch, catch the error, and clear `vendors` to empty.
        let paths = YNHPaths(
            home: "/tmp/ynh-home",
            config: "/tmp/ynh-home/config",
            harnesses: "/tmp/ynh-home/harnesses",
            symlinks: "/tmp/ynh-home/symlinks",
            cache: "/tmp/ynh-home/cache",
            run: "/tmp/ynh-home/run",
            bin: "/tmp/ynh-home/bin"
        )
        let bogus = "/does/not/exist/ynh-\(UUID().uuidString)"
        let detector = MockYNHDetector(
            status: .ready(ynhPath: bogus, yndPath: bogus, paths: paths),
            ynhHomeOverride: "/tmp/override"
        )
        let service = VendorService(ynhDetector: detector)

        await service.refresh()

        XCTAssertTrue(service.vendors.isEmpty)
        XCTAssertFalse(service.isLoading)
    }
}
