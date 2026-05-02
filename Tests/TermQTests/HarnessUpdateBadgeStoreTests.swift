import Foundation
import TermQShared
import XCTest

@testable import TermQ

// MARK: - Stub service

/// Stub that lets each test control exactly what state and snapshot is returned.
@MainActor
private final class StubUpdateAvailabilityService: UpdateAvailabilityService {
    var stateByHarness: [String: UpdateCheckState] = [:]
    var snapshotByHarness: [String: Harness] = [:]
    let isProbingAll = false

    func state(forHarness id: String) -> UpdateCheckState {
        stateByHarness[id] ?? .idle
    }

    func state(forInclude git: String, inHarness id: String) -> UpdateCheckState { .idle }

    func snapshot(forHarness id: String) -> Harness? {
        snapshotByHarness[id]
    }

    func refresh(harness id: String) async {}
    func refreshAll() async {}
    func invalidate(harness id: String) {}
}

// MARK: - Tests

@MainActor
final class HarnessUpdateBadgeStoreTests: XCTestCase {

    private func makeHarness(
        name: String,
        version: String = "1.0.0",
        versionAvailable: String? = nil,
        includes: [HarnessInclude] = [],
        installedSHA: String? = nil,
        installedRef: String? = nil,
        shaAvailable: String? = nil
    ) -> Harness {
        let provenance: HarnessProvenance? =
            (installedSHA != nil || installedRef != nil)
            ? HarnessProvenance(
                sourceType: "registry",
                source: "github.com/test/repo",
                path: nil,
                registryName: nil,
                installedAt: "2026-01-01T00:00:00Z",
                ref: installedRef,
                sha: installedSHA,
                namespace: nil,
                forkedFrom: nil
            )
            : nil
        return Harness(
            name: name,
            version: version,
            versionAvailable: versionAvailable,
            defaultVendor: "claude",
            path: "/tmp/\(name)",
            installedFrom: provenance,
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0),
            includes: includes,
            shaAvailable: shaAvailable
        )
    }

    private func makeInclude(ref: String?, refAvailable: String?) -> HarnessInclude {
        // The badge store now keys off `ref_installed` (the resolved SHA from
        // YNH 0.3.0+'s `installed.json.resolved`), so existing test cases that
        // pass `ref:` here populate `ref_installed` in the JSON to keep their
        // intent — the badge logic should respond to the installed SHA, not
        // the manifest pin.
        var json = #"{"git":"git@github.com:org/repo","is_pinned":false"#
        if let ref { json += #","ref_installed":"\#(ref)""# }
        if let refAvailable { json += #","ref_available":"\#(refAvailable)""# }
        json += "}"
        return try! JSONDecoder().decode(HarnessInclude.self, from: Data(json.utf8))
    }

    // MARK: - hasUpdate

    func testNoSnapshot_hasUpdateIsFalse() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "a")
        XCTAssertFalse(store.hasUpdate(for: harness))
    }

    func testSnapshotWithVersionUpdate_hasUpdateIsTrue() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "a")
        let snapshot = makeHarness(name: "a", version: "1.0.0", versionAvailable: "1.1.0")
        stub.snapshotByHarness[harness.id] = snapshot
        XCTAssertTrue(store.hasUpdate(for: harness))
    }

    func testSnapshotUpToDate_hasUpdateIsFalse() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "a")
        let snapshot = makeHarness(name: "a", version: "1.0.0", versionAvailable: "1.0.0")
        stub.snapshotByHarness[harness.id] = snapshot
        XCTAssertFalse(store.hasUpdate(for: harness))
    }

    func testIncludeWithNewerRef_hasUpdateIsTrue() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "a")
        let staleInclude = makeInclude(ref: "abc123", refAvailable: "def456")
        let snapshot = makeHarness(name: "a", includes: [staleInclude])
        stub.snapshotByHarness[harness.id] = snapshot
        XCTAssertTrue(store.hasUpdate(for: harness))
    }

    func testIncludeWithSameRef_hasUpdateIsFalse() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "a")
        let currentInclude = makeInclude(ref: "abc123", refAvailable: "abc123")
        let snapshot = makeHarness(name: "a", includes: [currentInclude])
        stub.snapshotByHarness[harness.id] = snapshot
        XCTAssertFalse(store.hasUpdate(for: harness))
    }

    func testIncludeWithNilRefAvailable_hasUpdateIsFalse() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "a")
        let include = makeInclude(ref: "abc123", refAvailable: nil)
        let snapshot = makeHarness(name: "a", includes: [include])
        stub.snapshotByHarness[harness.id] = snapshot
        XCTAssertFalse(store.hasUpdate(for: harness))
    }

    /// Regression: when YNH reports `ref_available` but no `ref` (the data shape
    /// some YNH builds emit), the include must NOT be reported as updatable —
    /// we cannot prove staleness without both sides of the comparison.
    func testIncludeWithNilRef_hasUpdateIsFalse() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "a")
        let include = makeInclude(ref: nil, refAvailable: "def456")
        let snapshot = makeHarness(name: "a", includes: [include])
        stub.snapshotByHarness[harness.id] = snapshot
        XCTAssertFalse(store.hasUpdate(for: harness))
    }

    // MARK: - signal classification

    func testSignal_noSnapshot_isNone() {
        let store = HarnessUpdateBadgeStore(service: StubUpdateAvailabilityService())
        XCTAssertEqual(store.signal(for: makeHarness(name: "a")), .none)
    }

    func testSignal_versionBump_isVersioned() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "a")
        let snapshot = makeHarness(name: "a", version: "1.0.0", versionAvailable: "1.1.0")
        stub.snapshotByHarness[harness.id] = snapshot
        guard case .versioned(let v) = store.signal(for: harness) else {
            return XCTFail("expected versioned signal")
        }
        XCTAssertEqual(v, "1.1.0")
    }

    /// Critical security signal: when an include's SHA drifts but `version`
    /// has NOT been bumped, classify as `unversionedDrift` so the UI can
    /// surface a warning treatment rather than the trusted "update available"
    /// affordance. Plain version-bump-driven updates take precedence — they
    /// classify as `versioned` even if includes also drifted.
    func testSignal_includeDriftWithoutVersionBump_isUnversionedDrift() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "a")
        let staleInclude = makeInclude(ref: "abc1234", refAvailable: "def5678")
        let snapshot = makeHarness(
            name: "a", version: "1.0.0", versionAvailable: "1.0.0", includes: [staleInclude])
        stub.snapshotByHarness[harness.id] = snapshot
        guard case .unversionedDrift(let drifted) = store.signal(for: harness) else {
            return XCTFail("expected unversionedDrift signal")
        }
        XCTAssertEqual(drifted.count, 1)
        XCTAssertEqual(drifted.first?.installedSHA, "abc1234")
        XCTAssertEqual(drifted.first?.availableSHA, "def5678")
    }

    /// Self-contained plugin case: harness has no includes but the harness's
    /// own source SHA differs from upstream. Must surface as
    /// `unversionedDrift` so users get a warning even when the plugin has
    /// nothing to detect via include-level probes.
    func testSignal_harnessSourceDriftWithoutVersionBump_isUnversionedDrift() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "selfcontained")
        let snapshot = makeHarness(
            name: "selfcontained",
            version: "1.0.0",
            versionAvailable: "1.0.0",
            installedSHA: "aaaa1111",
            installedRef: "main",
            shaAvailable: "bbbb2222"
        )
        stub.snapshotByHarness[harness.id] = snapshot
        guard case .unversionedDrift(let drifted) = store.signal(for: harness) else {
            return XCTFail("expected unversionedDrift signal for self-contained harness drift")
        }
        XCTAssertEqual(drifted.count, 1)
        XCTAssertEqual(drifted.first?.path, "selfcontained")
        XCTAssertEqual(drifted.first?.installedSHA, "aaaa1111")
        XCTAssertEqual(drifted.first?.availableSHA, "bbbb2222")
    }

    func testSignal_harnessSourceMatch_isNone() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "selfcontained")
        let snapshot = makeHarness(
            name: "selfcontained",
            installedSHA: "aaaa1111",
            installedRef: "main",
            shaAvailable: "aaaa1111"
        )
        stub.snapshotByHarness[harness.id] = snapshot
        XCTAssertEqual(store.signal(for: harness), .none)
    }

    func testSignal_versionBumpTakesPrecedenceOverIncludeDrift() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "a")
        let staleInclude = makeInclude(ref: "abc1234", refAvailable: "def5678")
        let snapshot = makeHarness(
            name: "a", version: "1.0.0", versionAvailable: "1.1.0", includes: [staleInclude])
        stub.snapshotByHarness[harness.id] = snapshot
        guard case .versioned = store.signal(for: harness) else {
            return XCTFail("version bump should take precedence")
        }
    }

    // MARK: - state delegation

    func testState_delegatesToService() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "b")
        stub.stateByHarness[harness.id] = .loading
        XCTAssertEqual(store.state(for: harness), .loading)
    }

    func testState_unknownHarness_returnsIdle() {
        let stub = StubUpdateAvailabilityService()
        let store = HarnessUpdateBadgeStore(service: stub)
        let harness = makeHarness(name: "never-seen")
        XCTAssertEqual(store.state(for: harness), .idle)
    }
}
