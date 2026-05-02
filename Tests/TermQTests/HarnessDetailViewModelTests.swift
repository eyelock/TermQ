import Foundation
import TermQShared
import XCTest

@testable import TermQ

@MainActor
final class HarnessDetailViewModelTests: XCTestCase {
    func testSourceBadge_derivedFromHarnessProvenance() {
        let provenance = HarnessProvenance(
            sourceType: "registry",
            source: "github.com/eyelock/assistants",
            registryName: "eyelock",
            installedAt: "2026-01-01T00:00:00Z"
        )
        let harness = Harness(
            name: "h",
            version: "0.1.0",
            defaultVendor: "claude",
            path: "/p",
            installedFrom: provenance,
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        let vm = HarnessDetailViewModel(
            harness: harness,
            detail: nil,
            isLoadingDetail: false,
            detailError: nil,
            updateAvailability: UnknownUpdateAvailabilityService(),
            capabilities: nil
        )
        XCTAssertEqual(vm.sourceBadge.source, .registry(name: "eyelock"))
    }

    func testHarnessUpdateState_delegatesToService() {
        let harness = Harness(
            name: "h",
            version: "0.1.0",
            defaultVendor: "claude",
            path: "/p",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        let vm = HarnessDetailViewModel(
            harness: harness,
            detail: nil,
            isLoadingDetail: false,
            detailError: nil,
            updateAvailability: UnknownUpdateAvailabilityService(),
            capabilities: nil
        )
        // Stub always returns .idle for any harness id.
        XCTAssertEqual(vm.harnessUpdateState, .idle)
    }

    func testUpdateSnapshot_nilWhenIdle() {
        let harness = Harness(
            name: "h", version: "0.1.0", defaultVendor: "claude", path: "/p",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        let vm = HarnessDetailViewModel(
            harness: harness, detail: nil, isLoadingDetail: false, detailError: nil,
            updateAvailability: UnknownUpdateAvailabilityService(), capabilities: nil
        )
        XCTAssertNil(vm.updateSnapshot)
    }

    func testUpdateSnapshot_nonNilWhenFresh() {
        let harness = Harness(
            name: "h", version: "0.1.0", defaultVendor: "claude", path: "/p",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        let stub = StubUpdateService(
            stateForHarness: .fresh(at: Date()),
            snapshotForHarness: harness
        )
        let vm = HarnessDetailViewModel(
            harness: harness, detail: nil, isLoadingDetail: false, detailError: nil,
            updateAvailability: stub, capabilities: nil
        )
        XCTAssertNotNil(vm.updateSnapshot)
    }

    func testPhase1Capable_falseWhenCapabilitiesNil() {
        let harness = Harness(
            name: "h", version: "0.1.0", defaultVendor: "claude", path: "/p",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        let vm = HarnessDetailViewModel(
            harness: harness, detail: nil, isLoadingDetail: false, detailError: nil,
            updateAvailability: UnknownUpdateAvailabilityService(), capabilities: nil
        )
        XCTAssertFalse(vm.phase1Capable)
    }

    func testPhase1Capable_trueWhenCapabilitiesMeetMinimum() {
        let harness = Harness(
            name: "h", version: "0.1.0", defaultVendor: "claude", path: "/p",
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        let vm = HarnessDetailViewModel(
            harness: harness, detail: nil, isLoadingDetail: false, detailError: nil,
            updateAvailability: UnknownUpdateAvailabilityService(), capabilities: "0.3.0"
        )
        XCTAssertTrue(vm.phase1Capable)
    }
}

// MARK: - Stub

@MainActor
private final class StubUpdateService: UpdateAvailabilityService {
    private let _state: UpdateCheckState
    private let _snapshot: Harness?
    let isProbingAll = false

    init(stateForHarness: UpdateCheckState, snapshotForHarness: Harness?) {
        self._state = stateForHarness
        self._snapshot = snapshotForHarness
    }

    func state(forHarness id: String) -> UpdateCheckState { _state }
    func state(forInclude git: String, inHarness id: String) -> UpdateCheckState { .idle }
    func snapshot(forHarness id: String) -> Harness? { _snapshot }
    func refresh(harness id: String) async {}
    func refreshAll() async {}
    func invalidate(harness id: String) {}
}
