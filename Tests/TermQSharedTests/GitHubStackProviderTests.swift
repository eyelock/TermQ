import Foundation
import XCTest

@testable import TermQShared

/// Tests the pure mapping from gh-stack's on-disk tracking file to the neutral model,
/// against fixture data. Deliberately does not require `gh` or the gh-stack extension —
/// neither is installed on CI, and that must remain the ship-safe case.
final class GitHubStackProviderVersionTests: XCTestCase {
    func testIdentify_ghStackVersionOutput() {
        XCTAssertEqual(
            GitHubStackProvider.identifyGhStack(versionOutput: "gh stack version 1.4.2\n"), "1.4.2")
    }

    func testIdentify_hyphenatedName() {
        XCTAssertEqual(
            GitHubStackProvider.identifyGhStack(versionOutput: "gh-stack 0.9.0"), "0.9.0")
    }

    func testIdentify_unrelatedBinary_returnsNil() {
        // `gh` itself, or anything else that answers --version, must not be mistaken for
        // the extension.
        XCTAssertNil(GitHubStackProvider.identifyGhStack(versionOutput: "gh version 2.96.0"))
        XCTAssertNil(GitHubStackProvider.identifyGhStack(versionOutput: "GPL Ghostscript 10.03.1"))
    }

    func testIdentify_namedButNoVersionNumber_returnsUnknown() {
        XCTAssertEqual(GitHubStackProvider.identifyGhStack(versionOutput: "gh stack"), "unknown")
    }
}

// MARK: - Tracking file decoding

final class GitHubStackTrackingFileTests: XCTestCase {
    /// Shape mirrors `internal/stack/stack.go`. Note `base` holds a SHA.
    private let validFile = """
        {
          "schemaVersion": 1,
          "repository": "eyelock/TermQ",
          "stacks": [
            {
              "id": "S_123",
              "number": 7,
              "trunk": { "branch": "develop", "head": "aaa111" },
              "branches": [
                { "branch": "feat-auth", "head": "bbb222", "base": "aaa111",
                  "pullRequest": { "number": 101, "url": "https://github.com/o/r/pull/101" } },
                { "branch": "feat-api", "head": "ccc333", "base": "bbb222",
                  "pullRequest": { "number": 102, "url": "https://github.com/o/r/pull/102",
                                   "merged": true } },
                { "branch": "feat-ui", "head": "ddd444", "base": "ccc333" }
              ]
            }
          ]
        }
        """

    func testDecode_validFile() throws {
        let file = try GitHubStackProvider.decodeTrackingFile(Data(validFile.utf8))
        XCTAssertEqual(file.schemaVersion, 1)
        XCTAssertEqual(file.stacks.count, 1)
        XCTAssertEqual(file.stacks[0].number, 7)
        XCTAssertEqual(file.stacks[0].trunk.branch, "develop")
        XCTAssertEqual(file.stacks[0].branches.map(\.branch), ["feat-auth", "feat-api", "feat-ui"])
    }

    func testDecode_missingSchemaVersion_treatedAsV1() throws {
        let json = """
            {"stacks":[{"trunk":{"branch":"main"},"branches":[{"branch":"a"}]}]}
            """
        let file = try GitHubStackProvider.decodeTrackingFile(Data(json.utf8))
        XCTAssertEqual(file.schemaVersion, 1)
        XCTAssertEqual(file.stacks.count, 1)
    }

    func testDecode_newerSchema_refuses() {
        // Misreading a future layout would produce a confidently wrong graph. gh-stack
        // refuses in the same situation; so do we.
        let json = """
            {"schemaVersion": 99, "stacks": []}
            """
        XCTAssertThrowsError(try GitHubStackProvider.decodeTrackingFile(Data(json.utf8))) { error in
            guard case StackProviderError.decodingFailed(let detail) = error else {
                return XCTFail("expected .decodingFailed, got \(error)")
            }
            XCTAssertTrue(detail.contains("99"))
        }
    }

    func testDecode_garbage_throws() {
        XCTAssertThrowsError(try GitHubStackProvider.decodeTrackingFile(Data("not json".utf8)))
    }

    func testDecode_unknownFields_areIgnored() throws {
        // Another tool's file: a new field must not blank the sidebar.
        let json = """
            {"schemaVersion":1,"repository":"o/r","somethingNew":{"a":1},
             "stacks":[{"trunk":{"branch":"main","head":"x"},
                        "branches":[{"branch":"a","futureField":true}]}]}
            """
        let file = try GitHubStackProvider.decodeTrackingFile(Data(json.utf8))
        XCTAssertEqual(file.stacks[0].branches.map(\.branch), ["a"])
    }

    func testDecode_emptyStacks_isValid() throws {
        let file = try GitHubStackProvider.decodeTrackingFile(
            Data(#"{"schemaVersion":1,"stacks":[]}"#.utf8))
        XCTAssertTrue(file.stacks.isEmpty)
    }
}

// MARK: - Branch mapping

final class GitHubStackBranchMappingTests: XCTestCase {
    private func stack(
        trunk: String = "develop", branches: [String], number: Int? = 1
    ) throws -> GhStackDTO {
        let branchJSON = branches.map { name in
            // A `base` SHA is present on every entry on purpose — see the parent test.
            #"{"branch":"\#(name)","head":"sha-\#(name)","base":"0123456789abcdef"}"#
        }.joined(separator: ",")
        let numberJSON = number.map { "\"number\":\($0)," } ?? ""
        let json = """
            {\(numberJSON)"trunk":{"branch":"\(trunk)"},"branches":[\(branchJSON)]}
            """
        return try JSONDecoder().decode(GhStackDTO.self, from: Data(json.utf8))
    }

    func testParent_comesFromOrder_notFromTheBaseField() throws {
        // The trap this locks down: `base` is the parent's HEAD SHA, not a branch name,
        // in both the tracking file and `gh stack view --json`. Using it as the parent
        // yields a graph that looks plausible and is wrong.
        let branches = GitHubStackProvider.branches(
            from: [try stack(branches: ["feat-auth", "feat-api", "feat-ui"])],
            currentBranch: nil, checkouts: [])

        let byName = Dictionary(uniqueKeysWithValues: branches.map { ($0.name, $0) })
        XCTAssertEqual(byName["feat-auth"]?.parent, "develop")
        XCTAssertEqual(byName["feat-api"]?.parent, "feat-auth")
        XCTAssertEqual(byName["feat-ui"]?.parent, "feat-api")
        for branch in branches {
            XCTAssertNotEqual(
                branch.parent, "0123456789abcdef", "a SHA must never be used as a parent name")
        }
    }

    func testChildren_pointUpTheStack() throws {
        let branches = GitHubStackProvider.branches(
            from: [try stack(branches: ["a", "b", "c"])], currentBranch: nil, checkouts: [])
        let byName = Dictionary(uniqueKeysWithValues: branches.map { ($0.name, $0) })
        XCTAssertEqual(byName["a"]?.children, ["b"])
        XCTAssertEqual(byName["b"]?.children, ["c"])
        XCTAssertEqual(byName["c"]?.children, [])
    }

    func testTrunk_isSynthesizedAsAParentlessEntry() throws {
        // StackGraph.isTrunk/rootBranch/stackRoots all define the trunk as "tracked and
        // parentless" (how git-spice reports it). gh-stack keeps it as a sibling field,
        // so it must be synthesized or those helpers quietly misbehave.
        let branches = GitHubStackProvider.branches(
            from: [try stack(branches: ["a", "b"])], currentBranch: nil, checkouts: [])
        let graph = StackGraph(branches: branches)

        XCTAssertTrue(graph.isTrunk("develop"))
        XCTAssertNil(graph.branch(named: "develop")?.parent)
        XCTAssertEqual(graph.stackRoots.map(\.name), ["a"])
        XCTAssertEqual(graph.chain(containing: "b").map(\.name), ["a", "b"])
        XCTAssertTrue(graph.isStacked("b"))
    }

    func testTrunk_children_listTheStackBottoms() throws {
        let branches = GitHubStackProvider.branches(
            from: [
                try stack(branches: ["a"], number: 1),
                try stack(branches: ["x"], number: 2),
            ], currentBranch: nil, checkouts: [])
        let trunk = branches.first { $0.name == "develop" }
        XCTAssertEqual(trunk?.children.sorted(), ["a", "x"])
    }

    func testTrunk_notSynthesizedWhenAlreadyAStackMember() throws {
        // Defensive: a real branch must never be shadowed by the synthetic trunk entry.
        let branches = GitHubStackProvider.branches(
            from: [try stack(trunk: "develop", branches: ["develop", "a"])],
            currentBranch: nil, checkouts: [])
        XCTAssertEqual(branches.filter { $0.name == "develop" }.count, 1)
    }

    func testIsCurrent_tracksTheMainWorktreesBranch() throws {
        let branches = GitHubStackProvider.branches(
            from: [try stack(branches: ["a", "b"])], currentBranch: "b", checkouts: [])
        let byName = Dictionary(uniqueKeysWithValues: branches.map { ($0.name, $0) })
        XCTAssertTrue(byName["b"]?.isCurrent ?? false)
        XCTAssertFalse(byName["a"]?.isCurrent ?? true)
    }

    func testCheckedOutElsewhere_derivedFromWorktreeList() throws {
        // gh-stack has no worktree awareness at all, so this has to come from git.
        let checkouts = [
            GitHubStackProvider.WorktreeCheckout(path: "/repo", branch: "develop", isMain: true),
            GitHubStackProvider.WorktreeCheckout(path: "/wt/feat-b", branch: "b", isMain: false),
        ]
        let branches = GitHubStackProvider.branches(
            from: [try stack(branches: ["a", "b"])], currentBranch: "develop", checkouts: checkouts)
        let byName = Dictionary(uniqueKeysWithValues: branches.map { ($0.name, $0) })
        XCTAssertEqual(byName["b"]?.checkedOutElsewhere, "/wt/feat-b")
        XCTAssertNil(byName["a"]?.checkedOutElsewhere)
    }

    func testCheckedOutElsewhere_ignoresTheMainWorktree() throws {
        let checkouts = [
            GitHubStackProvider.WorktreeCheckout(path: "/repo", branch: "a", isMain: true)
        ]
        let branches = GitHubStackProvider.branches(
            from: [try stack(branches: ["a"])], currentBranch: "a", checkouts: checkouts)
        XCTAssertNil(branches.first { $0.name == "a" }?.checkedOutElsewhere)
    }

    func testChangeRequest_mapsNumberUrlAndMergedState() throws {
        let json = """
            {"trunk":{"branch":"develop"},"branches":[
              {"branch":"a","pullRequest":{"number":101,"url":"https://x/1"}},
              {"branch":"b","pullRequest":{"number":102,"url":"https://x/2","merged":true}},
              {"branch":"c"}
            ]}
            """
        let dto = try JSONDecoder().decode(GhStackDTO.self, from: Data(json.utf8))
        let branches = GitHubStackProvider.branches(
            from: [dto], currentBranch: nil, checkouts: [])
        let byName = Dictionary(uniqueKeysWithValues: branches.map { ($0.name, $0) })

        XCTAssertEqual(byName["a"]?.changeRequest?.id, "101")
        XCTAssertEqual(byName["a"]?.changeRequest?.status, .open)
        XCTAssertEqual(byName["b"]?.changeRequest?.status, .merged)
        XCTAssertEqual(byName["b"]?.changeRequest?.url, "https://x/2")
        XCTAssertNil(byName["c"]?.changeRequest)
    }

    func testChangeRequest_commentCountUnavailableFromDisk() throws {
        let json = """
            {"trunk":{"branch":"d"},"branches":[{"branch":"a","pullRequest":{"number":1}}]}
            """
        let dto = try JSONDecoder().decode(GhStackDTO.self, from: Data(json.utf8))
        let branches = GitHubStackProvider.branches(from: [dto], currentBranch: nil, checkouts: [])
        XCTAssertNil(branches.first { $0.name == "a" }?.changeRequest?.commentCount)
    }

    func testIsQueued_alwaysFalseFromDisk() throws {
        // `Queued` is json:"-" in gh-stack — transient, repopulated from the API on each
        // run and never written to the file.
        let branches = GitHubStackProvider.branches(
            from: [try stack(branches: ["a", "b"])], currentBranch: nil, checkouts: [])
        XCTAssertTrue(branches.allSatisfy { !$0.isQueued })
    }

    func testPushState_unavailableFromDisk() throws {
        let branches = GitHubStackProvider.branches(
            from: [try stack(branches: ["a"])], currentBranch: nil, checkouts: [])
        XCTAssertNil(branches.first { $0.name == "a" }?.push)
    }

    func testMultipleStacks_shareOneSynthesizedTrunk() throws {
        let branches = GitHubStackProvider.branches(
            from: [
                try stack(branches: ["a", "b"], number: 1),
                try stack(branches: ["x", "y"], number: 2),
            ], currentBranch: nil, checkouts: [])
        let graph = StackGraph(branches: branches)
        XCTAssertEqual(branches.filter { $0.name == "develop" }.count, 1)
        XCTAssertEqual(graph.stackRoots.map(\.name).sorted(), ["a", "x"])
    }

    func testDistinctTrunks_bothSynthesized() throws {
        let branches = GitHubStackProvider.branches(
            from: [
                try stack(trunk: "develop", branches: ["a"], number: 1),
                try stack(trunk: "main", branches: ["x"], number: 2),
            ], currentBranch: nil, checkouts: [])
        let graph = StackGraph(branches: branches)
        XCTAssertTrue(graph.isTrunk("develop"))
        XCTAssertTrue(graph.isTrunk("main"))
    }
}

// MARK: - Union across worktrees

final class GitHubStackDedupeTests: XCTestCase {
    private func stack(number: Int?, trunk: String = "develop", branches: [String]) throws -> GhStackDTO {
        let branchJSON = branches.map { #"{"branch":"\#($0)"}"# }.joined(separator: ",")
        let numberJSON = number.map { "\"number\":\($0)," } ?? ""
        return try JSONDecoder().decode(
            GhStackDTO.self,
            from: Data(
                "{\(numberJSON)\"trunk\":{\"branch\":\"\(trunk)\"},\"branches\":[\(branchJSON)]}".utf8))
    }

    func testDedupe_sameRemoteNumber_collapsesToOne() throws {
        // Two worktrees legitimately referencing the same stack must show up once.
        let stacks = [
            try stack(number: 7, branches: ["a", "b"]),
            try stack(number: 7, branches: ["a", "b"]),
        ]
        XCTAssertEqual(GitHubStackProvider.dedupe(stacks).count, 1)
    }

    func testDedupe_localOnlyStacks_collapsedByChainShape() throws {
        let stacks = [
            try stack(number: nil, branches: ["a", "b"]),
            try stack(number: nil, branches: ["a", "b"]),
        ]
        XCTAssertEqual(GitHubStackProvider.dedupe(stacks).count, 1)
    }

    func testDedupe_differentStacks_bothKept() throws {
        let stacks = [
            try stack(number: nil, branches: ["a", "b"]),
            try stack(number: nil, branches: ["x", "y"]),
        ]
        XCTAssertEqual(GitHubStackProvider.dedupe(stacks).count, 2)
    }

    func testDedupe_sameBranchesDifferentTrunk_bothKept() throws {
        let stacks = [
            try stack(number: nil, trunk: "develop", branches: ["a"]),
            try stack(number: nil, trunk: "main", branches: ["a"]),
        ]
        XCTAssertEqual(GitHubStackProvider.dedupe(stacks).count, 2)
    }

    func testDedupe_preservesOrder() throws {
        let stacks = [
            try stack(number: 1, branches: ["a"]),
            try stack(number: 2, branches: ["b"]),
            try stack(number: 1, branches: ["a"]),
        ]
        XCTAssertEqual(GitHubStackProvider.dedupe(stacks).map(\.number), [1, 2])
    }
}

// MARK: - git worktree list parsing

final class GitHubStackWorktreeListTests: XCTestCase {
    func testParse_mainAndLinkedWorktrees() {
        let output = """
            worktree /Users/d/repo
            HEAD aaa111
            branch refs/heads/develop

            worktree /Users/d/repo/.worktrees/feat-a
            HEAD bbb222
            branch refs/heads/feat-a

            """
        let checkouts = GitHubStackProvider.parseWorktreeList(output)
        XCTAssertEqual(checkouts.count, 2)
        XCTAssertEqual(checkouts[0].path, "/Users/d/repo")
        XCTAssertEqual(checkouts[0].branch, "develop")
        XCTAssertTrue(checkouts[0].isMain, "the first record is always the main worktree")
        XCTAssertEqual(checkouts[1].branch, "feat-a")
        XCTAssertFalse(checkouts[1].isMain)
    }

    func testParse_detachedHead_hasNoBranch() {
        let output = """
            worktree /Users/d/repo
            HEAD aaa111
            detached

            """
        let checkouts = GitHubStackProvider.parseWorktreeList(output)
        XCTAssertEqual(checkouts.count, 1)
        XCTAssertNil(checkouts[0].branch)
    }

    func testParse_stripsRefsHeadsPrefix() {
        let checkouts = GitHubStackProvider.parseWorktreeList(
            "worktree /r\nbranch refs/heads/feature/nested/name\n")
        XCTAssertEqual(checkouts[0].branch, "feature/nested/name")
    }

    func testParse_emptyOutput() {
        XCTAssertTrue(GitHubStackProvider.parseWorktreeList("").isEmpty)
    }

    // MARK: restrict(_:toKnownPaths:)

    private let checkouts = [
        GitHubStackProvider.WorktreeCheckout(path: "/repo", branch: "develop", isMain: true),
        GitHubStackProvider.WorktreeCheckout(path: "/wt/a", branch: "a", isMain: false),
        GitHubStackProvider.WorktreeCheckout(path: "/wt/unknown", branch: "b", isMain: false),
    ]

    func testRestrict_dropsWorktreesTheCallerDoesNotKnowAbout() {
        // checkedOutElsewhere is a jump target: naming a worktree the sidebar has never
        // heard of renders a control that navigates nowhere.
        let result = GitHubStackProvider.restrict(checkouts, toKnownPaths: ["/repo", "/wt/a"])
        XCTAssertEqual(result.map(\.path), ["/repo", "/wt/a"])
    }

    func testRestrict_alwaysKeepsTheMainWorktree() {
        // It supplies isCurrent and is never a jump target, so it survives even when the
        // caller's list omits it.
        let result = GitHubStackProvider.restrict(checkouts, toKnownPaths: ["/wt/a"])
        XCTAssertTrue(result.contains { $0.isMain })
    }

    func testRestrict_emptyKnownPaths_keepsEverything() {
        let result = GitHubStackProvider.restrict(checkouts, toKnownPaths: [])
        XCTAssertEqual(result.count, 3)
    }

    func testRestrict_normalizesPaths() {
        let result = GitHubStackProvider.restrict(checkouts, toKnownPaths: ["/repo", "/wt/./a"])
        XCTAssertEqual(result.map(\.path), ["/repo", "/wt/a"])
    }
}

// MARK: - Tracking file discovery

final class GitHubStackFileDiscoveryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gh-stack-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testGitDirectories_includeCommonDirAndEveryWorktree() throws {
        let common = root.appendingPathComponent(".git")
        let worktrees = common.appendingPathComponent("worktrees")
        try FileManager.default.createDirectory(
            at: worktrees.appendingPathComponent("feat-a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: worktrees.appendingPathComponent("feat-b"), withIntermediateDirectories: true)

        let directories = GitHubStackProvider.gitDirectories(commonDirectory: common.path)
        XCTAssertEqual(directories.count, 3)
        XCTAssertEqual(directories.first, common.path)
        XCTAssertTrue(directories.contains { $0.hasSuffix("/worktrees/feat-a") })
        XCTAssertTrue(directories.contains { $0.hasSuffix("/worktrees/feat-b") })
    }

    func testGitDirectories_noWorktreesSubdir_returnsCommonDirOnly() throws {
        let common = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: common, withIntermediateDirectories: true)
        XCTAssertEqual(GitHubStackProvider.gitDirectories(commonDirectory: common.path), [common.path])
    }

    func testTrackingFilePaths_onlyReturnsExistingFiles() throws {
        let common = root.appendingPathComponent(".git")
        let worktreeDir = common.appendingPathComponent("worktrees/feat-a")
        try FileManager.default.createDirectory(at: worktreeDir, withIntermediateDirectories: true)
        // Tracking file only in the linked worktree — stacking set up inside a worktree
        // and nowhere else is the normal case for TermQ's workflow.
        try Data("{}".utf8).write(to: worktreeDir.appendingPathComponent("gh-stack"))

        let paths = GitHubStackProvider.trackingFilePaths(commonDirectory: common.path)
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths[0].hasSuffix("/worktrees/feat-a/gh-stack"))
    }

    func testTrackingFilePaths_noneFound_isEmpty() throws {
        let common = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: common, withIntermediateDirectories: true)
        XCTAssertTrue(GitHubStackProvider.trackingFilePaths(commonDirectory: common.path).isEmpty)
    }
}

// MARK: - Capabilities

final class GitHubStackCapabilitiesTests: XCTestCase {
    private let capabilities = GitHubStackProvider().capabilities

    func testDoesNotAdvertiseBranchInsertion() {
        // Only reachable through the interactive `modify` TUI, which TermQ must not spawn.
        XCTAssertFalse(capabilities.contains(.branchInsertion))
    }

    func testDoesNotAdvertiseTrackExisting() {
        // `init <branches...>` adopts a whole set and `link` also creates PRs — neither
        // is "track this one branch onto this base".
        XCTAssertFalse(capabilities.contains(.trackExisting))
    }

    func testDoesNotAdvertiseDestroyStack() {
        // `unstack` leaves every branch in place. Reusing .destroyStack would put a
        // button with git-spice's blast radius on an operation that does not have it.
        XCTAssertFalse(capabilities.contains(.destroyStack))
        XCTAssertTrue(capabilities.contains(.untrackStack))
    }

    func testAdvertisesSyncPushes() {
        // `gh stack sync` force-pushes every branch and mutates the stack on GitHub.
        XCTAssertTrue(capabilities.contains(.syncPushes))
    }

    func testAdvertisesGitHubOnlyCapabilities() {
        XCTAssertTrue(capabilities.contains(.mergeStack))
        XCTAssertTrue(capabilities.contains(.remoteDiscovery))
        XCTAssertTrue(capabilities.contains(.linkExisting))
    }

    func testProviderID() {
        XCTAssertEqual(GitHubStackProvider().providerID, .gitHub)
    }

    func testDestroyStack_refusesRatherThanSubstitutingUntrack() async {
        do {
            try await GitHubStackProvider().destroyStack(in: "/wt")
            XCTFail("expected refusal")
        } catch let error as StackProviderError {
            guard case .unsupported = error else {
                return XCTFail("expected .unsupported, got \(error)")
            }
        } catch {
            XCTFail("expected StackProviderError, got \(error)")
        }
    }
}

// MARK: - Non-interactivity

final class GitHubStackEnvironmentTests: XCTestCase {
    func testEnvironment_neutralizesPagerAndColor() {
        // gh-stack has no global --no-prompt: it sniffs for a TTY and pipes non-JSON
        // output through a pager. A pager would hold the pipe open indefinitely.
        let env = GitHubStackProvider.commandEnvironment
        XCTAssertEqual(env["GH_PAGER"], "cat")
        XCTAssertEqual(env["PAGER"], "cat")
        XCTAssertEqual(env["NO_COLOR"], "1")
        XCTAssertNotNil(env["GH_STACK_THEME"], "theme detection must not probe an absent terminal")
    }
}
