import Foundation
import TermQShared
import XCTest

@testable import TermQ

// MARK: - MockYNHDetector

/// Test double for `YNHDetectorProtocol`.
///
/// Allows tests to inject a controlled `status` and `ynhHomeOverride` without
/// running the real subprocess detection.
@MainActor
final class MockYNHDetector: YNHDetectorProtocol {
    var status: YNHStatus
    var ynhHomeOverride: String?

    init(status: YNHStatus = .missing, ynhHomeOverride: String? = nil) {
        self.status = status
        self.ynhHomeOverride = ynhHomeOverride
    }
}

// MARK: - Helpers

private func makePaths() -> YNHPaths {
    YNHPaths(
        home: "/tmp/ynh-home",
        config: "/tmp/ynh-home/config",
        harnesses: "/tmp/ynh-home/harnesses",
        symlinks: "/tmp/ynh-home/symlinks",
        cache: "/tmp/ynh-home/cache",
        run: "/tmp/ynh-home/run",
        bin: "/tmp/ynh-home/bin"
    )
}

// MARK: - HarnessRepository refresh() tests

@MainActor
final class HarnessRepositoryRefreshTests: XCTestCase {

    func test_refresh_whenStatusIsMissing_clearsHarnesses() async {
        let detector = MockYNHDetector(status: .missing)
        let repo = HarnessRepository(ynhDetector: detector)
        await repo.refresh()
        XCTAssertTrue(repo.harnesses.isEmpty)
    }

    func test_refresh_whenStatusIsMissing_clearsSelectedHarnessName() async {
        let detector = MockYNHDetector(status: .missing)
        let repo = HarnessRepository(ynhDetector: detector)
        repo.selectedHarnessId = "my-harness"
        await repo.refresh()
        XCTAssertNil(repo.selectedHarnessId)
    }

    func test_refresh_whenStatusIsBinaryOnly_clearsHarnesses() async {
        let detector = MockYNHDetector(status: .binaryOnly(ynhPath: "/usr/local/bin/ynh"))
        let repo = HarnessRepository(ynhDetector: detector)
        await repo.refresh()
        XCTAssertTrue(repo.harnesses.isEmpty)
    }

    func test_refresh_whenStatusIsBinaryOnly_clearsSelectedHarnessName() async {
        let detector = MockYNHDetector(status: .binaryOnly(ynhPath: "/usr/local/bin/ynh"))
        let repo = HarnessRepository(ynhDetector: detector)
        repo.selectedHarnessId = "some-harness"
        await repo.refresh()
        XCTAssertNil(repo.selectedHarnessId)
    }

    func test_refresh_whenNotReady_doesNotSetLoadingTrue() async {
        // When the guard fires early, isLoading must not be left true
        let detector = MockYNHDetector(status: .missing)
        let repo = HarnessRepository(ynhDetector: detector)
        await repo.refresh()
        XCTAssertFalse(repo.isLoading)
    }
}

// MARK: - HarnessRepository fetchDetail() tests

@MainActor
final class HarnessRepositoryFetchDetailTests: XCTestCase {

    func test_fetchDetail_whenStatusIsMissing_setsToolchainNotReadyError() async {
        let detector = MockYNHDetector(status: .missing)
        let repo = HarnessRepository(ynhDetector: detector)
        await repo.fetchDetail(for: "my-harness")
        XCTAssertEqual(repo.detailError, "YNH toolchain not ready")
    }

    func test_fetchDetail_whenStatusIsBinaryOnly_setsToolchainNotReadyError() async {
        let detector = MockYNHDetector(status: .binaryOnly(ynhPath: "/usr/local/bin/ynh"))
        let repo = HarnessRepository(ynhDetector: detector)
        await repo.fetchDetail(for: "my-harness")
        XCTAssertEqual(repo.detailError, "YNH toolchain not ready")
    }

    func test_fetchDetail_whenNotReady_selectedDetailRemainsNil() async {
        let detector = MockYNHDetector(status: .missing)
        let repo = HarnessRepository(ynhDetector: detector)
        await repo.fetchDetail(for: "my-harness")
        XCTAssertNil(repo.selectedDetail)
    }

    func test_fetchDetail_whenNotReady_doesNotSetLoadingTrue() async {
        let detector = MockYNHDetector(status: .missing)
        let repo = HarnessRepository(ynhDetector: detector)
        await repo.fetchDetail(for: "my-harness")
        XCTAssertFalse(repo.isLoadingDetail)
    }
}

// MARK: - HarnessRepository ynhEnvironment / ynhHomeOverride tests

@MainActor
final class HarnessRepositoryEnvironmentTests: XCTestCase {

    /// When the detector reports `.missing` after previously being `.ready`,
    /// a subsequent refresh must respect the new status and clear state.
    func test_refresh_readsStatusFromDetectorEachCall() async {
        let detector = MockYNHDetector(status: .binaryOnly(ynhPath: "/usr/local/bin/ynh"))
        let repo = HarnessRepository(ynhDetector: detector)

        // First refresh: binaryOnly → harnesses cleared
        await repo.refresh()
        XCTAssertTrue(repo.harnesses.isEmpty)

        // Switch to missing
        detector.status = .missing
        repo.selectedHarnessId = "stale"
        await repo.refresh()

        // Should still clear state with the updated status
        XCTAssertTrue(repo.harnesses.isEmpty)
        XCTAssertNil(repo.selectedHarnessId)
    }

    /// fetchDetail must read status from the injected detector on each call.
    func test_fetchDetail_readsStatusFromDetectorEachCall() async {
        let detector = MockYNHDetector(status: .binaryOnly(ynhPath: "/usr/local/bin/ynh"))
        let repo = HarnessRepository(ynhDetector: detector)

        await repo.fetchDetail(for: "h1")
        XCTAssertEqual(repo.detailError, "YNH toolchain not ready")

        // Flip to missing — error should still be set on next call
        detector.status = .missing
        await repo.fetchDetail(for: "h2")
        XCTAssertEqual(repo.detailError, "YNH toolchain not ready")
    }
}

// MARK: - HarnessRepository invalidation tests

@MainActor
final class HarnessRepositoryInvalidationTests: XCTestCase {

    func test_invalidateDetail_clearsSelectedDetailForMatchingName() {
        let detector = MockYNHDetector(status: .missing)
        let repo = HarnessRepository(ynhDetector: detector)
        repo.selectedHarnessId = "target"
        repo.invalidateDetail(for: "target")
        XCTAssertNil(repo.selectedDetail)
    }

    func test_invalidateAllDetails_clearsSelectedDetail() {
        let detector = MockYNHDetector(status: .missing)
        let repo = HarnessRepository(ynhDetector: detector)
        repo.invalidateAllDetails()
        XCTAssertNil(repo.selectedDetail)
    }
}

// MARK: - ynhErrorMessage

final class YNHErrorMessageTests: XCTestCase {

    func test_emptyStderr_returnsNil() {
        XCTAssertNil(ynhErrorMessage(from: ""))
    }

    func test_whitespaceOnlyStderr_returnsNil() {
        XCTAssertNil(ynhErrorMessage(from: "   \n  "))
    }

    func test_jsonWithMessage_returnsMessage() {
        let json = #"{"error":{"code":"NOT_FOUND","message":"harness not found"}}"#
        XCTAssertEqual(ynhErrorMessage(from: json), "harness not found")
    }

    func test_jsonWithCodeOnly_returnsCode() {
        let json = #"{"error":{"code":"NOT_FOUND"}}"#
        XCTAssertEqual(ynhErrorMessage(from: json), "NOT_FOUND")
    }

    func test_jsonWithEmptyMessageFallsBackToCode() {
        let json = #"{"error":{"code":"ERR","message":""}}"#
        XCTAssertEqual(ynhErrorMessage(from: json), "ERR")
    }

    func test_plainTextStderr_returnsRawString() {
        XCTAssertEqual(
            ynhErrorMessage(from: "error: unknown flag --check-updates"), "error: unknown flag --check-updates")
    }

    func test_trailingNewlineIsTrimmed() {
        XCTAssertEqual(ynhErrorMessage(from: "something went wrong\n"), "something went wrong")
    }
}

// MARK: - Strings.Harnesses.uninstallBaseMessage

@MainActor
final class HarnessUninstallMessageTests: XCTestCase {

    private func makeHarness(sourceType: String?) -> Harness {
        let installedFrom: HarnessProvenance? = sourceType.map { type in
            try! JSONDecoder().decode(
                HarnessProvenance.self,
                from: """
                    {"source_type":"\(type)","source":"/tmp/h","path":null,"registry_name":null,"installed_at":"2026-01-01"}
                    """.data(using: .utf8)!
            )
        }
        return Harness(
            name: "h", version: "1", defaultVendor: "claude", path: "/tmp/h",
            installedFrom: installedFrom,
            artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0)
        )
    }

    func test_untrackedHarness_usesUntrackedMessage() {
        let harness = makeHarness(sourceType: nil)
        XCTAssertEqual(
            Strings.Harnesses.uninstallBaseMessage(for: harness),
            Strings.Harnesses.uninstallAlertMessageUntracked
        )
    }

    func test_localInstalledHarness_usesLocalMessage() {
        let harness = makeHarness(sourceType: "local")
        XCTAssertEqual(
            Strings.Harnesses.uninstallBaseMessage(for: harness),
            Strings.Harnesses.uninstallAlertMessageLocal
        )
    }

    func test_registryHarness_usesGenericMessage() {
        let harness = makeHarness(sourceType: "registry")
        XCTAssertEqual(
            Strings.Harnesses.uninstallBaseMessage(for: harness),
            Strings.Harnesses.uninstallAlertMessage
        )
    }

    func test_gitHarness_usesGenericMessage() {
        let harness = makeHarness(sourceType: "git")
        XCTAssertEqual(
            Strings.Harnesses.uninstallBaseMessage(for: harness),
            Strings.Harnesses.uninstallAlertMessage
        )
    }
}
