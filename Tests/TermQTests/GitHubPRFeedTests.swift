import Foundation
import TermQShared
import XCTest

@testable import TermQ

// MARK: - Helpers

private func makePR(
    number: Int,
    isDraft: Bool = false,
    reviewers: [String] = [],
    updatedAt: Date = Date(timeIntervalSince1970: 0),
    headOid: String? = nil
) -> GitHubPR {
    let json = """
        {
          "number": \(number),
          "title": "PR \(number)",
          "headRefName": "branch-\(number)",
          "headRefOid": "\(headOid ?? "sha\(number)")",
          "author": {"login": "alice"},
          "isCrossRepository": false,
          "isDraft": \(isDraft),
          "reviewRequests": [\(reviewers.map { "{\"login\":\"\($0)\"}" }.joined(separator: ","))],
          "assignees": [],
          "updatedAt": "\(ISO8601DateFormatter().string(from: updatedAt))"
        }
        """
    return try! JSONDecoder().decode(GitHubPR.self, from: Data(json.utf8))
}

// MARK: - prioritisedFeed tests

@MainActor
final class GitHubPRFeedTests: XCTestCase {

    // MARK: Tier 1 — checked-out always first regardless of cap

    func testCheckedOutPRsAlwaysInFeed() {
        let pr1 = makePR(number: 1)
        let pr2 = makePR(number: 2)
        let (feed, overflow) = GitHubPRService.prioritisedFeed(
            prs: [pr1, pr2],
            login: nil,
            matches: [1: "/path/worktree"],  // pr1 checked out
            cap: 1
        )
        XCTAssertEqual(feed.map(\.number), [1])
        XCTAssertEqual(overflow, 1)
    }

    func testCheckedOutPRsExceedCapWithoutTruncation() {
        let prs = (1...3).map { makePR(number: $0) }
        let matches: [Int: String] = [1: "/wt1", 2: "/wt2", 3: "/wt3"]
        let (feed, overflow) = GitHubPRService.prioritisedFeed(
            prs: prs, login: nil, matches: matches, cap: 1)
        XCTAssertEqual(feed.count, 3, "Tier-1 PRs are always included, even beyond cap")
        XCTAssertEqual(overflow, 0)
    }

    // MARK: Tier 2 — review requested

    func testReviewRequestedPRsFilledAfterCheckedOut() {
        let checkedOut = makePR(number: 1)
        let reviewReq = makePR(number: 2, reviewers: ["bob"])
        let other = makePR(number: 3)
        let (feed, _) = GitHubPRService.prioritisedFeed(
            prs: [checkedOut, reviewReq, other],
            login: "bob",
            matches: [1: "/wt"],
            cap: 10
        )
        let nums = feed.map(\.number)
        XCTAssertEqual(nums.first, 1, "Checked-out comes first")
        XCTAssertTrue(nums.contains(2), "Review-requested for login should appear")
        XCTAssertTrue(nums.contains(3))
    }

    func testReviewRequestedIgnoredWhenLoginNil() {
        let pr = makePR(number: 1, reviewers: ["bob"])
        let (feed, overflow) = GitHubPRService.prioritisedFeed(
            prs: [pr], login: nil, matches: [:], cap: 10)
        XCTAssertEqual(feed.map(\.number), [1], "All PRs included in tier3/4 when login unknown")
        XCTAssertEqual(overflow, 0)
    }

    // MARK: Tier 3 — open non-draft with no reviewers

    func testNonDraftNoReviewersInTier3() {
        let draft = makePR(number: 1, isDraft: true)
        let open = makePR(number: 2)
        let withReviewer = makePR(number: 3, reviewers: ["carol"])
        let (feed, _) = GitHubPRService.prioritisedFeed(
            prs: [draft, open, withReviewer], login: "carol", matches: [:], cap: 10)
        let nums = feed.map(\.number)
        // open (tier3) should appear before draft and withReviewer-for-someone-else (tier4)
        XCTAssertTrue(nums.contains(2))
        let indexOpen = nums.firstIndex(of: 2)!
        let indexDraft = nums.firstIndex(of: 1)!
        XCTAssertLessThan(indexOpen, indexDraft, "Open non-draft precedes draft (tier3 < tier4)")
    }

    // MARK: Cap and overflow

    func testCapLimitsNonTier1() {
        let checked = makePR(number: 1)
        let others = (2...10).map { makePR(number: $0) }  // 9 others → 10 total
        let (feed, overflow) = GitHubPRService.prioritisedFeed(
            prs: [checked] + others, login: nil, matches: [1: "/wt"], cap: 4)
        XCTAssertEqual(feed.count, 4, "cap=4: 1 tier1 + 3 from remainder")
        XCTAssertEqual(overflow, 6, "10 total − 4 in feed = 6 overflow")
    }

    func testOverflowZeroWhenAllFit() {
        let prs = (1...3).map { makePR(number: $0) }
        let (feed, overflow) = GitHubPRService.prioritisedFeed(
            prs: prs, login: nil, matches: [:], cap: 10)
        XCTAssertEqual(feed.count, 3)
        XCTAssertEqual(overflow, 0)
    }

    func testCapZeroStillIncludesCheckedOut() {
        let checked = makePR(number: 1)
        let other = makePR(number: 2)
        let (feed, overflow) = GitHubPRService.prioritisedFeed(
            prs: [checked, other], login: nil, matches: [1: "/wt"], cap: 0)
        XCTAssertEqual(feed.map(\.number), [1])
        XCTAssertEqual(overflow, 1)
    }

    func testEmptyPRListReturnsEmpty() {
        let (feed, overflow) = GitHubPRService.prioritisedFeed(
            prs: [], login: nil, matches: [:], cap: 20)
        XCTAssertTrue(feed.isEmpty)
        XCTAssertEqual(overflow, 0)
    }

    // MARK: Within-tier recency ordering (updatedAt desc)

    func testTier1OrderedByUpdatedAtDescending() {
        let old = makePR(number: 1, updatedAt: Date(timeIntervalSince1970: 1000))
        let new = makePR(number: 2, updatedAt: Date(timeIntervalSince1970: 9000))
        let (feed, _) = GitHubPRService.prioritisedFeed(
            prs: [old, new], login: nil,
            matches: [1: "/wt1", 2: "/wt2"], cap: 10)
        XCTAssertEqual(feed.map(\.number), [2, 1], "Newer updatedAt sorts first within tier1")
    }

    func testTier2OrderedByUpdatedAtDescending() {
        let older = makePR(number: 1, reviewers: ["me"], updatedAt: Date(timeIntervalSince1970: 100))
        let newer = makePR(number: 2, reviewers: ["me"], updatedAt: Date(timeIntervalSince1970: 900))
        let (feed, _) = GitHubPRService.prioritisedFeed(
            prs: [older, newer], login: "me", matches: [:], cap: 10)
        XCTAssertEqual(feed.map(\.number), [2, 1])
    }

    // MARK: Tier ordering end-to-end

    func testTierOrderRespectedAcrossAllFourTiers() {
        let t1 = makePR(number: 1)  // checked out → tier1
        let t2 = makePR(number: 2, reviewers: ["me"])  // review requested → tier2
        let t3 = makePR(number: 3)  // open non-draft → tier3
        let t4 = makePR(number: 4, isDraft: true)  // draft → tier4

        let (feed, _) = GitHubPRService.prioritisedFeed(
            prs: [t4, t3, t2, t1],  // deliberately shuffled
            login: "me",
            matches: [1: "/wt"],
            cap: 10
        )
        XCTAssertEqual(feed.map(\.number), [1, 2, 3, 4])
    }
}

// MARK: - RunWithFocusSheet title tests

@MainActor
final class RunWithFocusSheetTitleTests: XCTestCase {

    // MARK: repoSlug extraction

    func testSlugFromDeepPath() {
        let title = RunWithFocusSheet.makeCardTitleStatic(
            focus: "pr-review", profile: "", harnessId: "h",
            repoPath: "/Users/david/Storage/Workspace/eyelock/TermQ", prNumber: 42)
        XCTAssertTrue(title.contains("eyelock/TermQ"), "Should extract last two path components")
        XCTAssertTrue(title.contains("#42"))
        XCTAssertTrue(title.hasPrefix("pr-review: "))
    }

    func testSlugFromShallowPath() {
        let title = RunWithFocusSheet.makeCardTitleStatic(
            focus: "run", profile: "", harnessId: "h",
            repoPath: "/myrepo", prNumber: 1)
        XCTAssertTrue(title.contains("#1"))
    }

    // MARK: Label precedence (focus > profile > harnessId)

    func testFocusTakesPrecedenceOverProfile() {
        let title = RunWithFocusSheet.makeCardTitleStatic(
            focus: "pr-summary", profile: "fast", harnessId: "termq-dev",
            repoPath: "/a/b", prNumber: 7)
        XCTAssertTrue(title.hasPrefix("pr-summary: "))
    }

    func testProfileUsedWhenNoFocus() {
        let title = RunWithFocusSheet.makeCardTitleStatic(
            focus: nil, profile: "fast", harnessId: "termq-dev",
            repoPath: "/a/b", prNumber: 7)
        XCTAssertTrue(title.hasPrefix("fast: "))
    }

    func testHarnessIdUsedWhenNeitherFocusNorProfile() {
        let title = RunWithFocusSheet.makeCardTitleStatic(
            focus: nil, profile: "", harnessId: "termq-dev",
            repoPath: "/a/b", prNumber: 7)
        XCTAssertTrue(title.hasPrefix("termq-dev: "))
    }

    func testEmptyFocusStringFallsBackToProfile() {
        let title = RunWithFocusSheet.makeCardTitleStatic(
            focus: "", profile: "quick", harnessId: "h",
            repoPath: "/a/b", prNumber: 1)
        XCTAssertTrue(title.hasPrefix("quick: "))
    }

    // MARK: Truncation

    func testShortTitleNotTruncated() {
        let title = RunWithFocusSheet.makeCardTitleStatic(
            focus: "f", profile: "", harnessId: "h",
            repoPath: "/org/repo", prNumber: 1)
        XCTAssertEqual(title, "f: org/repo#1")
        XCTAssertLessThanOrEqual(title.count, 40)
    }

    func testLongOrgRepoTruncatedToFitBudget() {
        let longPath = "/MyCompany-Admin-And-Another-Team/Admin-MySuperProject-CalledReallyLong"
        let title = RunWithFocusSheet.makeCardTitleStatic(
            focus: "pr-summary", profile: "", harnessId: "h",
            repoPath: longPath, prNumber: 248)
        XCTAssertLessThanOrEqual(title.count, 40, "Title must not exceed 40 chars")
        XCTAssertTrue(title.hasPrefix("pr-summary: "), "Focus label always preserved")
        XCTAssertTrue(title.contains("#248"), "PR number always preserved")
        XCTAssertTrue(title.contains("…"), "Long slug should be middle-truncated")
    }

    func testExtremelyLongFocusNameStillIncludesPRNumber() {
        let veryLongFocus = String(repeating: "x", count: 35)
        let title = RunWithFocusSheet.makeCardTitleStatic(
            focus: veryLongFocus, profile: "", harnessId: "h",
            repoPath: "/org/repo", prNumber: 99)
        XCTAssertTrue(title.contains("#99"), "PR number always present even when budget is tiny")
    }

    func testTitleFitsExactly40Chars() {
        // Verify a known-length input lands at ≤ 40.
        let title = RunWithFocusSheet.makeCardTitleStatic(
            focus: "code-review", profile: "", harnessId: "h",
            repoPath: "/eyelock/TermQ", prNumber: 300)
        XCTAssertLessThanOrEqual(title.count, 40)
    }
}

// MARK: - HarnessLaunchConfig.command tests

@MainActor
final class HarnessLaunchConfigCommandTests: XCTestCase {

    private func makeConfig(
        harnessID: String = "my-harness",
        vendorID: String = "",
        defaultVendor: String = "",
        focus: String? = nil,
        profile: String? = nil,
        prompt: String? = nil,
        interactive: Bool = false,
        branch: String? = nil
    ) -> HarnessLaunchConfig {
        HarnessLaunchConfig(
            harnessID: harnessID,
            vendorID: vendorID,
            defaultVendor: defaultVendor,
            focus: focus,
            profile: profile,
            workingDirectory: "/tmp",
            prompt: prompt,
            instructions: nil,
            backend: .direct,
            branch: branch,
            interactive: false,
            cardTitle: nil
        )
    }

    // MARK: Baseline

    func testMinimalCommand() {
        let cmd = makeConfig().command()
        XCTAssertEqual(cmd, "ynh run my-harness")
    }

    // MARK: Vendor flag

    func testVendorFlagIncludedWhenSet() {
        let cmd = makeConfig(vendorID: "claude").command()
        XCTAssertEqual(cmd, "ynh run my-harness -v claude")
    }

    func testEmptyVendorIDOmitted() {
        let cmd = makeConfig(vendorID: "").command()
        XCTAssertFalse(cmd.contains("-v"), "Empty vendorID should not emit -v flag")
    }

    // MARK: Focus vs Profile (mutually exclusive in YNH)

    func testFocusFlagEmitted() {
        let cmd = makeConfig(focus: "pr-summary").command()
        XCTAssertTrue(cmd.contains("--focus pr-summary"))
        XCTAssertFalse(cmd.contains("--profile"))
    }

    func testProfileFlagEmittedWhenNoFocus() {
        let cmd = makeConfig(profile: "fast").command()
        XCTAssertTrue(cmd.contains("--profile fast"))
        XCTAssertFalse(cmd.contains("--focus"))
    }

    func testFocusTakesPrecedenceOverProfile() {
        let cmd = makeConfig(focus: "pr-summary", profile: "fast").command()
        XCTAssertTrue(cmd.contains("--focus pr-summary"))
        XCTAssertFalse(cmd.contains("--profile"))
    }

    func testEmptyFocusStringOmitted() {
        let cmd = makeConfig(focus: "").command()
        XCTAssertFalse(cmd.contains("--focus"))
    }

    // MARK: Interactive flag

    func testInteractiveFlagPosition() {
        let config = HarnessLaunchConfig(
            harnessID: "h", vendorID: "", defaultVendor: "", focus: "f",
            profile: nil, workingDirectory: "/tmp", prompt: nil,
            instructions: nil, backend: .direct, branch: nil, interactive: true, cardTitle: nil)
        let cmd = config.command(sessionName: "termq-abc")
        // Expected: ynh run h --focus f --interactive --session-name termq-abc
        let parts = cmd.components(separatedBy: " ")
        let focusIdx = parts.firstIndex(of: "--focus")!
        let interactiveIdx = parts.firstIndex(of: "--interactive")!
        let sessionIdx = parts.firstIndex(of: "--session-name")!
        XCTAssertLessThan(focusIdx, interactiveIdx, "--interactive comes after --focus")
        XCTAssertLessThan(interactiveIdx, sessionIdx, "--interactive comes before --session-name")
    }

    func testInteractiveFlagAbsentWhenFalse() {
        let cmd = makeConfig().command()
        XCTAssertFalse(cmd.contains("--interactive"))
    }

    // MARK: Session name

    func testSessionNameAppended() {
        let cmd = makeConfig().command(sessionName: "termq-deadbeef")
        XCTAssertTrue(cmd.contains("--session-name termq-deadbeef"))
    }

    func testSessionNameOmittedWhenNil() {
        let cmd = makeConfig().command(sessionName: nil)
        XCTAssertFalse(cmd.contains("--session-name"))
    }

    // MARK: Prompt

    func testPromptAfterDoubleDash() {
        let config = HarnessLaunchConfig(
            harnessID: "h", vendorID: "", defaultVendor: "", focus: nil,
            profile: nil, workingDirectory: "/tmp", prompt: "review this PR",
            instructions: nil, backend: .direct, branch: nil, interactive: false, cardTitle: nil)
        let cmd = config.command()
        XCTAssertTrue(cmd.contains("--"))
        let dashIdx = cmd.range(of: " -- ")!.lowerBound
        XCTAssertTrue(cmd[dashIdx...].contains("review this PR"))
    }

    func testNilPromptOmitted() {
        let cmd = makeConfig(prompt: nil).command()
        XCTAssertFalse(cmd.contains("--"))
    }

    func testEmptyPromptOmitted() {
        let cmd = makeConfig(prompt: "").command()
        XCTAssertFalse(cmd.contains("--"))
    }

    func testPromptWithSingleQuotesEscaped() {
        let config = HarnessLaunchConfig(
            harnessID: "h", vendorID: "", defaultVendor: "", focus: nil,
            profile: nil, workingDirectory: "/tmp", prompt: "it's a test",
            instructions: nil, backend: .direct, branch: nil, interactive: false, cardTitle: nil)
        let cmd = config.command()
        XCTAssertTrue(cmd.contains("'it'\\''s a test'"), "Single quotes must be escaped")
    }

    // MARK: Instructions flag

    func testInstructionsFlagIncluded() {
        let config = HarnessLaunchConfig(
            harnessID: "h", vendorID: "", defaultVendor: "", focus: "pr-summary",
            profile: nil, workingDirectory: "/tmp", prompt: nil,
            instructions: "PR #42 in org/repo", backend: .direct, branch: nil,
            interactive: false, cardTitle: nil)
        let cmd = config.command()
        XCTAssertTrue(cmd.contains("--instructions"), "instructions flag must be emitted")
        XCTAssertTrue(cmd.contains("PR #42 in org/repo"), "instructions value must be in command")
    }

    func testInstructionsValueShellQuoted() {
        let config = HarnessLaunchConfig(
            harnessID: "h", vendorID: "", defaultVendor: "", focus: nil,
            profile: nil, workingDirectory: "/tmp", prompt: nil,
            instructions: "it's PR #1", backend: .direct, branch: nil,
            interactive: false, cardTitle: nil)
        let cmd = config.command()
        XCTAssertTrue(cmd.contains("'it'\\''s PR #1'"), "single quotes in instructions must be escaped")
    }

    func testNilInstructionsOmitted() {
        let cmd = makeConfig().command()
        XCTAssertFalse(cmd.contains("--instructions"), "nil instructions must not emit flag")
    }

    func testInstructionsAppearsBeforeSessionName() {
        let config = HarnessLaunchConfig(
            harnessID: "h", vendorID: "", defaultVendor: "", focus: "f",
            profile: nil, workingDirectory: "/tmp", prompt: nil,
            instructions: "PR #7 in org/repo", backend: .direct, branch: nil,
            interactive: false, cardTitle: nil)
        let cmd = config.command(sessionName: "termq-abc")
        let parts = cmd.components(separatedBy: " ")
        let instrIdx = parts.firstIndex(of: "--instructions")!
        let sessionIdx = parts.firstIndex(of: "--session-name")!
        XCTAssertLessThan(instrIdx, sessionIdx, "--instructions comes before --session-name")
    }

    // MARK: Full command composition

    func testFullCommandWithAllFlags() {
        let config = HarnessLaunchConfig(
            harnessID: "termq-dev", vendorID: "claude", defaultVendor: "claude",
            focus: "pr-summary", profile: nil, workingDirectory: "/tmp", prompt: nil,
            instructions: nil, backend: .direct, branch: "feat/x", interactive: true, cardTitle: nil)
        let cmd = config.command(sessionName: "termq-abc123")
        XCTAssertEqual(
            cmd,
            "ynh run termq-dev -v claude --focus pr-summary --interactive --session-name termq-abc123"
        )
    }

    // MARK: Tags

    func testTagsIncludeFocus() {
        let config = HarnessLaunchConfig(
            harnessID: "h", vendorID: "claude", defaultVendor: "", focus: "pr-summary",
            profile: nil, workingDirectory: "/tmp", prompt: nil,
            instructions: nil, backend: .direct, branch: "main", interactive: false, cardTitle: nil)
        let tags = Dictionary(uniqueKeysWithValues: config.tags.map { ($0.key, $0.value) })
        XCTAssertEqual(tags["focus"], "pr-summary")
        XCTAssertEqual(tags["vendor"], "claude")
        XCTAssertEqual(tags["branch"], "main")
        XCTAssertEqual(tags["source"], "harness")
    }

    func testTagsUseDefaultVendorWhenNoOverride() {
        let config = HarnessLaunchConfig(
            harnessID: "h", vendorID: "", defaultVendor: "gemini", focus: nil,
            profile: nil, workingDirectory: "/tmp", prompt: nil,
            instructions: nil, backend: .direct, branch: nil, interactive: false, cardTitle: nil)
        let tags = Dictionary(uniqueKeysWithValues: config.tags.map { ($0.key, $0.value) })
        XCTAssertEqual(tags["vendor"], "gemini", "defaultVendor used for tag when vendorID empty")
    }
}
