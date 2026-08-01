import Foundation
import TermQShared

// MARK: - Model

/// One pull request as the forge reports it inside a stack.
struct RemoteStackPR: Sendable, Equatable, Identifiable {
    let number: Int
    let headRef: String
    /// `open` or `closed` — the REST endpoint lowercases these, unlike `gh pr view`.
    let state: String
    let isDraft: Bool
    let isMerged: Bool

    var id: Int { number }
}

/// A stack as it exists on the forge, independent of anything checked out locally.
struct RemoteStack: Sendable, Equatable, Identifiable {
    let number: Int
    let baseRef: String
    let isOpen: Bool
    /// Bottom of the stack first.
    let pullRequests: [RemoteStackPR]

    var id: Int { number }

    /// Opaque identifier for `StackProvider.checkoutStack(remoteStackID:)`.
    var remoteStackID: String { String(number) }

    func contains(prNumber: Int) -> Bool {
        pullRequests.contains { $0.number == prNumber }
    }
}

// MARK: - Service

/// Discovers stacks that exist on the forge, whether or not anything is checked out.
///
/// ## Why this exists separately from the stack graph
///
/// `GitHubStackProvider.graph` reads gh-stack's LOCAL tracking file, so it can only see
/// stacks this machine already has. That is the right source for the sidebar's own stack
/// UI, and exactly the wrong one for "check out a stack you have never touched" — the
/// only stacks it can offer are the ones that need no checking out.
///
/// `gh stack link` makes the gap plainer: it registers a stack on the forge and writes no
/// local tracking at all, so without this service a successful link leaves the app looking
/// as though nothing happened.
///
/// ## About the endpoint
///
/// `repos/{owner}/{repo}/stacks` is what gh-stack itself calls (`ListStacks` /
/// `FindStackForPR` / `GetStack`), reached through `gh api` so it uses gh's own
/// authentication — the same arrangement as the `gh pr list` calls elsewhere. `{owner}`
/// and `{repo}` are resolved by gh from the working directory's remote.
///
/// It is a PREVIEW API: stacked pull requests are new and these paths are not in the
/// published REST documentation yet. Decoding is therefore deliberately lenient — a
/// renamed or missing field must hide the affordance, never break the pull request feed
/// it sits inside. A 404 means the repository does not have stacked pull requests enabled,
/// which is a normal state and not an error.
@MainActor
final class RemoteStackDiscoveryService: ObservableObject {
    static let shared = RemoteStackDiscoveryService()

    /// Stacks per repository path. An empty array means "asked, and there are none" —
    /// distinct from a missing key, which means "not asked yet".
    @Published private(set) var stacksByRepo: [String: [RemoteStack]] = [:]

    private let ghProbe: GhCliProbe
    private let commandRunner: any YNHCommandRunner
    /// In-flight fetches, so a feed that renders many rows triggers one request.
    private var inFlight: [String: Task<[RemoteStack], Never>] = [:]

    init(ghProbe: GhCliProbe = .shared, commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.ghProbe = ghProbe
        self.commandRunner = commandRunner
    }

    /// The stack containing `prNumber`, from whatever was last discovered.
    ///
    /// Pure lookup — never fetches. Views call this while rendering, and a network call
    /// from a view body would fire on every redraw.
    func stack(containingPR prNumber: Int, repoPath: String) -> RemoteStack? {
        stacksByRepo[repoPath]?.first { $0.contains(prNumber: prNumber) }
    }

    /// Fetch this repository's stacks, coalescing concurrent callers.
    @discardableResult
    func refresh(repoPath: String) async -> [RemoteStack] {
        if let existing = inFlight[repoPath] { return await existing.value }
        let task = Task { [weak self] () -> [RemoteStack] in
            guard let self else { return [] }
            return await self.fetch(repoPath: repoPath)
        }
        inFlight[repoPath] = task
        let stacks = await task.value
        inFlight.removeValue(forKey: repoPath)
        stacksByRepo[repoPath] = stacks
        return stacks
    }

    func evict(repoPath: String) {
        stacksByRepo.removeValue(forKey: repoPath)
        inFlight.removeValue(forKey: repoPath)
    }

    private func fetch(repoPath: String) async -> [RemoteStack] {
        guard let ghPath = ghProbe.status.ghPath else { return [] }
        guard
            let result = try? await commandRunner.run(
                executable: ghPath,
                arguments: ["api", "repos/{owner}/{repo}/stacks"],
                environment: nil,
                currentDirectory: repoPath,
                onStdoutLine: nil,
                onStderrLine: nil
            )
        else { return [] }
        // A 404 (stacked PRs not enabled here) is an ordinary answer, not a failure to
        // report — the affordance simply does not appear.
        guard result.didSucceed, let data = result.stdout.data(using: .utf8) else { return [] }
        return Self.decodeStacks(data)
    }

    /// Split out so the preview-API leniency is testable without a live `gh`.
    static func decodeStacks(_ data: Data) -> [RemoteStack] {
        let decoded = (try? JSONDecoder().decode([RemoteStackDTO].self, from: data)) ?? []
        return decoded.compactMap { $0.toRemoteStack() }
    }
}

// MARK: - DTOs

/// `repos/{owner}/{repo}/stacks`. Every field is optional bar `number`: this is a preview
/// API, and a shape change should cost the Check Out Whole Stack item rather than the feed.
struct RemoteStackDTO: Decodable {
    let number: Int?
    let base: BaseDTO?
    let open: Bool?
    let pullRequests: [PullRequestDTO]?

    struct BaseDTO: Decodable {
        let ref: String?
    }

    struct PullRequestDTO: Decodable {
        let number: Int?
        let state: String?
        let draft: Bool?
        let mergedAt: String?
        let head: HeadDTO?

        struct HeadDTO: Decodable {
            let ref: String?
        }

        enum CodingKeys: String, CodingKey {
            case number, state, draft, head
            case mergedAt = "merged_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case number, base, open
        case pullRequests = "pull_requests"
    }

    func toRemoteStack() -> RemoteStack? {
        // Without a number there is nothing to check out — `gh stack checkout` addresses
        // stacks by number and nothing else.
        guard let number, number > 0 else { return nil }
        let prs = (pullRequests ?? []).compactMap { dto -> RemoteStackPR? in
            guard let prNumber = dto.number else { return nil }
            return RemoteStackPR(
                number: prNumber,
                headRef: dto.head?.ref ?? "",
                state: dto.state ?? "open",
                isDraft: dto.draft ?? false,
                isMerged: dto.mergedAt != nil)
        }
        return RemoteStack(
            number: number, baseRef: base?.ref ?? "", open: open ?? true, pullRequests: prs)
    }
}

extension RemoteStack {
    fileprivate init(number: Int, baseRef: String, open: Bool, pullRequests: [RemoteStackPR]) {
        self.init(number: number, baseRef: baseRef, isOpen: open, pullRequests: pullRequests)
    }
}
