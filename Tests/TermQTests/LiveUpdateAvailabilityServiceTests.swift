import Foundation
import TermQShared
import XCTest

@testable import TermQ

@MainActor
final class LiveUpdateAvailabilityServiceTests: XCTestCase {

    // MARK: - refreshAll

    func testRefreshAll_populatesCacheWithFreshState() async {
        let json = Self.listJSON(harnesses: [
            Self.harnessFixture(name: "a", versionInstalled: "0.1.0", versionAvailable: "0.2.0"),
            Self.harnessFixture(name: "b", versionInstalled: "0.1.0", versionAvailable: "0.1.0"),
        ])
        let service = LiveUpdateAvailabilityService(
            listFetcher: { Data(json.utf8) },
            infoFetcher: { _ in Data() },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        await service.refreshAll()

        XCTAssertEqual(service.state(forHarness: "a"), .fresh(at: Date(timeIntervalSince1970: 1_000)))
        XCTAssertEqual(service.snapshot(forHarness: "a")?.versionAvailable, "0.2.0")
        XCTAssertEqual(service.snapshot(forHarness: "a")?.hasVersionUpdate, true)

        XCTAssertEqual(service.state(forHarness: "b"), .fresh(at: Date(timeIntervalSince1970: 1_000)))
        XCTAssertEqual(service.snapshot(forHarness: "b")?.hasVersionUpdate, false)
    }

    func testRefreshAll_dropsHarnessesNotInResponse() async {
        let serviceWithSeed = LiveUpdateAvailabilityService(
            listFetcher: { Data(Self.listJSON(harnesses: [Self.harnessFixture(name: "a")]).utf8) },
            infoFetcher: { _ in Data() }
        )
        await serviceWithSeed.refreshAll()
        XCTAssertNotNil(serviceWithSeed.snapshot(forHarness: "a"))

        // Subsequent probe returns no harnesses — uninstalled out from under us.
        let dropping = LiveUpdateAvailabilityService(
            listFetcher: { Data(Self.listJSON(harnesses: []).utf8) },
            infoFetcher: { _ in Data() }
        )
        await dropping.refreshAll()
        XCTAssertNil(dropping.snapshot(forHarness: "a"))
        XCTAssertEqual(dropping.state(forHarness: "a"), .idle)
    }

    func testRefreshAll_failureSetsErrorOnExistingEntries() async {
        nonisolated(unsafe) var firstCall = true
        let service = LiveUpdateAvailabilityService(
            listFetcher: {
                if firstCall {
                    firstCall = false
                    return Data(Self.listJSON(harnesses: [Self.harnessFixture(name: "a")]).utf8)
                }
                throw TestFetchError.boom
            },
            infoFetcher: { _ in Data() }
        )

        await service.refreshAll()
        if case .fresh = service.state(forHarness: "a") {
            // expected
        } else {
            XCTFail("first refresh should succeed, got \(service.state(forHarness: "a"))")
        }

        await service.refreshAll()
        if case .error(let reason) = service.state(forHarness: "a") {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("expected error state, got \(service.state(forHarness: "a"))")
        }
        // Snapshot is preserved across the failure so the UI doesn't blank out.
        XCTAssertNotNil(service.snapshot(forHarness: "a"))
    }

    // MARK: - invalidate

    func testInvalidate_marksStaleAndPreservesSnapshot() async {
        let service = LiveUpdateAvailabilityService(
            listFetcher: { Data(Self.listJSON(harnesses: [Self.harnessFixture(name: "a")]).utf8) },
            infoFetcher: { _ in Data() }
        )
        await service.refreshAll()
        XCTAssertNotNil(service.snapshot(forHarness: "a"))

        service.invalidate(harness: "a")
        XCTAssertEqual(service.state(forHarness: "a"), .stale)
        XCTAssertNotNil(service.snapshot(forHarness: "a"), "snapshot survives invalidate")
    }

    // MARK: - refresh(harness:)

    func testRefreshHarness_setsFreshStateAfterSuccess() async {
        let infoJSON = Self.infoJSON(name: "a", versionInstalled: "0.1.0")
        let service = LiveUpdateAvailabilityService(
            listFetcher: { Data() },
            infoFetcher: { name in
                XCTAssertEqual(name, "a")
                return Data(infoJSON.utf8)
            },
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        await service.refresh(harness: "a")

        XCTAssertEqual(service.state(forHarness: "a"), .fresh(at: Date(timeIntervalSince1970: 2_000)))
    }

    func testRefreshHarness_passesCanonicalIdDirectlyToYnhInfo() async {
        let infoJSON = Self.infoJSON(name: "leaf", versionInstalled: "0.1.0")
        nonisolated(unsafe) var seenName: String?
        let service = LiveUpdateAvailabilityService(
            listFetcher: { Data() },
            infoFetcher: { name in
                seenName = name
                return Data(infoJSON.utf8)
            }
        )

        await service.refresh(harness: "ns/repo/leaf")

        XCTAssertEqual(seenName, "ns/repo/leaf", "ynh info requires the canonical id")
    }

    // MARK: - State for unknown harness

    func testState_forUnknownHarness_isIdle() {
        let service = LiveUpdateAvailabilityService(
            listFetcher: { Data() }, infoFetcher: { _ in Data() })
        XCTAssertEqual(service.state(forHarness: "never-seen"), .idle)
        XCTAssertNil(service.snapshot(forHarness: "never-seen"))
    }

    // MARK: - Helpers

    private enum TestFetchError: Error { case boom }

    private nonisolated static func listJSON(harnesses: [String]) -> String {
        """
        {
          "capabilities": "0.3.0",
          "ynh_version": "0.3.0",
          "harnesses": [\(harnesses.joined(separator: ","))]
        }
        """
    }

    private nonisolated static func harnessFixture(
        name: String,
        versionInstalled: String = "0.1.0",
        versionAvailable: String? = nil
    ) -> String {
        let versionAvailableLine: String
        if let versionAvailable {
            versionAvailableLine = "\"version_available\": \"\(versionAvailable)\","
        } else {
            versionAvailableLine = ""
        }
        return """
            {
              "name": "\(name)",
              "version_installed": "\(versionInstalled)",
              \(versionAvailableLine)
              "default_vendor": "claude",
              "path": "/p/\(name)",
              "is_pinned": false,
              "artifacts": { "skills": 0, "agents": 0, "rules": 0, "commands": 0 },
              "includes": [],
              "delegates_to": []
            }
            """
    }

    private nonisolated static func infoJSON(name: String, versionInstalled: String) -> String {
        """
        {
          "capabilities": "0.3.0",
          "ynh_version": "0.3.0",
          "harness": {
            "name": "\(name)",
            "version_installed": "\(versionInstalled)",
            "default_vendor": "claude",
            "path": "/p/\(name)",
            "is_pinned": false
          }
        }
        """
    }
}
