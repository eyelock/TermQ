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

    // MARK: - ensureLoaded()

    private func readyService(runner: StubCommandRunner) -> VendorService {
        let paths = YNHPaths(
            home: "/tmp/ynh-home",
            config: "/tmp/ynh-home/config",
            harnesses: "/tmp/ynh-home/harnesses",
            symlinks: "/tmp/ynh-home/symlinks",
            cache: "/tmp/ynh-home/cache",
            run: "/tmp/ynh-home/run",
            bin: "/tmp/ynh-home/bin"
        )
        let detector = MockYNHDetector(status: .ready(ynhPath: "/stub/ynh", yndPath: "/stub/ynd", paths: paths))
        return VendorService(ynhDetector: detector, commandRunner: runner)
    }

    private let vendorsJSON = """
        [{"name":"claude","display_name":"Claude Code","cli":"claude","config_dir":".claude",
          "available":true,"supports_initial_prompt":true,"supports_resume":true},
         {"name":"cursor","display_name":"Cursor","cli":"cursor","config_dir":".cursor",
          "available":true,"supports_initial_prompt":true}]
        """

    func testEnsureLoaded_loadsOnceAndSharesTheFirstLoad() async {
        let runner = StubCommandRunner()
        runner.outcomes["vendors"] = .stdout(vendorsJSON)
        let service = readyService(runner: runner)

        async let first: Void = service.ensureLoaded()
        async let second: Void = service.ensureLoaded()
        _ = await (first, second)
        await service.ensureLoaded()

        XCTAssertEqual(runner.capturedInvocations.count, 1)
        XCTAssertEqual(service.vendors.map(\.vendorID), ["claude", "cursor"])
        XCTAssertEqual(service.resumableVendorIDs, ["claude"])
    }

    func testEnsureLoaded_whenYNHIsMissing_completesWithoutVendors() async {
        let service = VendorService(ynhDetector: MockYNHDetector(status: .missing))

        await service.ensureLoaded()

        XCTAssertTrue(service.vendors.isEmpty)
        XCTAssertTrue(service.hasLoaded)
    }

    /// An explicit refresh still re-runs `ynh vendors` after the first load.
    func testRefresh_afterEnsureLoaded_runsAgain() async {
        let runner = StubCommandRunner()
        runner.outcomes["vendors"] = .stdout(vendorsJSON)
        let service = readyService(runner: runner)

        await service.ensureLoaded()
        await service.refresh()

        XCTAssertEqual(runner.capturedInvocations.count, 2)
    }
}
