import Foundation
import TermQCore
import TermQShared
import XCTest

@testable import TermQ

/// Exercises the card → harness/worktree/repo resolution ladder and the
/// path-matching that backs the non-live card menu. Pure logic — the resolver
/// is constructed with injected lookups, no live singletons.
@MainActor
final class CardLaunchResolverTests: XCTestCase {

    private let column = UUID()

    private func card(workingDirectory: String, tags: [TermQCore.Tag] = []) -> TerminalCard {
        TerminalCard(tags: tags, columnId: column, workingDirectory: workingDirectory)
    }

    private func repo(
        name: String = "repo", path: String, worktreeBase: String? = nil
    )
        -> ObservableRepository
    {
        ObservableRepository(name: name, path: path, worktreeBasePath: worktreeBase)
    }

    private func worktree(_ path: String, branch: String? = "feat/x") -> GitWorktree {
        GitWorktree(
            path: path, branch: branch, commitHash: "abc12345",
            isMainWorktree: false, isLocked: false)
    }

    // MARK: - Ladder ordering

    func test_bakedHarnessTag_winsLadder() {
        let c = card(
            workingDirectory: "/r/wt",
            tags: [TermQCore.Tag(key: "source", value: "harness"), TermQCore.Tag(key: "harness", value: "baked/h")])
        let r = repo(path: "/r")
        let resolver = CardLaunchResolver(
            repositories: [r],
            worktrees: [r.id: [worktree("/r/wt")]],
            worktreeHarness: { _ in "wt/h" },  // would win at rung 2…
            repoDefaultHarness: { _ in "repo/h" })  // …but the baked tag wins.

        let opts = resolver.resolve(c)

        XCTAssertEqual(opts.effectiveHarnessId, "baked/h")
        XCTAssertTrue(opts.hasBakedHarness)
        XCTAssertFalse(opts.showsLaunchItem, "baked-harness cards relaunch via plain Open")
        XCTAssertTrue(opts.canLaunchHarness)
    }

    func test_worktreeMatch_usesWorktreeHarness() {
        let c = card(workingDirectory: "/r/wt")
        let r = repo(path: "/r")
        let wt = worktree("/r/wt", branch: "feat/y")
        let resolver = CardLaunchResolver(
            repositories: [r],
            worktrees: [r.id: [wt]],
            worktreeHarness: { $0 == "/r/wt" ? "wt/h" : nil },
            repoDefaultHarness: { _ in "repo/h" })

        let opts = resolver.resolve(c)

        XCTAssertEqual(opts.effectiveHarnessId, "wt/h")
        XCTAssertEqual(opts.worktree?.path, "/r/wt")
        XCTAssertEqual(opts.repo?.id, r.id)
        XCTAssertFalse(opts.hasBakedHarness)
        XCTAssertTrue(opts.showsLaunchItem)
        XCTAssertEqual(opts.branch, "feat/y", "branch falls back to the matched worktree")
    }

    func test_repoContainment_usesRepoDefault_noWorktree() {
        let c = card(workingDirectory: "/r/sub/dir")
        let r = repo(path: "/r")
        let resolver = CardLaunchResolver(
            repositories: [r],
            worktrees: [r.id: [worktree("/r/other")]],
            repoDefaultHarness: { $0 == "/r" ? "repo/h" : nil })

        let opts = resolver.resolve(c)

        XCTAssertEqual(opts.effectiveHarnessId, "repo/h")
        XCTAssertNil(opts.worktree)
        XCTAssertEqual(opts.repo?.id, r.id)
        XCTAssertTrue(opts.showsLaunchItem)
    }

    func test_worktreeBasePathContainment_matchesRepo() {
        let c = card(workingDirectory: "/base/wts/feature")
        let r = repo(path: "/r", worktreeBase: "/base/wts")
        let resolver = CardLaunchResolver(
            repositories: [r],
            worktrees: [:],
            repoDefaultHarness: { _ in "repo/h" })

        let opts = resolver.resolve(c)

        XCTAssertEqual(opts.repo?.id, r.id)
        XCTAssertNil(opts.worktree)
        XCTAssertEqual(opts.effectiveHarnessId, "repo/h")
    }

    func test_noMatch_plainOnly() {
        let c = card(workingDirectory: "/elsewhere/tmp")
        let r = repo(path: "/r")
        let resolver = CardLaunchResolver(
            repositories: [r],
            worktrees: [r.id: [worktree("/r/wt")]],
            // Path-keyed override applies only to the real worktree path, as in
            // production (YNHPersistence.harness(for:) is a path-keyed lookup).
            worktreeHarness: { $0 == "/r/wt" ? "wt/h" : nil },
            repoDefaultHarness: { $0 == "/r" ? "repo/h" : nil })

        let opts = resolver.resolve(c)

        XCTAssertNil(opts.effectiveHarnessId)
        XCTAssertNil(opts.repo)
        XCTAssertNil(opts.worktree)
        XCTAssertFalse(opts.canLaunchHarness)
        XCTAssertFalse(opts.showsLaunchItem)
        XCTAssertNil(opts.repoPath)
    }

    // MARK: - Derived fields

    func test_branchTag_preferredOverWorktreeBranch() {
        let c = card(
            workingDirectory: "/r/wt",
            tags: [TermQCore.Tag(key: "branch", value: "feat/from-tag")])
        let r = repo(path: "/r")
        let resolver = CardLaunchResolver(
            repositories: [r],
            worktrees: [r.id: [worktree("/r/wt", branch: "feat/from-worktree")]])

        XCTAssertEqual(resolver.resolve(c).branch, "feat/from-tag")
    }

    func test_focusesAndName_passThrough() {
        let c = card(workingDirectory: "/r/wt", tags: [TermQCore.Tag(key: "harness", value: "h/id")])
        let r = repo(path: "/r")
        let resolver = CardLaunchResolver(
            repositories: [r],
            worktrees: [r.id: [worktree("/r/wt")]],
            focusesForHarness: { $0 == "h/id" ? ["bugfix", "review"] : [] })

        let opts = resolver.resolve(c)

        XCTAssertEqual(opts.focuses, ["bugfix", "review"])
        XCTAssertEqual(opts.effectiveHarnessName, "h/id", "name falls back to id when lookup is empty")
        XCTAssertEqual(opts.repoPath, "/r")
    }

    func test_exactWorktreeMatch_doesNotFalseMatchSiblingPrefix() {
        // "/r/wt" must not match a card at "/r/wt-2" via prefix logic.
        let c = card(workingDirectory: "/r/wt-2")
        let r = repo(path: "/r")
        let resolver = CardLaunchResolver(
            repositories: [r],
            worktrees: [r.id: [worktree("/r/wt")]],
            repoDefaultHarness: { _ in "repo/h" })

        let opts = resolver.resolve(c)

        XCTAssertNil(opts.worktree, "sibling path must not match the /r/wt worktree")
        XCTAssertEqual(opts.repo?.id, r.id, "still owned by /r via repo containment")
    }
}
