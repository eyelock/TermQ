import Foundation
import XCTest

@testable import TermQ
@testable import TermQCore
@testable import TermQShared

/// The repo refresh button must never force-push.
///
/// Refreshing a stacked repo runs the provider's sync rather than a plain fetch, because
/// a fetch alone leaves the stack stale after a downstack merge. That is free for
/// git-spice, whose `repo sync` is local-only. gh-stack's force-pushes every branch and
/// rewrites the stack on GitHub — which is exactly why Sync is a confirmed action — so
/// reaching it through a refresh button performed, unasked, the operation the
/// confirmation exists to guard.
///
/// It was not theoretical: refreshing after a merge silently force-pushed and deleted the
/// merged branches, which is how the behaviour was found.
@MainActor
final class RefreshDoesNotForcePushTests: XCTestCase {

    private func makeViewModel(
        stackService: StackService, gitService: MockGitService
    )
        -> WorktreeSidebarViewModel
    {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefreshForcePush-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return WorktreeSidebarViewModel(
            gitService: gitService,
            persistence: MockRepoPersistence(),
            prService: .shared,
            gitConfig: GitConfigStore(
                defaults: UserDefaults(suiteName: "RefreshForcePush.\(UUID().uuidString)")!),
            workspaceStore: WorkspaceStore(fileURL: dir.appendingPathComponent("w.json")),
            stackService: stackService)
    }

    private func mainWorktree(at path: String) -> GitWorktree {
        GitWorktree(
            path: path, branch: "feat-a", commitHash: "abc12345", isMainWorktree: true,
            isLocked: false)
    }

    /// `.syncPushes` marks a sync that reaches the remote — gh-stack's shape.
    func testARefreshDoesNotSyncWhenTheProvidersSyncForcePushes() async throws {
        let provider = FakeStackProvider(
            id: StackProviderID(rawValue: "gh"),
            capabilities: [.restack, .submit, .sync, .syncPushes])
        await provider.setGraph(
            StackGraph(branches: [
                StackBranch(
                    name: "feat-a", isCurrent: true, checkedOutElsewhere: nil, parent: nil,
                    children: [], needsRestack: false, changeRequest: nil, push: nil)
            ]), for: "/repo")

        let service = StackService(registry: StackProviderRegistry(providers: [provider]))
        await service.probe()
        await service.refreshGraph(repo: "/repo")

        let git = MockGitService()
        git.listWorktreesResult = [mainWorktree(at: "/repo")]
        let viewModel = makeViewModel(stackService: service, gitService: git)
        let repo = ObservableRepository(name: "repo", path: "/repo")
        viewModel.worktrees[repo.id] = [mainWorktree(at: "/repo")]

        let report = await viewModel.refreshRepo(for: repo)

        let log = await provider.mutationLog
        XCTAssertFalse(
            log.contains("sync"),
            "a refresh must not run a sync that force-pushes — that is what the Sync "
                + "confirmation exists to guard")
        XCTAssertTrue(git.fetchRemoteCalled, "it should fall back to a plain fetch instead")
        XCTAssertNil(report, "no sync ran, so there is no sync report to show")
    }

    /// The inverse, so the fix cannot be "never sync on refresh": a local-only sync is
    /// still what keeps a git-spice stack from going stale after a downstack merge.
    func testARefreshStillSyncsWhenTheProvidersSyncIsLocalOnly() async throws {
        let provider = FakeStackProvider(
            id: StackProviderID(rawValue: "spice"),
            capabilities: [.restack, .submit, .sync, .scopedRestack, .scopedSubmit])
        await provider.setGraph(
            StackGraph(branches: [
                StackBranch(
                    name: "feat-a", isCurrent: true, checkedOutElsewhere: nil, parent: nil,
                    children: [], needsRestack: false, changeRequest: nil, push: nil)
            ]), for: "/repo")

        let service = StackService(registry: StackProviderRegistry(providers: [provider]))
        await service.probe()
        await service.refreshGraph(repo: "/repo")

        let git = MockGitService()
        git.listWorktreesResult = [mainWorktree(at: "/repo")]
        let viewModel = makeViewModel(stackService: service, gitService: git)
        let repo = ObservableRepository(name: "repo", path: "/repo")
        viewModel.worktrees[repo.id] = [mainWorktree(at: "/repo")]

        _ = await viewModel.refreshRepo(for: repo)

        let log = await provider.mutationLog
        XCTAssertTrue(
            log.contains("sync"),
            "a local-only sync is safe on refresh and is what keeps the stack current")
    }
}
