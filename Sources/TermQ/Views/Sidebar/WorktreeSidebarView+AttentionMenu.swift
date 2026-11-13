import AppKit
import SwiftUI
import TermQCore
import TermQShared

// MARK: - Attention Tab Menus

/// Context menus for the Attention tab's review requests.
///
/// A pull request in one of TermQ's repositories gets the Remote tab's menu
/// (`prContextMenu`). Any other gets a review checkout from a hidden clone
/// (`ReviewCloneService`), so a harness can open on the PR's code, plus a way
/// to add the repository to TermQ and check the PR out properly.
extension WorktreeSidebarView {
    @ViewBuilder
    func attentionMenu(_ request: ReviewRequest) -> some View {
        if let path = reviewRequests.termqRepositoryPath(for: request.repository),
            let repo = viewModel.repositories.first(where: { $0.path == path })
        {
            if let pr = prService.prsByRepo[path]?.first(where: { $0.number == request.number }) {
                let matches = GitHubPRService.matchPRsToWorktrees(
                    prs: [pr], worktrees: viewModel.worktrees[repo.id] ?? [], stackGraph: viewModel.stacks[repo.id])
                prContextMenu(pr, repo: repo, worktreePath: matches[pr.number])
            } else {
                // The repository's PR list hasn't loaded (or this PR is past its limit).
                Text(Strings.Actions.loadingPR).foregroundColor(.secondary)
                attentionLinkItems(request)
            }
        } else {
            otherRepositoryMenu(request)
        }
    }

    /// The request the selected terminal is working on, to highlight it.
    var focusedAttentionRequestId: String? {
        guard let directory = boardVM.selectedCard?.workingDirectory else { return nil }
        return ReviewRequests.request(
            workingIn: directory, among: reviewRequests.requests, folders: attentionFolders
        )?.id
    }

    /// The folders on disk holding `request`'s code: its worktree in one of
    /// TermQ's repositories, or its review checkout.
    private func attentionFolders(_ request: ReviewRequest) -> [String] {
        var folders: [String] = []
        if let review = reviewClones.checkout(for: request) { folders.append(review.path) }
        if let path = reviewRequests.termqRepositoryPath(for: request.repository),
            let repo = viewModel.repositories.first(where: { $0.path == path }),
            let pr = prService.prsByRepo[path]?.first(where: { $0.number == request.number })
        {
            let matches = GitHubPRService.matchPRsToWorktrees(
                prs: [pr], worktrees: viewModel.worktrees[repo.id] ?? [], stackGraph: viewModel.stacks[repo.id])
            // Not the main checkout: other worktrees can live inside it, and a
            // terminal in one of those is not on the main checkout's PR.
            if let worktree = matches[pr.number], worktree != repo.path { folders.append(worktree) }
        }
        return folders
    }

    /// Loads what the menus need and tidies review checkouts. Runs inside the
    /// Attention view's `.task`, so a newer change cancels it.
    func attentionRequestsChanged(_ requests: [ReviewRequest]) async {
        let paths = Set(requests.compactMap { reviewRequests.termqRepositoryPath(for: $0.repository) })
        for path in paths {
            guard !Task.isCancelled else { return }
            await prService.refresh(repoPath: path)
        }
        guard !Task.isCancelled else { return }
        await reviewClones.refresh(
            openRequests: requests, ghPath: readyGhPath,
            cardDirectories: { boardVM.board.activeCards.map(\.workingDirectory) })
    }

    // MARK: Other repositories

    @ViewBuilder
    private func otherRepositoryMenu(_ request: ReviewRequest) -> some View {
        let review = reviewClones.checkout(for: request)
        let clonePath = reviewClones.clonePath(for: request.repository)
        let harnessId = ynhPersistence.runHarness(for: clonePath)
        let focuses =
            harnessId.flatMap { harnessRepository.cachedDetail(for: $0)?.composition.focuses }
            .map { $0.keys.sorted() } ?? []
        let ghPath = readyGhPath

        if review != nil || ghPath != nil {
            // A harness is remembered per repository once Launch… has used it.
            LaunchMenuItems(
                name: harnessId.map(harnessDisplayName),
                openSheet: { Task { await reviewInHarness(request, quickLaunch: nil) } },
                focuses: harnessId.map { harnessId in
                    focuses.map { focusName in
                        LaunchMenuItems.Focus(name: focusName) {
                            Task { await reviewInHarness(request, quickLaunch: (focusName, harnessId)) }
                        }
                    }
                } ?? [])
            Divider()
        }

        if let review {
            Button {
                boardVM.newTerminal(at: review.path, branch: nil, repoName: request.repository)
            } label: {
                Label(Strings.Sidebar.newTerminal, systemImage: LaunchMenuIcon.quickTerminal)
            }
            Button {
                boardVM.addTerminal(workingDirectory: review.path, branch: nil, repoName: request.repository)
            } label: {
                Label(Strings.Sidebar.createTerminal, systemImage: LaunchMenuIcon.newTerminal)
            }
            Divider()
            worktreeRevealMenuItems(review)
            Divider()
        }

        attentionLinkItems(request)

        if let ghPath {
            Divider()
            Button {
                Task { await addRepositoryAndCheckout(request, ghPath: ghPath) }
            } label: {
                Label(Strings.Actions.checkoutAddingRepository, systemImage: "square.and.arrow.down")
            }
        }
        if let review {
            Button(role: .destructive) {
                Task { await removeOtherReviewCheckout(review, request: request) }
            } label: {
                Label(Strings.RemotePRs.removeReviewCheckout, systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func attentionLinkItems(_ request: ReviewRequest) -> some View {
        Button {
            if let url = URL(string: request.url) { NSWorkspace.shared.open(url) }
        } label: {
            Label(Strings.RemotePRs.openPROnRemote, systemImage: "network")
        }
        Button {
            PathActions.copyPathname(request.url)
        } label: {
            Label(Strings.RemotePRs.copyPRURL, systemImage: "doc.on.clipboard")
        }
    }

    // MARK: Actions

    /// Make (or reuse) the review checkout, then open the Run with Focus sheet, or
    /// launch a focus straight away.
    private func reviewInHarness(_ request: ReviewRequest, quickLaunch: (focus: String, harnessId: String)?) async {
        do {
            let review: GitWorktree
            if let existing = reviewClones.checkout(for: request) {
                review = existing
            } else {
                guard let ghPath = readyGhPath else { return }
                review = try await reviewClones.checkout(request, ghPath: ghPath)
            }
            let clonePath = reviewClones.clonePath(for: request.repository)
            if let quickLaunch {
                quickLaunchFocus(
                    quickLaunch.focus, worktree: review,
                    repo: ObservableRepository(name: request.repository, path: clonePath),
                    prNumber: request.number, harnessId: quickLaunch.harnessId)
            } else {
                runWithFocusContext = RunWithFocusContext(
                    reviewCheckout: review, clonePath: clonePath, prNumber: request.number)
            }
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    /// Clone the repository where the user chooses, add it to TermQ, then check the PR
    /// out as a worktree. A review checkout from the hidden clone stays until its PR
    /// closes; its changes live in a different clone, so they aren't carried across.
    private func addRepositoryAndCheckout(_ request: ReviewRequest, ghPath: String) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = Strings.Actions.cloneHere
        panel.message = Strings.Actions.chooseCloneFolder(request.repository)
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let name = String(request.repository.split(separator: "/").last ?? Substring(request.repository))
        let path = parent.appendingPathComponent(name).path
        do {
            if FileManager.default.fileExists(atPath: path) {
                // Only reuse a folder that is a clone of this very repository.
                let origin = try? await GitServiceShared.runGitCommand(
                    repoPath: path, args: ["remote", "get-url", "origin"])
                guard
                    origin.flatMap(ReviewRequests.nameWithOwner(fromRemote:))?.lowercased()
                        == request.repository.lowercased()
                else {
                    throw GitHubPRError.commandFailed(Strings.Actions.folderIsNotRepository(path, request.repository))
                }
            } else {
                let result = try await CommandRunner.run(
                    executable: ghPath, arguments: ["repo", "clone", request.repository, path, "--", "--quiet"],
                    currentDirectory: parent.path)
                guard result.didSucceed else {
                    throw GitHubPRError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            if !viewModel.repositories.contains(where: { $0.path == path }) {
                try await viewModel.addRepository(path: path)
            }
            guard let repo = viewModel.repositories.first(where: { $0.path == path }) else { return }
            reviewRequests.updateTermQRepositories(paths: viewModel.repositories.map(\.path))
            await prService.refresh(repoPath: path, force: true)
            guard let pr = prService.prsByRepo[path]?.first(where: { $0.number == request.number }) else {
                throw GitHubPRError.commandFailed(Strings.Actions.prNotFound(request.number))
            }
            await checkoutPRFromRemote(pr, repo: repo, ghPath: ghPath)
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    private func removeOtherReviewCheckout(_ review: GitWorktree, request: ReviewRequest) async {
        let name = URL(fileURLWithPath: review.path).lastPathComponent
        let directories = boardVM.board.activeCards.map(\.workingDirectory)
        guard !ReviewCheckouts.hasOpenTerminal(at: review.path, cardDirectories: directories) else {
            viewModel.operationError = Strings.RemotePRs.reviewKeptInUse(name)
            return
        }
        let dirty = await GitServiceShared.isWorktreeDirty(worktreePath: review.path)
        // Without the PR's head from gh, any commit counts as the user's own.
        var prHead: String?
        if let ghPath = readyGhPath {
            prHead = await ReviewCloneService.prState(
                repository: request.repository, number: request.number, ghPath: ghPath)?.headOid
        }
        let committed = await WorktreeSidebarViewModel.hasLocalCommits(
            worktreePath: review.path, prHeadOid: prHead ?? "")
        if dirty || committed {
            guard
                AlertBuilder.confirm(
                    title: Strings.RemotePRs.removeReviewCheckoutTitle,
                    message: Strings.RemotePRs.removeReviewCheckoutDirty,
                    confirmButton: Strings.RemotePRs.pruneRemove,
                    cancelButton: Strings.Common.cancel)
            else { return }
        }
        do {
            try await reviewClones.remove(review, repository: request.repository)
        } catch {
            viewModel.operationError = Strings.RemotePRs.pruneFailed(name)
        }
    }
}
