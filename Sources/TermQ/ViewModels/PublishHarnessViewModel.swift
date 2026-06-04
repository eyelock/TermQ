import Foundation
import TermQCore
import TermQShared

/// Orchestrates "Publish to Repository…" — the graduate-a-local-harness
/// flow. Owns all decisions; `PublishHarnessSheet` only renders state.
///
/// Pure decision logic (destination resolution, git-URL matching) lives in
/// static funcs so the clash matrix is unit-testable without a UI or git.
@MainActor
final class PublishHarnessViewModel: ObservableObject {

    /// What publishing into the chosen destination would mean.
    enum DestinationState: Equatable {
        case scanning
        /// Destination is free — publish creates a new entry.
        case newEntry
        /// The repo already has an entry with this name — publishing
        /// updates it in place (at its existing path, shown to the user).
        case updateExisting(relativePath: String)
        /// The destination directory holds a *different* harness.
        case clash(existingName: String)
        /// The destination directory exists but is not a harness.
        case directoryOccupied
        /// The local source is a checkout of the target repo itself —
        /// publishing-by-copy is meaningless; commit there instead.
        case sameRepo
    }

    // MARK: - Inputs

    let harness: Harness
    /// The editable source tree being published.
    let sourcePath: String

    // MARK: - Dependencies

    private let detector: any YNHDetectorProtocol
    private let commandRunner: any YNHCommandRunner
    let worktreeViewModel: WorktreeSidebarViewModel

    // MARK: - Form state

    @Published var selectedRepoID: UUID? {
        didSet { if oldValue != selectedRepoID { Task { await repoSelectionChanged() } } }
    }
    @Published var parentDir: String = "" {
        didSet { if oldValue != parentDir { resolveDestination() } }
    }
    @Published var publishName: String {
        didSet { if oldValue != publishName { resolveDestination() } }
    }
    @Published var branchName: String {
        didSet {
            if oldValue != branchName, let repo = selectedRepo {
                worktreePath = worktreeViewModel.inferWorktreePath(for: repo, branchName: branchName)
            }
        }
    }
    @Published var baseBranch: String = ""
    @Published var worktreePath: String = ""
    @Published var copyMode: HarnessPublishPlan.CopyMode {
        didSet { if oldValue != copyMode { rebuildPlan() } }
    }

    // MARK: - Derived state

    @Published private(set) var scan: RepoHarnessScan?
    @Published private(set) var plan: HarnessPublishPlan?
    @Published private(set) var planError: String?
    @Published private(set) var preflight: YndValidationResult?
    @Published private(set) var destinationState: DestinationState = .scanning
    @Published private(set) var changes: [PublishChange] = []
    @Published private(set) var isPreparing = true

    private var composition: HarnessComposition?

    var selectedRepo: ObservableRepository? {
        worktreeViewModel.repositories.first { $0.id == selectedRepoID }
    }

    /// The harness directory relative to the repo/worktree root the publish
    /// will write to. Updates reuse the existing entry's location.
    var destinationRelativePath: String {
        if case .updateExisting(let relativePath) = destinationState {
            return relativePath
        }
        let trimmedParent = parentDir.trimmingCharacters(in: .whitespaces)
        let name = trimmedName
        guard !trimmedParent.isEmpty, trimmedParent != "." else { return name }
        return "\(trimmedParent)/\(name)"
    }

    var trimmedName: String {
        publishName.trimmingCharacters(in: .whitespaces)
    }

    /// True when a rename was applied relative to the source harness.
    var isRenamed: Bool {
        !trimmedName.isEmpty && trimmedName != harness.name
    }

    var canPublish: Bool {
        guard !trimmedName.isEmpty, selectedRepo != nil, plan != nil,
            !branchName.trimmingCharacters(in: .whitespaces).isEmpty,
            !worktreePath.trimmingCharacters(in: .whitespaces).isEmpty
        else { return false }
        if let preflight, !preflight.isValid { return false }
        switch destinationState {
        case .newEntry, .updateExisting: return true
        case .scanning, .clash, .directoryOccupied, .sameRepo: return false
        }
    }

    // MARK: - Init

    init(
        harness: Harness,
        worktreeViewModel: WorktreeSidebarViewModel,
        detector: any YNHDetectorProtocol = YNHDetector.shared,
        commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()
    ) {
        self.harness = harness
        self.sourcePath = harness.editablePath
        self.worktreeViewModel = worktreeViewModel
        self.detector = detector
        self.commandRunner = commandRunner
        self.publishName = harness.name
        self.branchName = "feat/harness-\(harness.name)"
        self.copyMode = HarnessPublishPlanner.defaultMode(forSourceAt: harness.editablePath)
    }

    // MARK: - Preparation (sheet onAppear)

    func prepare() async {
        isPreparing = true
        defer { isPreparing = false }

        // Both subprocess probes are nonisolated statics so the `async let`
        // children genuinely run concurrently instead of serialising on the
        // main actor.
        let runner = commandRunner
        let ynd = yndPath
        let environment = ynhEnvironment()
        let source = sourcePath
        async let preflightValue = Self.runValidate(
            runner: runner, yndPath: ynd, path: source, environment: environment)
        async let compositionValue = Self.runCompose(
            runner: runner, yndPath: ynd, path: source, environment: environment)
        preflight = await preflightValue
        composition = await compositionValue
        rebuildPlan()

        if selectedRepoID == nil {
            selectedRepoID = await Self.preselectRepo(
                for: harness,
                allHarnesses: HarnessRepository.shared.harnesses,
                repositories: worktreeViewModel.repositories,
                gitService: worktreeViewModel.gitService
            )?.id
        }
        if selectedRepoID == nil { destinationState = .newEntry }
    }

    private func repoSelectionChanged() async {
        guard let repo = selectedRepo else { return }
        destinationState = .scanning
        scan = nil
        changes = []

        // Same-repo detection first — a checkout of the target repo never
        // needs a copy, it needs a commit.
        if await isSameRepo(repo: repo) {
            destinationState = .sameRepo
            return
        }

        let repoPath = repo.path
        let result = await Task.detached(priority: .userInitiated) {
            RepoHarnessScanner.scan(repoPath: repoPath)
        }.value
        scan = result
        if parentDir.isEmpty {
            parentDir = result.suggestedParentDirs.first ?? ""
        }

        baseBranch = await worktreeViewModel.defaultBranch(for: repo)
        worktreePath = worktreeViewModel.inferWorktreePath(for: repo, branchName: branchName)
        resolveDestination()
    }

    /// Re-derive `destinationState` + change preview from the current scan
    /// and form fields.
    func resolveDestination() {
        guard let repo = selectedRepo else { return }
        if destinationState == .sameRepo { return }
        guard let scan else {
            destinationState = .scanning
            return
        }
        destinationState = Self.resolveDestinationState(
            name: trimmedName,
            parentDir: parentDir,
            scan: scan,
            repoPath: repo.path
        )
        rebuildChangePreview()
    }

    private func rebuildChangePreview() {
        changes = []
        guard let plan, let repo = selectedRepo,
            case .updateExisting(let relativePath) = destinationState
        else { return }
        let destination =
            relativePath == "."
            ? repo.path
            : (repo.path as NSString).appendingPathComponent(relativePath)
        let frozen = plan
        Task.detached(priority: .userInitiated) { [weak self] in
            let diff = PublishChangePreview.diff(plan: frozen, destinationPath: destination)
            await MainActor.run { [weak self] in
                self?.changes = diff
            }
        }
    }

    // MARK: - Plan

    /// Run `ynd compose` against a harness path. Nonisolated so callers can
    /// fan it out concurrently. Nil when ynd is missing or the harness does
    /// not compose — callers report the gap (e.g. via `planError`).
    nonisolated private static func runCompose(
        runner: any YNHCommandRunner,
        yndPath: String?,
        path: String,
        environment: [String: String]
    ) async -> HarnessComposition? {
        guard let yndPath else { return nil }
        guard
            let result = try? await runner.run(
                executable: yndPath,
                arguments: ["compose", path],
                environment: environment
            ), result.didSucceed
        else { return nil }
        return try? JSONDecoder().decode(HarnessComposition.self, from: Data(result.stdout.utf8))
    }

    /// Run `ynd validate` against a harness path. Nonisolated for the same
    /// reason as `runCompose`.
    nonisolated private static func runValidate(
        runner: any YNHCommandRunner,
        yndPath: String?,
        path: String,
        environment: [String: String]
    ) async -> YndValidationResult? {
        guard let yndPath else { return nil }
        return try? await YndValidateRunner(commandRunner: runner).validate(
            yndPath: yndPath,
            harnessPath: path,
            environment: environment
        )
    }

    private func rebuildPlan() {
        planError = nil
        do {
            plan = try HarnessPublishPlanner.plan(
                sourcePath: sourcePath,
                harnessName: harness.name,
                composition: composition,
                mode: copyMode
            )
        } catch HarnessPublishPlannerError.compositionRequired {
            plan = nil
            planError = Strings.HarnessPublish.compositionUnavailable
        } catch {
            plan = nil
            planError = error.localizedDescription
        }
        rebuildChangePreview()
    }

    // MARK: - Same-repo detection

    private func isSameRepo(repo: ObservableRepository) async -> Bool {
        // Containment: the source tree lives inside the repo's checkout.
        let repoPrefix = repo.path.hasSuffix("/") ? repo.path : repo.path + "/"
        if sourcePath == repo.path || sourcePath.hasPrefix(repoPrefix) { return true }

        // Remote identity: the source is its own checkout of the same repo.
        guard let sourceRemote = try? await worktreeViewModel.gitService.remoteURL(repoPath: sourcePath),
            let repoRemote = try? await worktreeViewModel.gitService.remoteURL(repoPath: repo.path)
        else { return false }
        guard let lhs = Self.normalizedGitURL(sourceRemote),
            let rhs = Self.normalizedGitURL(repoRemote)
        else { return false }
        return lhs == rhs
    }

    // MARK: - Pure decision logic (unit-tested)

    /// Destination resolution matrix:
    /// - name matches an existing entry → update at *its* path
    /// - chosen directory holds a different harness → clash
    /// - chosen directory exists with unknown content → occupied
    /// - otherwise → new entry
    nonisolated static func resolveDestinationState(
        name: String,
        parentDir: String,
        scan: RepoHarnessScan,
        repoPath: String
    ) -> DestinationState {
        guard !name.isEmpty else { return .newEntry }
        if let existing = scan.entry(named: name) {
            return .updateExisting(relativePath: existing.relativePath)
        }

        let trimmedParent = parentDir.trimmingCharacters(in: .whitespaces)
        let relative = trimmedParent.isEmpty || trimmedParent == "." ? name : "\(trimmedParent)/\(name)"
        if let occupying = scan.entries.first(where: { $0.relativePath == relative }) {
            return .clash(existingName: occupying.name)
        }
        let destination = (repoPath as NSString).appendingPathComponent(relative)
        if FileManager.default.fileExists(atPath: destination) {
            return .directoryOccupied
        }
        return .newEntry
    }

    /// Normalize a git remote URL to `host/owner/repo` for identity
    /// comparison: strips scheme, `git@host:` form, trailing `.git` and `/`.
    nonisolated static func normalizedGitURL(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        for scheme in ["https://", "http://", "ssh://git@", "ssh://", "git://"]
        where value.hasPrefix(scheme) {
            value = String(value.dropFirst(scheme.count))
            break
        }
        if value.hasPrefix("git@"), let colon = value.firstIndex(of: ":") {
            value = value.replacingCharacters(in: colon...colon, with: "/")
            value = String(value.dropFirst("git@".count))
        }
        if value.hasSuffix("/") { value = String(value.dropLast()) }
        if value.hasSuffix(".git") { value = String(value.dropLast(4)) }
        return value.isEmpty ? nil : value
    }

    /// Pick the most likely target repo: the fork origin when recorded,
    /// otherwise the repo matching another install of the same name (the
    /// dual-entry case: `local/x` alongside `github.com/org/repo/x`).
    static func preselectRepo(
        for harness: Harness,
        allHarnesses: [Harness],
        repositories: [ObservableRepository],
        gitService: any GitServiceProtocol
    ) async -> ObservableRepository? {
        var candidateURLs: [String] = []
        if let forkOrigin = harness.installedFrom?.forkedFrom?.source {
            candidateURLs.append(forkOrigin)
        }
        for sibling in allHarnesses
        where sibling.name == harness.name && sibling.id != harness.id {
            if let provenance = sibling.installedFrom,
                provenance.sourceType == "git" || provenance.sourceType == "registry"
            {
                candidateURLs.append(provenance.source)
            }
        }
        guard !candidateURLs.isEmpty else { return nil }
        let normalizedCandidates = candidateURLs.compactMap { normalizedGitURL($0) }

        for repo in repositories {
            guard let remote = try? await gitService.remoteURL(repoPath: repo.path),
                let normalized = normalizedGitURL(remote)
            else { continue }
            if normalizedCandidates.contains(normalized) {
                return repo
            }
        }
        return nil
    }

    // MARK: - Helpers

    func ynhEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = detector.ynhHomeOverride {
            env["YNH_HOME"] = override
        }
        return env
    }

    var yndPath: String? {
        if case .ready(_, let yndPath, _) = detector.status { return yndPath }
        return nil
    }

    // MARK: - Publish execution (progress phase)

    /// Run the full publish sequence, streaming step output into
    /// `runnerState`: worktree → copy → reference check → `ynd validate`
    /// → optional register script → sidebar refresh.
    ///
    /// Returns true on success. Failures keep the worktree for inspection —
    /// it is never auto-deleted.
    func publish(runnerState: CommandSheetState) async -> Bool {
        guard let repo = selectedRepo, let plan else { return false }
        let destinationRelative = destinationRelativePath
        let isUpdate: Bool = {
            if case .updateExisting = destinationState { return true }
            return false
        }()

        runnerState.begin()

        // 1. Worktree.
        runnerState.append(line: Strings.HarnessPublish.stepWorktree(branchName))
        do {
            try await worktreeViewModel.createWorktree(
                repo: repo,
                branchName: branchName,
                baseBranch: baseBranch.isEmpty ? nil : baseBranch,
                path: worktreePath
            )
        } catch {
            return fail(runnerState, error.localizedDescription)
        }

        // Existing entry's own file roots (root/shared update sync),
        // enumerated from the fresh worktree BEFORE the copy overwrites it.
        var existingRoots: [String]?
        if isUpdate {
            existingRoots = await destinationFileRoots(relativePath: destinationRelative)
        }

        // 2. Copy.
        runnerState.append(line: Strings.HarnessPublish.stepCopy(destinationRelative))
        let report: HarnessPublishReport
        do {
            report = try HarnessPublishExecutor.execute(
                plan: plan,
                worktreePath: worktreePath,
                destinationRelativePath: destinationRelative,
                renameTo: isRenamed ? trimmedName : nil,
                isUpdate: isUpdate,
                existingFileRoots: existingRoots
            )
        } catch {
            return fail(runnerState, errorMessage(for: error))
        }
        for warning in report.warnings {
            runnerState.append(line: Strings.HarnessPublish.warningPrefix(warning))
        }
        for deleted in report.deletedPaths {
            runnerState.append(line: Strings.HarnessPublish.deletedLine(deleted))
        }
        runnerState.append(line: Strings.HarnessPublish.stepCopied(report.copiedRoots.count))

        let destinationPath =
            destinationRelative == "."
            ? worktreePath
            : (worktreePath as NSString).appendingPathComponent(destinationRelative)

        // 3. Honesty gate: every manifest-referenced script must exist at
        // the destination. `ynd validate` does not check this (it is
        // schema-shape only), so a fresh gap here means the copy missed a
        // file — stop before anything gets committed. An unreadable
        // destination manifest is itself a failed copy, not a pass.
        let knownGaps = Set(plan.unresolvedReferences)
        do {
            let unresolved = try HarnessPublishPlanner.unresolvedManifestReferences(at: destinationPath)
            let fresh = unresolved.filter { !knownGaps.contains($0) }
            if !fresh.isEmpty {
                return fail(
                    runnerState,
                    Strings.HarnessPublish.referencesMissing(fresh.joined(separator: ", ")))
            }
        } catch {
            return fail(runnerState, errorMessage(for: error))
        }

        // 4. Schema validation in place.
        if let yndPath {
            runnerState.append(line: Strings.HarnessPublish.stepValidate)
            let validation = try? await YndValidateRunner(commandRunner: commandRunner).validate(
                yndPath: yndPath,
                harnessPath: destinationPath,
                environment: ynhEnvironment()
            )
            if let validation, !validation.isValid {
                for finding in validation.findings {
                    runnerState.append(line: Strings.HarnessPublish.warningPrefix(finding))
                }
                return fail(runnerState, Strings.HarnessPublish.validationFailed)
            }
        }

        // 5. Repo-provided registration hook (opt-in by convention).
        if scan?.hasRegisterScript == true {
            let script = (worktreePath as NSString)
                .appendingPathComponent(RepoHarnessScanner.registerScriptPath)
            if FileManager.default.isExecutableFile(atPath: script) {
                runnerState.append(
                    line: Strings.HarnessPublish.stepRegister(RepoHarnessScanner.registerScriptPath))
                do {
                    let result = try await commandRunner.run(
                        executable: script,
                        arguments: [destinationRelative, isUpdate ? "update" : "new"],
                        environment: ynhEnvironment(),
                        currentDirectory: worktreePath,
                        onStdoutLine: { line in
                            Task { @MainActor in runnerState.append(line: line) }
                        },
                        onStderrLine: { line in
                            Task { @MainActor in runnerState.append(line: line) }
                        }
                    )
                    guard result.didSucceed else {
                        return fail(runnerState, Strings.HarnessPublish.registerFailed)
                    }
                } catch {
                    return fail(runnerState, error.localizedDescription)
                }
            }
        }

        // 6. Done — surface the new worktree in the sidebar.
        await worktreeViewModel.refreshWorktrees(for: repo)
        worktreeViewModel.setExpanded(repo.id, expanded: true)
        runnerState.append(line: Strings.HarnessPublish.stepDone(worktreePath))
        runnerState.finish(result: CommandRunner.Result(exitCode: 0, stdout: "", stderr: "", duration: 0))
        return true
    }

    /// The existing entry's enumerated file roots inside the fresh
    /// worktree — `ynd compose` + planner against the destination. Nil
    /// when the destination doesn't compose cleanly (the executor then
    /// skips deletions and warns instead).
    private func destinationFileRoots(relativePath: String) async -> [String]? {
        let destinationPath =
            relativePath == "."
            ? worktreePath
            : (worktreePath as NSString).appendingPathComponent(relativePath)
        guard
            let composition = await Self.runCompose(
                runner: commandRunner,
                yndPath: yndPath,
                path: destinationPath,
                environment: ynhEnvironment()
            )
        else { return nil }
        return try? HarnessPublishPlanner.plan(
            sourcePath: destinationPath,
            harnessName: composition.name,
            composition: composition,
            mode: .enumerated
        ).files
    }

    private func fail(_ runnerState: CommandSheetState, _ message: String) -> Bool {
        runnerState.append(line: message)
        runnerState.finish(
            result: CommandRunner.Result(exitCode: 1, stdout: "", stderr: message, duration: 0))
        return false
    }

    private func errorMessage(for error: Error) -> String {
        switch error {
        case HarnessPublishExecutorError.destinationOccupied(let path):
            return Strings.HarnessPublish.errorDestinationOccupied(path)
        case HarnessPublishExecutorError.invalidDestination(let path):
            return Strings.HarnessPublish.errorInvalidDestination(path)
        case HarnessPublishExecutorError.copyFailed(let detail):
            return Strings.HarnessPublish.errorCopyFailed(detail)
        case HarnessPublishExecutorError.manifestRewriteFailed(let detail):
            return Strings.HarnessPublish.errorRenameFailed(detail)
        case HarnessPublishPlannerError.manifestNotFound(let path):
            return Strings.HarnessPublish.errorCopyFailed(path)
        case HarnessPublishPlannerError.manifestInvalid(let detail):
            return Strings.HarnessPublish.errorCopyFailed(detail)
        default:
            return error.localizedDescription
        }
    }
}
