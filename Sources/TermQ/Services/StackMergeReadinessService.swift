import Foundation
import TermQShared

// MARK: - Readiness Model

/// Whether a pull request has the reviews it needs.
enum StackReviewState: String, Sendable, Equatable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
    /// No review decision — either none is required, or none has been given.
    case none = ""
}

/// Rolled-up CI state for a pull request's head commit.
enum StackCheckState: Sendable, Equatable {
    case passing
    case failing
    case pending
    /// No checks are configured, or none have reported.
    case none
}

/// One pull request in a stack, with everything the merge confirmation needs to show.
struct StackPRReadiness: Sendable, Equatable, Identifiable {
    let number: Int
    let title: String
    let branch: String
    let isDraft: Bool
    /// `OPEN`, `CLOSED`, or `MERGED`.
    let state: String
    let review: StackReviewState
    let checks: StackCheckState

    var id: Int { number }

    /// Whether this pull request stops the stack ABOVE it from being merged.
    ///
    /// Deliberately narrow: only draft and not-open block. Missing reviews and failing
    /// checks are shown so the user can weigh them, but GitHub — not TermQ — decides
    /// whether they actually prevent a merge, because branch protection rules vary per
    /// repository and TermQ cannot see them. Predicting a refusal we're not sure about
    /// would be worse than letting GitHub answer.
    var blocksStackMerge: Bool {
        isDraft || state != "OPEN"
    }

    /// Why it blocks, for the confirmation sheet.
    var blockReason: String? {
        if state == "MERGED" { return Strings.Stacks.mergeBlockedMerged }
        if state != "OPEN" { return Strings.Stacks.mergeBlockedClosed }
        if isDraft { return Strings.Stacks.mergeBlockedDraft }
        return nil
    }
}

/// Everything the Merge Stack sheet needs, fetched at the moment the user asks for it.
struct StackMergeReadiness: Sendable, Equatable {
    /// Bottom of the stack first — merge order.
    let prs: [StackPRReadiness]
    /// The repository's own default merge method, shown so the sheet can name what will
    /// happen. Never used to pass a flag: gh-stack resolves the default itself, and
    /// naming one here risks a method the repository forbids.
    let defaultMergeMethod: StackMergeMethod?

    /// The lowest pull request that blocks a whole-stack merge, if any.
    ///
    /// gh-stack refuses a whole-stack merge when a draft or closed pull request sits
    /// partway up, and tells the user to merge up to an explicit pull request instead.
    /// Finding it up front means the sheet can say so before the user confirms something
    /// that cannot succeed.
    var blocker: StackPRReadiness? {
        prs.first { $0.blocksStackMerge }
    }

    /// Pull requests that would merge — everything below the blocker, or all of them.
    var mergeable: [StackPRReadiness] {
        guard let blocker, let index = prs.firstIndex(where: { $0.number == blocker.number })
        else { return prs }
        return Array(prs.prefix(upTo: index))
    }

    var canMergeWholeStack: Bool { blocker == nil && !prs.isEmpty }
}

// MARK: - Service

/// Fetches merge readiness for a stack's pull requests, on demand.
///
/// ## Why this is not part of the PR feed
///
/// `GitHubPRService` fetches up to 100 PRs per repository on every refresh. Review
/// decisions and check rollups are comparatively expensive fields, and they would be paid
/// for on every refresh, for every PR, to populate a sheet most users open rarely.
///
/// They are also the fields that must be FRESHEST: stale readiness inside a merge
/// confirmation is actively dangerous, because it is the basis on which someone decides to
/// merge. Fetching when the sheet opens costs one scoped call and shows state as of the
/// moment of the decision, which is the only moment that matters here.
@MainActor
final class StackMergeReadinessService {
    static let shared = StackMergeReadinessService()

    private let ghProbe: GhCliProbe
    private let commandRunner: any YNHCommandRunner

    init(ghProbe: GhCliProbe = .shared, commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.ghProbe = ghProbe
        self.commandRunner = commandRunner
    }

    /// Fetch readiness for `prNumbers`, bottom of the stack first.
    ///
    /// One `gh pr view` per pull request, run concurrently. A stack is typically two to
    /// five PRs, and per-PR reads keep this precise: `gh pr list --state open` would
    /// silently omit a closed pull request, which is exactly the case that blocks a
    /// stack merge and most needs reporting.
    func readiness(repoPath: String, prNumbers: [Int]) async throws -> StackMergeReadiness {
        // `.status.ghPath` rather than requiring `.ready`: an unauthenticated gh still
        // has a usable path, and letting the call fail with gh's own auth message is more
        // informative than a generic "not installed" from here.
        guard let ghPath = ghProbe.status.ghPath else {
            throw StackProviderError.binaryMissing
        }
        async let method = defaultMergeMethod(repoPath: repoPath, ghPath: ghPath)

        var byNumber: [Int: StackPRReadiness] = [:]
        try await withThrowingTaskGroup(of: StackPRReadiness?.self) { group in
            for number in prNumbers {
                group.addTask { [commandRunner] in
                    try await Self.fetchOne(
                        number: number, repoPath: repoPath, ghPath: ghPath,
                        commandRunner: commandRunner)
                }
            }
            for try await entry in group {
                if let entry { byNumber[entry.number] = entry }
            }
        }

        // Preserve the caller's order: it is the stack's bottom-to-top order, which is
        // also merge order, and the task group completes in whatever order it likes.
        return StackMergeReadiness(
            prs: prNumbers.compactMap { byNumber[$0] },
            defaultMergeMethod: await method)
    }

    private static func fetchOne(
        number: Int, repoPath: String, ghPath: String, commandRunner: any YNHCommandRunner
    ) async throws -> StackPRReadiness? {
        let result = try await commandRunner.run(
            executable: ghPath,
            arguments: [
                "pr", "view", String(number),
                "--json", "number,title,headRefName,isDraft,state,reviewDecision,statusCheckRollup",
            ],
            environment: nil,
            currentDirectory: repoPath,
            onStdoutLine: nil,
            onStderrLine: nil
        )
        guard result.didSucceed, let data = result.stdout.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StackPRReadinessDTO.self, from: data).toReadiness()
    }

    /// The repository's configured default merge method. Display only.
    private func defaultMergeMethod(repoPath: String, ghPath: String) async -> StackMergeMethod? {
        guard
            let result = try? await commandRunner.run(
                executable: ghPath,
                arguments: ["repo", "view", "--json", "viewerDefaultMergeMethod"],
                environment: nil,
                currentDirectory: repoPath,
                onStdoutLine: nil,
                onStderrLine: nil
            ),
            result.didSucceed,
            let data = result.stdout.data(using: .utf8),
            let dto = try? JSONDecoder().decode(DefaultMergeMethodDTO.self, from: data)
        else { return nil }
        return StackMergeMethod(githubDefault: dto.viewerDefaultMergeMethod)
    }
}

// MARK: - DTOs

/// `gh pr view --json …`. Everything but `number` decodes leniently — a missing field
/// should degrade one row of the sheet, never fail the whole fetch.
struct StackPRReadinessDTO: Decodable {
    let number: Int
    let title: String?
    let headRefName: String?
    let isDraft: Bool?
    let state: String?
    let reviewDecision: String?
    let statusCheckRollup: [CheckDTO]?

    struct CheckDTO: Decodable {
        /// Checks API: COMPLETED / IN_PROGRESS / QUEUED …
        let status: String?
        /// Checks API: SUCCESS / FAILURE / …
        let conclusion: String?
        /// Commit-status API uses `state` instead: SUCCESS / FAILURE / PENDING.
        let state: String?
    }

    func toReadiness() -> StackPRReadiness {
        StackPRReadiness(
            number: number,
            title: title ?? "",
            branch: headRefName ?? "",
            isDraft: isDraft ?? false,
            // Absent state is treated as OPEN: reporting a PR as closed when we simply
            // could not read it would wrongly mark the stack as blocked.
            state: state ?? "OPEN",
            review: StackReviewState(rawValue: reviewDecision ?? "") ?? .none,
            checks: Self.rollUp(statusCheckRollup ?? []))
    }

    /// Collapse the per-check array into one state. Any failure wins, then anything still
    /// running, then success — the order someone scanning a merge sheet cares about.
    static func rollUp(_ checks: [CheckDTO]) -> StackCheckState {
        guard !checks.isEmpty else { return .none }
        var sawPending = false
        for check in checks {
            let conclusion = (check.conclusion ?? check.state ?? "").uppercased()
            let status = (check.status ?? "").uppercased()
            if ["FAILURE", "TIMED_OUT", "CANCELLED", "ERROR", "ACTION_REQUIRED"].contains(conclusion) {
                return .failing
            }
            if conclusion.isEmpty || status == "IN_PROGRESS" || status == "QUEUED"
                || conclusion == "PENDING"
            {
                sawPending = true
            }
        }
        return sawPending ? .pending : .passing
    }
}

private struct DefaultMergeMethodDTO: Decodable {
    let viewerDefaultMergeMethod: String
}
