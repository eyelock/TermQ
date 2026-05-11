import Foundation
import TermQShared
import XCTest

@testable import TermQ

final class HarnessSourceBadgeViewModelTests: XCTestCase {

    // MARK: - Source classification

    func testClassify_nilProvenance_isLocal() {
        XCTAssertEqual(HarnessSourceBadgeViewModel.classify(nil), .local)
    }

    func testClassify_localProvenanceWithoutFork_isLocal() throws {
        let json = """
            {
                "source_type": "local",
                "source": "/path/to/harness",
                "installed_at": "2026-01-01T00:00:00Z"
            }
            """
        let provenance = try JSONDecoder().decode(
            HarnessProvenance.self, from: Data(json.utf8))
        XCTAssertEqual(HarnessSourceBadgeViewModel.classify(provenance), .local)
    }

    func testClassify_git_isGit() throws {
        let json = """
            {
                "source_type": "git",
                "source": "git@github.com:user/repo",
                "installed_at": "2026-01-01T00:00:00Z"
            }
            """
        let provenance = try JSONDecoder().decode(
            HarnessProvenance.self, from: Data(json.utf8))
        XCTAssertEqual(HarnessSourceBadgeViewModel.classify(provenance), .git)
    }

    func testClassify_registry_carriesRegistryName() throws {
        let json = """
            {
                "source_type": "registry",
                "source": "github.com/eyelock/assistants",
                "registry_name": "eyelock-assistants",
                "installed_at": "2026-01-01T00:00:00Z"
            }
            """
        let provenance = try JSONDecoder().decode(
            HarnessProvenance.self, from: Data(json.utf8))
        XCTAssertEqual(
            HarnessSourceBadgeViewModel.classify(provenance),
            .registry(name: "eyelock-assistants"))
    }

    func testClassify_registryWithoutName_isStillRegistry() throws {
        let json = """
            {
                "source_type": "registry",
                "source": "github.com/eyelock/assistants",
                "installed_at": "2026-01-01T00:00:00Z"
            }
            """
        let provenance = try JSONDecoder().decode(
            HarnessProvenance.self, from: Data(json.utf8))
        XCTAssertEqual(
            HarnessSourceBadgeViewModel.classify(provenance),
            .registry(name: nil))
    }

    func testClassify_localWithForkedFrom_isForked() throws {
        let json = """
            {
                "source_type": "local",
                "source": "/path/to/fork",
                "installed_at": "2026-01-01T00:00:00Z",
                "forked_from": {
                    "source_type": "registry",
                    "source": "github.com/eyelock/assistants",
                    "registry_name": "eyelock",
                    "version": "0.1.0",
                    "sha": "abc123"
                }
            }
            """
        let provenance = try JSONDecoder().decode(
            HarnessProvenance.self, from: Data(json.utf8))
        let classified = HarnessSourceBadgeViewModel.classify(provenance)
        guard case .forked(let origin) = classified else {
            return XCTFail("expected .forked, got \(classified)")
        }
        XCTAssertEqual(origin.sourceType, "registry")
        XCTAssertEqual(origin.registryName, "eyelock")
        XCTAssertEqual(origin.version, "0.1.0")
        XCTAssertEqual(origin.sha, "abc123")
    }

    func testClassify_unknownSourceType_fallsBackToLocal() throws {
        let json = """
            {
                "source_type": "future-source",
                "source": "wherever",
                "installed_at": "2026-01-01T00:00:00Z"
            }
            """
        let provenance = try JSONDecoder().decode(
            HarnessProvenance.self, from: Data(json.utf8))
        XCTAssertEqual(HarnessSourceBadgeViewModel.classify(provenance), .local)
    }

    // MARK: - View model construction

    func testInit_fromHarness_picksUpSourceAndIcon() {
        let harness = Harness(
            name: "h",
            version: "0.1.0",
            defaultVendor: "claude",
            path: "/p",
            installedFrom: nil,
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
        let vm = HarnessSourceBadgeViewModel(harness: harness)
        XCTAssertEqual(vm.source, .local)
        XCTAssertFalse(vm.iconSystemName.isEmpty)
    }

    func testIcons_areDistinctPerSource() {
        // The detail header shows the icon next to the source label, so
        // distinct sources must render with distinct symbols.
        let icons: Set<String> = [
            HarnessSourceBadgeViewModel(harness: Self.harness(provenance: nil)).iconSystemName,
            HarnessSourceBadgeViewModel(harness: Self.harness(sourceType: "git")).iconSystemName,
            HarnessSourceBadgeViewModel(harness: Self.harness(sourceType: "registry")).iconSystemName,
            HarnessSourceBadgeViewModel(harness: Self.harness(sourceType: "local", forkedSourceType: "registry"))
                .iconSystemName,
        ]
        XCTAssertEqual(icons.count, 4, "each source should have its own icon")
    }

    // MARK: - Helpers

    private static func harness(
        provenance: HarnessProvenance? = nil,
        sourceType: String? = nil,
        forkedSourceType: String? = nil
    ) -> Harness {
        let resolved: HarnessProvenance?
        if let provenance {
            resolved = provenance
        } else if let sourceType {
            let fork = forkedSourceType.map {
                ForkOrigin(
                    sourceType: $0, source: "x", registryName: nil, version: nil, sha: nil)
            }
            resolved = HarnessProvenance(
                sourceType: sourceType,
                source: "x",
                path: nil,
                registryName: nil,
                installedAt: "2026-01-01T00:00:00Z",
                ref: nil,
                sha: nil,
                namespace: nil,
                forkedFrom: fork
            )
        } else {
            resolved = nil
        }
        return Harness(
            name: "h",
            version: "0.1.0",
            defaultVendor: "claude",
            path: "/p",
            installedFrom: resolved,
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
    }
}
