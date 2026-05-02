import Foundation
import TermQShared
import XCTest

@testable import TermQ

final class HarnessEditabilityResolverTests: XCTestCase {
    private func makeHarness(installedFrom: HarnessProvenance?) -> Harness {
        Harness(
            name: "test",
            version: "1.0.0",
            defaultVendor: "claude",
            path: "/tmp/test",
            installedFrom: installedFrom,
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
    }

    func testNilProvenance_isFullyEditable() {
        XCTAssertEqual(
            HarnessEditabilityResolver.resolve(makeHarness(installedFrom: nil)),
            .fullyEditable)
    }

    func testLocalProvenance_isFullyEditable() {
        let p = HarnessProvenance(
            sourceType: "local", source: "/p", installedAt: "2026-01-01T00:00:00Z")
        XCTAssertEqual(
            HarnessEditabilityResolver.resolve(makeHarness(installedFrom: p)),
            .fullyEditable)
    }

    func testGitProvenance_isFullyEditable() {
        let p = HarnessProvenance(
            sourceType: "git", source: "git@github.com:u/r", installedAt: "2026-01-01T00:00:00Z")
        XCTAssertEqual(
            HarnessEditabilityResolver.resolve(makeHarness(installedFrom: p)),
            .fullyEditable)
    }

    func testRegistryProvenance_isReadOnly_canFork() {
        let p = HarnessProvenance(
            sourceType: "registry",
            source: "github.com/org/repo",
            installedAt: "2026-01-01T00:00:00Z")
        XCTAssertEqual(
            HarnessEditabilityResolver.resolve(makeHarness(installedFrom: p)),
            .readOnly(canFork: true))
    }

    func testForkedProvenance_isFullyEditable() {
        let origin = ForkOrigin(sourceType: "registry", source: "github.com/org/repo")
        let p = HarnessProvenance(
            sourceType: "local",
            source: "/fork",
            installedAt: "2026-01-01T00:00:00Z",
            forkedFrom: origin)
        XCTAssertEqual(
            HarnessEditabilityResolver.resolve(makeHarness(installedFrom: p)),
            .fullyEditable)
    }

    func testUnknownSourceType_isFullyEditable() {
        let p = HarnessProvenance(
            sourceType: "future_type", source: "/p", installedAt: "2026-01-01T00:00:00Z")
        XCTAssertEqual(
            HarnessEditabilityResolver.resolve(makeHarness(installedFrom: p)),
            .fullyEditable)
    }
}
