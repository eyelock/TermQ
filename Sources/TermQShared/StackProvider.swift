import Foundation

// MARK: - Provider Identity

/// Identifies a stacked-PR backend (`git-spice`, a future GitHub-native provider, Graphite, …).
public struct StackProviderID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let gitSpice = StackProviderID(rawValue: "git-spice")
    /// GitHub-native stacked PRs, via the `github/gh-stack` extension for the `gh` CLI.
    public static let gitHub = StackProviderID(rawValue: "github")
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
    /// gates "Destroy Stack" in the UI. DESTRUCTIVE: branches are deleted.
    public static let destroyStack = StackCapabilities(rawValue: 1 << 6)
    /// Provider can drop a stack from tracking WITHOUT deleting its branches — gates
    /// "Untrack Stack". Deliberately distinct from `.destroyStack`: gh-stack's
    /// `unstack --local` leaves every branch in place, where git-spice's
    /// `stack delete` removes them. Same-looking action, opposite blast radius.
    public static let untrackStack = StackCapabilities(rawValue: 1 << 7)
    /// Provider can merge every change request in a stack as one all-or-nothing
    /// operation (gh-stack `merge`). No git-spice equivalent.
    public static let mergeStack = StackCapabilities(rawValue: 1 << 8)
    /// Provider can discover and check out stacks that exist only on the remote
    /// (gh-stack `checkout <stack-number>`). No git-spice equivalent.
    public static let remoteDiscovery = StackCapabilities(rawValue: 1 << 9)
    /// Provider can adopt pre-existing change requests into a stack (gh-stack `link`).
    /// No git-spice equivalent.
    public static let linkExisting = StackCapabilities(rawValue: 1 << 10)
    /// `sync` also pushes to the remote and mutates remote state, rather than being a
    /// local-only reconcile. Providers advertising this MUST have their sync action
    /// confirmed by the user first — gh-stack's `sync` force-pushes every branch and
    /// creates/updates the stack object on GitHub, where `gs repo sync` touches nothing
    /// remote. Without this flag a one-click "Sync" would silently force-push.
    public static let syncPushes = StackCapabilities(rawValue: 1 << 11)
    /// `restack` can target a NAMED branch rather than only the one checked out in the
    /// worktree it runs in — gates "Restack from Here" and the cross-worktree restack
    /// sweep, both of which name a branch other than the caller's own.
    ///
    /// git-spice takes `--branch=NAME` on every restack form. gh-stack's `rebase` always
    /// pivots on the checked-out branch: its positional argument only picks WHICH STACK
    /// to load, and `--upstack`/`--downstack` are still measured from `HEAD`. Passing a
    /// branch name there would rebase a different range than the caller asked for, which
    /// is worse than not offering the action at all.
    public static let scopedRestack = StackCapabilities(rawValue: 1 << 12)
    /// `submit` can target part of a stack (one branch, or a branch and everything above
    /// it) rather than all of it — gates the per-branch Submit action.
    ///
    /// git-spice has `branch`/`upstack`/`stack submit`. gh-stack has a single `submit`
    /// that always covers the whole stack, with no scoping flag.
    public static let scopedSubmit = StackCapabilities(rawValue: 1 << 13)
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
    /// Branch's change request is sitting in a merge queue. Restructuring operations
    /// must refuse to touch it. Only providers with merge-queue awareness report this
    /// (git-spice has no notion of it and always reports `false`).
    public let isQueued: Bool

    /// `isQueued` is last and defaulted so providers that can't report merge-queue
    /// state — and every existing call site — stay source-compatible.
    public init(
        name: String,
        isCurrent: Bool,
        checkedOutElsewhere: String?,
        parent: String?,
        children: [String],
        needsRestack: Bool,
        changeRequest: StackChangeRequest?,
        push: StackPushState?,
        isQueued: Bool = false
    ) {
        self.name = name
        self.isCurrent = isCurrent
        self.checkedOutElsewhere = checkedOutElsewhere
        self.parent = parent
        self.children = children
        self.needsRestack = needsRestack
        self.changeRequest = changeRequest
        self.push = push
        self.isQueued = isQueued
    }

    /// Hand-rolled to keep `isQueued` optional on the wire: `StackGraph` is encoded into
    /// MCP tool responses, and a payload produced before this field existed must still
    /// decode. The rest matches what the compiler would synthesize.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        isCurrent = try container.decode(Bool.self, forKey: .isCurrent)
        checkedOutElsewhere = try container.decodeIfPresent(String.self, forKey: .checkedOutElsewhere)
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        children = try container.decodeIfPresent([String].self, forKey: .children) ?? []
        needsRestack = try container.decode(Bool.self, forKey: .needsRestack)
        changeRequest = try container.decodeIfPresent(StackChangeRequest.self, forKey: .changeRequest)
        push = try container.decodeIfPresent(StackPushState.self, forKey: .push)
        isQueued = try container.decodeIfPresent(Bool.self, forKey: .isQueued) ?? false
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
    /// The active provider has no equivalent for the requested operation. Callers should
    /// be gating on `capabilities` — this is the backstop for when they don't.
    case unsupported(operation: String)
    /// The operation is supported, but the repository/worktree is not in a state the
    /// provider can act on (e.g. gh-stack can only add a branch at the top of a stack).
    /// Distinct from `.unsupported`: the user can fix this and retry, so the message is
    /// surfaced verbatim and should say what to do.
    case preconditionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "No stacked-PR provider is installed."
        case .notInitialized(let repo):
            return "Stacking is not enabled for \(repo)."
        case .unsupported(let operation):
            return "This stacked-PR provider does not support \(operation)."
        case .preconditionFailed(let detail):
            return detail
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
    /// This provider's identity, reachable from an `any StackProvider` existential.
    ///
    /// A protocol REQUIREMENT rather than extension-only sugar, deliberately: members
    /// that exist solely in a protocol extension are statically dispatched, so a call
    /// through an existential would always run the extension's body and ignore any
    /// conforming type's override. The registry keys dictionaries on this, so that
    /// silently collapses distinct providers onto one key. The default below still gives
    /// every provider `Self.id` for free.
    var providerID: StackProviderID { get }
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

    /// Fetch the stack graph for `repo`, given every worktree the app knows about.
    ///
    /// Providers whose state is repo-wide (git-spice keeps it in `refs/spice/data`, and
    /// `gs log --all` reads the lot in one call) ignore `worktrees` entirely and inherit
    /// the default below.
    ///
    /// Providers whose state is PER-WORKTREE need the list. gh-stack writes its tracking
    /// file to `git rev-parse --git-dir`, which inside a linked worktree is
    /// `.git/worktrees/<name>/` — so each worktree carries its own independent stack, and
    /// there is no repo-wide read to fall back on. Such a provider fans out across
    /// `worktrees`, unions the results into one repo-level `StackGraph`, and derives
    /// `checkedOutElsewhere` from which worktree each branch turned up in.
    ///
    /// `worktrees` is a hint, not a contract: an empty array must still produce whatever
    /// the provider can see from `repo` alone.
    func graph(repo: String, worktrees: [String]) async throws -> StackGraph

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
    /// Sync from inside a specific worktree.
    ///
    /// Providers with repo-wide state reconcile the whole repository regardless of the
    /// working directory and inherit the default below, which drops `worktree`.
    ///
    /// gh-stack's `sync` operates on THE STACK CONTAINING THE CHECKED-OUT BRANCH, and its
    /// tracking file lives in the worktree's own git dir — run from the wrong directory it
    /// either syncs a different stack or reports "not in a stack". Such a provider must
    /// override this and use `worktree` as the working directory.
    func sync(repo: String, worktree: String) async throws
    func continueOperation(in worktree: String) async throws
    func abortOperation(in worktree: String) async throws
    func pausedOperation(repo: String) async -> StackPausedOperation?
    /// Delete every branch in the stack containing whatever is checked out in
    /// `worktree` — both upstack and downstack from it. Only meaningful when
    /// `capabilities` contains `.destroyStack`.
    func destroyStack(in worktree: String) async throws

    /// Drop the stack containing whatever is checked out in `worktree` from tracking,
    /// LEAVING EVERY BRANCH IN PLACE. Only meaningful when `capabilities` contains
    /// `.untrackStack`. Not a synonym for `destroyStack` — that one deletes branches.
    func untrackStack(in worktree: String) async throws
}

// MARK: - Default Implementations

extension StackProvider {
    /// Satisfies the `providerID` requirement from the type's own `static id`.
    public var providerID: StackProviderID { Self.id }

    /// Providers that don't advertise `.branchInsertion` fall back to `.onTop`,
    /// ignoring `position` — the UI gates Before/After on the capability, so this only
    /// runs for providers that never receive a non-`.onTop` position.
    public func createBranch(
        name: String, target: String?, position: StackBranchPosition, in worktree: String
    ) async throws {
        try await createBranch(name: name, target: target, in: worktree)
    }

    /// Repo-wide providers ignore the worktree list. Only a provider with per-worktree
    /// state needs to override this.
    public func graph(repo: String, worktrees: [String]) async throws -> StackGraph {
        try await graph(repo: repo)
    }

    /// Repo-wide providers reconcile the same state from anywhere, so the working
    /// directory is irrelevant. Only a provider whose sync is scoped to the checked-out
    /// stack needs to override this.
    public func sync(repo: String, worktree: String) async throws {
        try await sync(repo: repo)
    }

    /// Untracking is opt-in via `.untrackStack`; the default refuses rather than
    /// silently doing something adjacent (and destructive).
    public func untrackStack(in worktree: String) async throws {
        throw StackProviderError.unsupported(operation: "untracking a stack")
    }
}

// MARK: - Provider Registry

/// Probes known providers and decides which one owns a given repository.
///
/// ## Why resolution is per-repo, not global
///
/// Two providers can be installed at once, and they track entirely separate repos. A
/// global "first ready wins" would hand every repo to whichever provider probes first,
/// so a repo stacked with the *other* tool reports "not stacked" — and because an
/// uninitialized repo is a deliberately silent state, it would do so without a single
/// warning. Resolution therefore keys off per-repo INITIALIZATION EVIDENCE (git-spice's
/// `refs/spice/data`, gh-stack's tracking file) and only falls back to preference order
/// for a repo that no provider has claimed yet.
public struct StackProviderRegistry: Sendable {
    public static let shared = StackProviderRegistry()

    private let providers: [any StackProvider]

    /// Order is preference order, used only to break ties for repos with no
    /// initialization evidence. git-spice stays first so existing installs are
    /// unaffected by gh-stack appearing on the machine.
    public init(
        providers: [any StackProvider] = [GitSpiceStackProvider(), GitHubStackProvider()]
    ) {
        self.providers = providers
    }

    /// Every registered provider that probes `.ready`, in preference order.
    public func readyProviders() async -> [(any StackProvider, StackProviderAvailability)] {
        var result: [(any StackProvider, StackProviderAvailability)] = []
        for provider in providers {
            let availability = await provider.probe()
            if case .ready = availability {
                result.append((provider, availability))
            }
        }
        return result
    }

    /// Availability of every registered provider, whether ready or not — the Settings
    /// tab needs the `.missing`/`.unusable` cases to explain themselves.
    public func probeAll() async -> [StackProviderID: StackProviderAvailability] {
        var result: [StackProviderID: StackProviderAvailability] = [:]
        for provider in providers {
            result[provider.providerID] = await provider.probe()
        }
        return result
    }

    /// The first ready provider, irrespective of repo. Answers "is stacking available at
    /// all" — use `resolveProvider(forRepo:preferred:)` for anything repo-specific.
    public func resolveProvider() async -> (any StackProvider, StackProviderAvailability)? {
        await readyProviders().first
    }

    /// The provider that owns `repo`.
    ///
    /// 1. Exactly one ready provider reports the repo initialized → that one, always.
    ///    Evidence beats preference: a repo already stacked with tool A must not be
    ///    driven by tool B just because B is preferred.
    /// 2. More than one claims it (both tools initialized in the same repo) → `preferred`
    ///    if it's among the claimants, else registry order.
    /// 3. Nobody claims it → the caller is about to *enable* stacking, so `preferred`
    ///    wins, else registry order.
    ///
    /// Returns `nil` only when no provider is ready at all.
    public func resolveProvider(
        forRepo repo: String, preferred: StackProviderID? = nil
    ) async -> (any StackProvider, StackProviderAvailability)? {
        let ready = await readyProviders()
        guard !ready.isEmpty else { return nil }

        var claimants: [(any StackProvider, StackProviderAvailability)] = []
        for entry in ready where await entry.0.isInitialized(repo: repo) {
            claimants.append(entry)
        }

        let candidates = claimants.isEmpty ? ready : claimants
        if let preferred, let match = candidates.first(where: { $0.0.providerID == preferred }) {
            return match
        }
        return candidates.first
    }

    /// Providers that consider `repo` initialized. More than one means the repo carries
    /// both tools' metadata — worth surfacing, since only one of them is driving.
    public func claimants(forRepo repo: String) async -> [StackProviderID] {
        var result: [StackProviderID] = []
        for (provider, _) in await readyProviders() where await provider.isInitialized(repo: repo) {
            result.append(provider.providerID)
        }
        return result
    }
}
