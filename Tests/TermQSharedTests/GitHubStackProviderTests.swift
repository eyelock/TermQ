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

    func testDoesNotAdvertiseScopedOperations() {
        // `rebase` pivots on HEAD and `submit` has no scoping flag, so neither can be
        // pointed at a named branch. Advertising these would put "Restack from Here" and
        // per-branch Submit in the menus, where they would either refuse or act on a
        // wider range than the label promises.
        XCTAssertFalse(capabilities.contains(.scopedRestack))
        XCTAssertFalse(capabilities.contains(.scopedSubmit))
        // The unscoped forms still work — the whole stack is the unit gh-stack operates on.
        XCTAssertTrue(capabilities.contains(.restack))
        XCTAssertTrue(capabilities.contains(.submit))
    }

    func testGitSpiceStillAdvertisesScopedOperations() {
        // Every git-spice restack/submit form takes --branch=NAME; adding the flags must
        // not have narrowed the existing provider.
        let gitSpice = GitSpiceStackProvider().capabilities
        XCTAssertTrue(gitSpice.contains(.scopedRestack))
        XCTAssertTrue(gitSpice.contains(.scopedSubmit))
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

// MARK: - Command Construction

/// `gh stack rebase` always pivots on HEAD: its positional argument selects WHICH STACK
/// to load, and `--upstack`/`--downstack` are measured from the checked-out branch. These
/// lock in that a scope naming some other branch is refused rather than silently rebasing
/// a different range than the caller asked for.
final class GitHubStackRestackArgumentsTests: XCTestCase {
    func testStackScope_rebasesTheWholeStack() throws {
        let args = try GitHubStackProvider.restackArguments(for: .stack, currentBranch: "feat-a")
        XCTAssertEqual(args, ["stack", "rebase"])
    }

    func testUpstackFromNil_usesTheUpstackFlag() throws {
        let args = try GitHubStackProvider.restackArguments(
            for: .upstack(from: nil), currentBranch: "feat-a")
        XCTAssertEqual(args, ["stack", "rebase", "--upstack"])
    }

    func testUpstackFromCurrentBranch_isTheSameAsFromNil() throws {
        // The pivot gh-stack would use and the pivot the caller asked for agree, so the
        // command is expressible exactly.
        let args = try GitHubStackProvider.restackArguments(
            for: .upstack(from: "feat-a"), currentBranch: "feat-a")
        XCTAssertEqual(args, ["stack", "rebase", "--upstack"])
    }

    func testUpstackFromOtherBranch_refusesWithARecoverableError() {
        // The dangerous case: gh-stack would happily run and rebase from HEAD instead.
        XCTAssertThrowsError(
            try GitHubStackProvider.restackArguments(
                for: .upstack(from: "feat-b"), currentBranch: "feat-a")
        ) { error in
            guard case StackProviderError.preconditionFailed(let detail)? = error as? StackProviderError
            else { return XCTFail("expected .preconditionFailed, got \(error)") }
            XCTAssertTrue(detail.contains("feat-b"), "the message must name the branch to check out")
        }
    }

    func testSingleBranchScope_isUnsupported() {
        // `--no-trunk` skips the trunk, not the other branches — it is not a substitute
        // for a single-branch rebase, and there is no other candidate.
        XCTAssertThrowsError(
            try GitHubStackProvider.restackArguments(for: .branch("feat-a"), currentBranch: "feat-a")
        ) { error in
            guard case StackProviderError.unsupported? = error as? StackProviderError else {
                return XCTFail("expected .unsupported, got \(error)")
            }
        }
    }

    func testUpstackFromNil_withDetachedHead_stillWorks() {
        // A detached HEAD yields a nil current branch; "from wherever we are" is still
        // meaningful, and gh-stack resolves the stack itself.
        XCTAssertEqual(
            try GitHubStackProvider.restackArguments(for: .upstack(from: nil), currentBranch: nil),
            ["stack", "rebase", "--upstack"])
    }
}

/// `gh stack submit` has no scoping flag and always covers the whole stack. `--auto`
/// creates new PRs as drafts, so `--open` is the inverse of `options.draft`.
final class GitHubStackSubmitArgumentsTests: XCTestCase {
    func testStackScope_readyForReview_marksPRsOpen() throws {
        let args = try GitHubStackProvider.submitArguments(
            for: .stack, options: StackSubmitOptions(draft: false))
        XCTAssertEqual(args, ["stack", "submit", "--auto", "--open"])
    }

    func testStackScope_draft_omitsOpen() throws {
        // Not a missing flag: on the --auto path, no --open IS the draft state.
        let args = try GitHubStackProvider.submitArguments(
            for: .stack, options: StackSubmitOptions(draft: true))
        XCTAssertEqual(args, ["stack", "submit", "--auto"])
    }

    func testAutoIsAlwaysPassed() throws {
        // Without --auto, submit opens a full-screen PR editor when it believes it has a
        // terminal. TermQ must never spawn that.
        for options in [StackSubmitOptions(draft: true), StackSubmitOptions(draft: false)] {
            let args = try GitHubStackProvider.submitArguments(for: .stack, options: options)
            XCTAssertTrue(args.contains("--auto"))
        }
    }

    func testUpdateOnly_isUnsupported() {
        // gh-stack always creates a PR for a branch that lacks one; there is no
        // update-what-exists mode to map onto.
        XCTAssertThrowsError(
            try GitHubStackProvider.submitArguments(
                for: .stack, options: StackSubmitOptions(updateOnly: true))
        ) { error in
            guard case StackProviderError.unsupported? = error as? StackProviderError else {
                return XCTFail("expected .unsupported, got \(error)")
            }
        }
    }

    func testPartialScopes_areRefusedRatherThanWidened() {
        // Quietly submitting the whole stack when one branch was asked for would push
        // and open PRs the user never requested.
        for scope in [StackScope.branch("feat-a"), .upstack(from: "feat-a"), .upstack(from: nil)] {
            XCTAssertThrowsError(
                try GitHubStackProvider.submitArguments(for: scope, options: StackSubmitOptions())
            ) { error in
                guard case StackProviderError.unsupported? = error as? StackProviderError else {
                    return XCTFail("expected .unsupported for \(scope), got \(error)")
                }
            }
        }
    }
}

// MARK: - Exit Code Mapping

/// gh-stack assigns a distinct exit code per failure class, which is far more stable than
/// matching on message text. These pin the classification, especially that a rebase
/// conflict is NOT an error.
final class GitHubStackExitCodeTests: XCTestCase {
    private func result(_ code: Int32, stderr: String = "") -> StackProcessResult {
        StackProcessResult(exitCode: code, stdout: "", stderr: stderr)
    }

    func testConflict_isNotClassifiedAsAPreconditionFailure() {
        // Exit 3 is a paused rebase. It must fall through to .commandFailed so
        // StackService's `pausedOperation` probe turns it into the conflict banner
        // rather than an alert the user cannot act on.
        let error = GitHubStackProvider.mapExitCode(result(3), command: "gh stack rebase")
        guard case .commandFailed(_, let code, _) = error else {
            return XCTFail("expected .commandFailed, got \(error)")
        }
        XCTAssertEqual(code, 3)
    }

    func testRecoverableCodes_becomePreconditionFailures() {
        // 2 not-in-stack, 5 invalid args (includes "can only add to the top"),
        // 6 ambiguous stack/remote, 7 rebase already running, 9 stacks unavailable,
        // 10 interrupted modify session — all fixable by the user.
        for code in [Int32(2), 5, 6, 7, 9, 10] {
            let error = GitHubStackProvider.mapExitCode(result(code), command: "gh stack add")
            guard case .preconditionFailed = error else {
                return XCTFail("exit \(code) should be .preconditionFailed, got \(error)")
            }
        }
    }

    func testStderrIsPreferredOverTheGenericMessage() {
        // gh-stack's own wording is more specific than anything written here.
        let error = GitHubStackProvider.mapExitCode(
            result(5, stderr: "can only add branches to the top of the stack\n"),
            command: "gh stack add")
        XCTAssertEqual(
            error.errorDescription, "can only add branches to the top of the stack")
    }

    func testUnknownCode_fallsThroughWithItsOutput() {
        let error = GitHubStackProvider.mapExitCode(
            result(1, stderr: "boom"), command: "gh stack sync")
        guard case .commandFailed(let command, let code, let output) = error else {
            return XCTFail("expected .commandFailed, got \(error)")
        }
        XCTAssertEqual(command, "gh stack sync")
        XCTAssertEqual(code, 1)
        XCTAssertEqual(output, "boom")
    }
}
