import Foundation

// MARK: - Provider Identity

/// Identifies a stacked-PR backend (`git-spice`, a future GitHub-native provider, Graphite, …).
public struct StackProviderID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let gitSpice = StackProviderID(rawValue: "git-spice")
}

/// Result of probing a provider for availability. Distinguishes "not installed" from
/// "installed but can't be used" (e.g. wrong binary identity, unsupported version) so the
/// UI can surface a precise message instead of silently doing nothing.
public enum StackProviderAvailability: Sendable, Equatable {
    case missing
    case unusable(reason: String)
    case ready(version: String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Capability flags a provider supports. The UI shows/hides actions per capability rather
/// than hardcoding what a specific provider (e.g. git-spice) can do — a hypothetical
/// GitHub-native provider might support `.submit`/`.sync` but not `.restack`.
public struct StackCapabilities: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let restack = StackCapabilities(rawValue: 1 << 0)
    public static let submit = StackCapabilities(rawValue: 1 << 1)
    public static let sync = StackCapabilities(rawValue: 1 << 2)
    public static let trackExisting = StackCapabilities(rawValue: 1 << 3)
    public static let conflictResume = StackCapabilities(rawValue: 1 << 4)
    /// Provider can create a branch at a position relative to the currently checked-out
    /// branch (not just "on top of an explicit target") — gates "New Stacked Branch
    /// Before…/After…" in the UI.
    public static let branchInsertion = StackCapabilities(rawValue: 1 << 5)
    /// Provider can delete every branch in a stack (up and down) in one operation —
    /// gates "Destroy Stack" in the UI.
    public static let destroyStack = StackCapabilities(rawValue: 1 << 6)
}

/// Where a newly created branch attaches, relative to the branch currently checked out
/// in the target worktree. `.onTop` is the original "create on top of an explicit
/// target" behavior; `.below`/`.above` require `.branchInsertion` support and operate on
/// whatever is checked out at call time (the caller must check it out first).
public enum StackBranchPosition: Sendable, Equatable {
    /// Create stacked on `target` (or the current branch when `target` is nil) —
    /// the original behavior.
    case onTop
    /// Insert below the currently checked-out branch: that branch's parent becomes the
    /// new branch. git-spice: `gs branch create <name> --below`.
    case below
    /// Insert directly above the currently checked-out branch, moving its existing
    /// children onto the new branch. git-spice: `gs branch create <name> --insert`.
    case above
}

// MARK: - Neutral Domain Model

/// A change request (pull request / merge request / whatever the provider calls it)
/// tracked against a stack branch.
public struct StackChangeRequest: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case open
        case closed
        case merged
        case unknown
    }

    /// Provider-assigned identifier (e.g. GitHub PR number as a string). Never parsed
    /// as an integer above the provider boundary — kept opaque for provider portability.
    public let id: String
    public let url: String?
    public let status: Status
    public let commentCount: Int?

    public init(id: String, url: String?, status: Status, commentCount: Int?) {
        self.id = id
        self.url = url
        self.status = status
        self.commentCount = commentCount
    }
}

/// Ahead/behind push state of a stack branch relative to its remote counterpart.
public struct StackPushState: Codable, Sendable, Equatable {
    public let ahead: Int
    public let behind: Int
    public let needsPush: Bool

    public init(ahead: Int, behind: Int, needsPush: Bool) {
        self.ahead = ahead
        self.behind = behind
        self.needsPush = needsPush
    }
}

/// One tracked branch in a stack, in provider-neutral terms.
public struct StackBranch: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }

    public let name: String
    public let isCurrent: Bool
    /// Path of the worktree this branch is checked out in, if it's checked out somewhere
    /// other than the worktree being queried. `nil` when not checked out elsewhere.
    public let checkedOutElsewhere: String?
    /// Name of the branch directly below this one in the stack. `nil` means this branch
    /// is stacked directly on trunk.
    public let parent: String?
    /// Names of branches directly above this one in the stack.
    public let children: [String]
    public let needsRestack: Bool
    public let changeRequest: StackChangeRequest?
    public let push: StackPushState?

    public init(
        name: String,
        isCurrent: Bool,
        checkedOutElsewhere: String?,
        parent: String?,
        children: [String],
        needsRestack: Bool,
        changeRequest: StackChangeRequest?,
        push: StackPushState?
    ) {
        self.name = name
        self.isCurrent = isCurrent
        self.checkedOutElsewhere = checkedOutElsewhere
        self.parent = parent
        self.children = children
        self.needsRestack = needsRestack
        self.changeRequest = changeRequest
        self.push = push
    }
}

/// The full set of tracked branches for a repository, as reported by a `StackProvider`.
public struct StackGraph: Codable, Sendable, Equatable {
    public let branches: [StackBranch]

    public init(branches: [StackBranch]) {
        self.branches = branches
    }

    public func branch(named name: String) -> StackBranch? {
        branches.first { $0.name == name }
    }

    /// Whether `name` is the trunk. `gs log` includes the trunk in its output as the
    /// only entry without a `down` edge, so "tracked and parentless" identifies it.
    /// The trunk is a fan-out point — multiple stacks can hang off it — and is NEVER a
    /// member of any chain or group.
    public func isTrunk(_ name: String) -> Bool {
        guard let branch = branch(named: name) else { return false }
        return branch.parent == nil
    }

    /// Whether `name` participates in a stack: its chain has at least two branches.
    /// False for the trunk (never a member), for untracked branches, and for a lone
    /// tracked branch sitting directly on trunk with nothing above it.
    public func isStacked(_ name: String) -> Bool {
        chain(containing: name).count > 1
    }

    /// Walk down from `name` to the bottom of its stack — the last NON-TRUNK branch
    /// (its parent is the trunk, or missing from the graph). Returns `nil` for the
    /// trunk itself and for untracked branches.
    public func rootBranch(for name: String) -> StackBranch? {
        guard let start = branch(named: name), start.parent != nil else { return nil }
        var current = start
        var seen = Set<String>()
        while let parentName = current.parent, !seen.contains(current.name) {
            seen.insert(current.name)
            guard let parent = branch(named: parentName), parent.parent != nil else {
                break  // parent is the trunk (or unknown) — current is the stack bottom
            }
            current = parent
        }
        return current
    }

    /// The bottom branch of every tracked stack in the graph: non-trunk branches
    /// sitting directly on trunk (or an unknown parent). A lone tracked branch with
    /// nothing above it is still a stack (a one-entry one, e.g. "New Stack…" or the
    /// New Worktree sheet's "Start a stack" checkbox) and IS included — gs tracks it,
    /// and it's a legitimate, addressable stack. A trunk with multiple `ups` yields one
    /// root per stack.
    public var stackRoots: [StackBranch] {
        branches.filter { branch in
            branch.parent != nil && rootBranch(for: branch.name)?.name == branch.name
        }
    }

    /// Pre-order flattened chain for the stack containing `name`: the bottom-most
    /// NON-TRUNK branch first, then each branch's first child recursively. The trunk is
    /// never included; asking for the trunk returns `[]` (it belongs to no single
    /// stack). Branching stacks show one path per call — sufficient for the "guarded,
    /// one active branch" v1 model.
    public func chain(containing name: String) -> [StackBranch] {
        guard let root = rootBranch(for: name) else { return [] }
        var result: [StackBranch] = []
        var current: StackBranch? = root
        var seen = Set<String>()
        while let branch = current, !seen.contains(branch.name) {
            seen.insert(branch.name)
            result.append(branch)
            current = branch.children.first.flatMap { self.branch(named: $0) }
        }
        return result
    }
}

// MARK: - Mutation Support Types

/// Which part of the stack a mutation (restack, submit) applies to.
public enum StackScope: Sendable, Equatable {
    /// A single named branch.
    case branch(String)
    /// A branch and everything stacked above it. `nil` means the current branch.
    case upstack(from: String?)
    /// The entire stack containing the current branch.
    case stack
}

/// Options for a submit (create/update change requests) operation.
public struct StackSubmitOptions: Sendable, Equatable {
    public var draft: Bool
    public var updateOnly: Bool

    public init(draft: Bool = false, updateOnly: Bool = false) {
        self.draft = draft
        self.updateOnly = updateOnly
    }
}

/// A provider operation (restack, sync) paused mid-flight due to a conflict, awaiting
/// the user to resolve files and call `continueOperation` or `abortOperation`.
public struct StackPausedOperation: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case restack
        case sync
    }

    public let kind: Kind
    public let conflictedFiles: [String]

    public init(kind: Kind, conflictedFiles: [String]) {
        self.kind = kind
        self.conflictedFiles = conflictedFiles
    }
}

// MARK: - Errors

public enum StackProviderError: Error, LocalizedError, Sendable {
    case binaryMissing
    case notInitialized(repo: String)
    case commandFailed(command: String, exitCode: Int32, output: String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "No stacked-PR provider is installed."
        case .notInitialized(let repo):
            return "Stacking is not enabled for \(repo)."
        case .commandFailed(let command, let exitCode, let output):
            return "\(command) failed (exit \(exitCode)): \(output)"
        case .decodingFailed(let detail):
            return "Failed to decode stack data: \(detail)"
        }
    }
}

// MARK: - Provider Protocol

/// A backend that implements stacked-branch/PR support (git-spice first, potentially
/// GitHub-native or Graphite later). Everything above this protocol — UI, view models,
/// MCP tools — speaks only the neutral types declared in this file. No provider-specific
/// strings or JSON shapes leak upward; each provider owns its own binary/API detection,
/// command construction, output parsing, and mapping of its failure modes onto the
/// neutral error/conflict states.
public protocol StackProvider: Sendable {
    static var id: StackProviderID { get }
    var capabilities: StackCapabilities { get }

    /// Detect whether this provider's backend is installed and usable. Safe to call
    /// repeatedly (e.g. app launch, "re-check" button, MCP tool invocation).
    func probe() async -> StackProviderAvailability

    /// Whether stacking has been enabled for `repo` (e.g. `gs repo init` has run).
    func isInitialized(repo: String) async -> Bool

    /// Enable stacking for `repo` against `trunk` as the base branch.
    func initialize(repo: String, trunk: String) async throws

    /// Fetch the current stack graph for `repo`.
    func graph(repo: String) async throws -> StackGraph

    func createBranch(name: String, target: String?, in worktree: String) async throws
    /// Create a branch at `position` relative to whatever is currently checked out in
    /// `worktree`. Only meaningful when `capabilities` contains `.branchInsertion`;
    /// providers without it can fall back to the `.onTop` behavior of the 3-arg
    /// overload (see the protocol extension default).
    func createBranch(
        name: String, target: String?, position: StackBranchPosition, in worktree: String
    ) async throws
    func trackBranch(_ name: String, base: String, in worktree: String) async throws
    func switchBranch(to name: String, in worktree: String) async throws
    func restack(scope: StackScope, in worktree: String) async throws
    func submit(scope: StackScope, options: StackSubmitOptions, in worktree: String) async throws
    func sync(repo: String) async throws
    func continueOperation(in worktree: String) async throws
    func abortOperation(in worktree: String) async throws
    func pausedOperation(repo: String) async -> StackPausedOperation?
    /// Delete every branch in the stack containing whatever is checked out in
    /// `worktree` — both upstack and downstack from it. Only meaningful when
    /// `capabilities` contains `.destroyStack`.
    func destroyStack(in worktree: String) async throws
}

// MARK: - Default Implementations

extension StackProvider {
    /// Providers that don't advertise `.branchInsertion` fall back to `.onTop`,
    /// ignoring `position` — the UI gates Before/After on the capability, so this only
    /// runs for providers that never receive a non-`.onTop` position.
    public func createBranch(
        name: String, target: String?, position: StackBranchPosition, in worktree: String
    ) async throws {
        try await createBranch(name: name, target: target, in: worktree)
    }
}

// MARK: - Provider Registry

/// Probes known providers in preference order and returns the first one that's ready.
/// v1 registers only `GitSpiceStackProvider`, but nothing outside the registry knows
/// the count — adding a second provider later is invisible to callers.
public struct StackProviderRegistry: Sendable {
    public static let shared = StackProviderRegistry()

    private let providers: [any StackProvider]

    public init(providers: [any StackProvider] = [GitSpiceStackProvider()]) {
        self.providers = providers
    }

    /// Probe providers in order; return the first that reports `.ready` along with its
    /// availability. Returns `nil` when no provider is usable.
    public func resolveProvider() async -> (any StackProvider, StackProviderAvailability)? {
        for provider in providers {
            let availability = await provider.probe()
            if case .ready = availability {
                return (provider, availability)
            }
        }
        return nil
    }
}
