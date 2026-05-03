import Foundation
import XCTest

@testable import TermQ

// MARK: - MockYNHPersistence

/// In-memory test double for `YNHPersistenceProtocol`.
///
/// Stores harness assignments in dictionaries — no file I/O, no Application
/// Support directory access. Safe to construct and mutate freely in tests.
@MainActor
final class MockYNHPersistence: YNHPersistenceProtocol {
    var worktreeHarness: [String: String] = [:]
    var repoHarness: [String: String] = [:]
    var harnessVendor: [String: String] = [:]

    func harness(for worktreePath: String) -> String? {
        worktreeHarness[worktreePath]
    }

    func repoDefaultHarness(for repoPath: String) -> String? {
        repoHarness[repoPath]
    }

    func worktrees(forHarnessId harnessId: String) -> [String] {
        worktreeHarness
            .compactMap { $0.value == harnessId ? $0.key : nil }
            .sorted()
    }

    func vendorOverride(for harnessId: String) -> String? {
        harnessVendor[harnessId]
    }

    func setRepoDefaultHarness(_ harnessName: String?, for repoPath: String) {
        if let name = harnessName {
            repoHarness[repoPath] = name
        } else {
            repoHarness.removeValue(forKey: repoPath)
        }
    }

    func setHarness(_ harnessName: String?, for worktreePath: String) {
        if let name = harnessName {
            worktreeHarness[worktreePath] = name
        } else {
            worktreeHarness.removeValue(forKey: worktreePath)
        }
    }

    func setVendorOverride(_ vendorId: String?, for harnessId: String) {
        if let vendorId, !vendorId.isEmpty {
            harnessVendor[harnessId] = vendorId
        } else {
            harnessVendor.removeValue(forKey: harnessId)
        }
    }

    func removeAllAssociations(for harnessName: String) {
        let worktreePaths = worktreeHarness.compactMap { $0.value == harnessName ? $0.key : nil }
        for path in worktreePaths { worktreeHarness.removeValue(forKey: path) }
        let repoPaths = repoHarness.compactMap { $0.value == harnessName ? $0.key : nil }
        for path in repoPaths { repoHarness.removeValue(forKey: path) }
        let vendorKeys = harnessVendor.keys.filter { id in
            id == harnessName || id.hasSuffix("/\(harnessName)")
        }
        for key in vendorKeys { harnessVendor.removeValue(forKey: key) }
    }
}

// MARK: - MockYNHPersistence query tests

@MainActor
final class MockYNHPersistenceQueryTests: XCTestCase {

    func test_harness_returnsNilWhenNotSet() {
        let mock = MockYNHPersistence()
        XCTAssertNil(mock.harness(for: "/repo/a"))
    }

    func test_harness_returnsValueAfterSetHarness() {
        let mock = MockYNHPersistence()
        mock.setHarness("claude", for: "/repo/a")
        XCTAssertEqual(mock.harness(for: "/repo/a"), "claude")
    }

    func test_harness_returnsNilAfterClear() {
        let mock = MockYNHPersistence()
        mock.setHarness("claude", for: "/repo/a")
        mock.setHarness(nil, for: "/repo/a")
        XCTAssertNil(mock.harness(for: "/repo/a"))
    }

    func test_repoDefaultHarness_returnsNilWhenNotSet() {
        let mock = MockYNHPersistence()
        XCTAssertNil(mock.repoDefaultHarness(for: "/repos/myproject"))
    }

    func test_repoDefaultHarness_returnsValueAfterSetRepoDefaultHarness() {
        let mock = MockYNHPersistence()
        mock.setRepoDefaultHarness("gpt4", for: "/repos/myproject")
        XCTAssertEqual(mock.repoDefaultHarness(for: "/repos/myproject"), "gpt4")
    }

    func test_repoDefaultHarness_returnsNilAfterClear() {
        let mock = MockYNHPersistence()
        mock.setRepoDefaultHarness("gpt4", for: "/repos/myproject")
        mock.setRepoDefaultHarness(nil, for: "/repos/myproject")
        XCTAssertNil(mock.repoDefaultHarness(for: "/repos/myproject"))
    }

    func test_worktrees_returnsEmptyWhenNoneLinked() {
        let mock = MockYNHPersistence()
        XCTAssertTrue(mock.worktrees(forHarnessId: "claude").isEmpty)
    }

    func test_worktrees_returnsOnlyMatchingPaths() {
        let mock = MockYNHPersistence()
        mock.setHarness("claude", for: "/repo/a")
        mock.setHarness("gpt4", for: "/repo/b")
        mock.setHarness("claude", for: "/repo/c")
        let result = mock.worktrees(forHarnessId: "claude")
        XCTAssertEqual(result, ["/repo/a", "/repo/c"])
    }

    func test_worktrees_isSorted() {
        let mock = MockYNHPersistence()
        mock.setHarness("claude", for: "/repo/z")
        mock.setHarness("claude", for: "/repo/a")
        mock.setHarness("claude", for: "/repo/m")
        XCTAssertEqual(mock.worktrees(forHarnessId: "claude"), ["/repo/a", "/repo/m", "/repo/z"])
    }
}

// MARK: - MockYNHPersistence mutation tests

@MainActor
final class MockYNHPersistenceMutationTests: XCTestCase {

    func test_removeAllAssociations_removesAllWorktreeLinks() {
        let mock = MockYNHPersistence()
        mock.setHarness("claude", for: "/repo/a")
        mock.setHarness("claude", for: "/repo/b")
        mock.setHarness("gpt4", for: "/repo/c")
        mock.removeAllAssociations(for: "claude")
        XCTAssertNil(mock.harness(for: "/repo/a"))
        XCTAssertNil(mock.harness(for: "/repo/b"))
        XCTAssertEqual(mock.harness(for: "/repo/c"), "gpt4")
    }

    func test_removeAllAssociations_removesRepoDefaults() {
        let mock = MockYNHPersistence()
        mock.setRepoDefaultHarness("claude", for: "/repos/proj1")
        mock.setRepoDefaultHarness("claude", for: "/repos/proj2")
        mock.setRepoDefaultHarness("gpt4", for: "/repos/proj3")
        mock.removeAllAssociations(for: "claude")
        XCTAssertNil(mock.repoDefaultHarness(for: "/repos/proj1"))
        XCTAssertNil(mock.repoDefaultHarness(for: "/repos/proj2"))
        XCTAssertEqual(mock.repoDefaultHarness(for: "/repos/proj3"), "gpt4")
    }

    func test_removeAllAssociations_noopWhenNothingLinked() {
        let mock = MockYNHPersistence()
        mock.removeAllAssociations(for: "unknown-harness")
        XCTAssertTrue(mock.worktreeHarness.isEmpty)
        XCTAssertTrue(mock.repoHarness.isEmpty)
    }

    func test_setHarness_overwritesPreviousValue() {
        let mock = MockYNHPersistence()
        mock.setHarness("claude", for: "/repo/a")
        mock.setHarness("gpt4", for: "/repo/a")
        XCTAssertEqual(mock.harness(for: "/repo/a"), "gpt4")
    }

    func test_setRepoDefaultHarness_overwritesPreviousValue() {
        let mock = MockYNHPersistence()
        mock.setRepoDefaultHarness("claude", for: "/repos/proj")
        mock.setRepoDefaultHarness("gpt4", for: "/repos/proj")
        XCTAssertEqual(mock.repoDefaultHarness(for: "/repos/proj"), "gpt4")
    }

    // MARK: - Vendor override

    func test_vendorOverride_returnsNilWhenNotSet() {
        let mock = MockYNHPersistence()
        XCTAssertNil(mock.vendorOverride(for: "my-harness"))
    }

    func test_setVendorOverride_storesAndReadsBack() {
        let mock = MockYNHPersistence()
        mock.setVendorOverride("codex", for: "my-harness")
        XCTAssertEqual(mock.vendorOverride(for: "my-harness"), "codex")
    }

    func test_setVendorOverride_nilClearsEntry() {
        let mock = MockYNHPersistence()
        mock.setVendorOverride("codex", for: "my-harness")
        mock.setVendorOverride(nil, for: "my-harness")
        XCTAssertNil(mock.vendorOverride(for: "my-harness"))
    }

    func test_setVendorOverride_emptyStringClearsEntry() {
        let mock = MockYNHPersistence()
        mock.setVendorOverride("codex", for: "my-harness")
        mock.setVendorOverride("", for: "my-harness")
        XCTAssertNil(mock.vendorOverride(for: "my-harness"))
    }

    func test_removeAllAssociations_clearsBareNameVendorOverride() {
        let mock = MockYNHPersistence()
        mock.setVendorOverride("codex", for: "my-harness")
        mock.removeAllAssociations(for: "my-harness")
        XCTAssertNil(mock.vendorOverride(for: "my-harness"))
    }

    func test_removeAllAssociations_clearsNamespaceQualifiedVendorOverride() {
        let mock = MockYNHPersistence()
        mock.setVendorOverride("codex", for: "eyelock/assistants/my-harness")
        mock.removeAllAssociations(for: "my-harness")
        XCTAssertNil(mock.vendorOverride(for: "eyelock/assistants/my-harness"))
    }

    func test_removeAllAssociations_doesNotClearUnrelatedVendorOverride() {
        let mock = MockYNHPersistence()
        mock.setVendorOverride("codex", for: "other-harness")
        mock.removeAllAssociations(for: "my-harness")
        XCTAssertEqual(mock.vendorOverride(for: "other-harness"), "codex")
    }
}

// MARK: - YNHPersistenceProtocol conformance smoke tests

/// These tests verify that the live `YNHPersistence` satisfies the protocol contract.
/// They exercise in-memory state only — no file I/O occurs because they do not call
/// `save` through the filesystem; the init for `YNHPersistence` does read from
/// Application Support, but the queries and mutations operate on the in-memory
/// `config` struct before any save, so the observable behaviour under test here
/// does not depend on or write to `ynh.json`.
@MainActor
final class YNHPersistenceConformanceTests: XCTestCase {

    func test_concreteType_satisfiesProtocol() {
        // Compile-time check: ensure the concrete type can be assigned to the protocol.
        let _: any YNHPersistenceProtocol = YNHPersistence()
    }

    func test_concreteType_harnessRoundtrip() {
        let persistence = YNHPersistence()
        // Use a path unlikely to conflict with real data.
        let path = "/tmp/termq-test-worktree-\(UUID().uuidString)"
        persistence.setHarness("test-harness", for: path)
        XCTAssertEqual(persistence.harness(for: path), "test-harness")
        persistence.setHarness(nil, for: path)
        XCTAssertNil(persistence.harness(for: path))
    }

    func test_concreteType_repoDefaultHarnessRoundtrip() {
        let persistence = YNHPersistence()
        let path = "/tmp/termq-test-repo-\(UUID().uuidString)"
        persistence.setRepoDefaultHarness("repo-harness", for: path)
        XCTAssertEqual(persistence.repoDefaultHarness(for: path), "repo-harness")
        persistence.setRepoDefaultHarness(nil, for: path)
        XCTAssertNil(persistence.repoDefaultHarness(for: path))
    }

    func test_concreteType_removeAllAssociations_clearsLinkedPaths() {
        let persistence = YNHPersistence()
        let path1 = "/tmp/termq-test-wt1-\(UUID().uuidString)"
        let path2 = "/tmp/termq-test-wt2-\(UUID().uuidString)"
        persistence.setHarness("ephemeral", for: path1)
        persistence.setHarness("ephemeral", for: path2)
        persistence.removeAllAssociations(for: "ephemeral")
        XCTAssertNil(persistence.harness(for: path1))
        XCTAssertNil(persistence.harness(for: path2))
    }
}
