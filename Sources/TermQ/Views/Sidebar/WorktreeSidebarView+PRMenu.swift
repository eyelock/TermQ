import AppKit
import SwiftUI
import TermQCore
import TermQShared

// MARK: - Pull Request Context Menu

/// The context menu for a pull request of a TermQ repository, shared by the
/// Remote tab and the Attention tab so the two can't drift.
///
/// The PR's folder on disk is its worktree when it is checked out, else its
/// review checkout when there is one. The folder gets the same terminal and
/// reveal/open-in items as a Local-tab worktree.
extension WorktreeSidebarView {
    @ViewBuilder
    func prContextMenu(_ pr: GitHubPR, repo: ObservableRepository, worktreePath: String?) -> some View {
        let worktree = worktreePath.flatMap { path in
            (viewModel.worktrees[repo.id] ?? []).first(where: { $0.path == path })
        }
        let review = worktree == nil ? viewModel.reviewCheckout(forPR: pr.number, repo: repo) : nil
        let folder = worktree ?? review

        if folder != nil || readyGhPath != nil {
            prHarnessItems(pr, repo: repo, folder: folder)
            Divider()
        }

        if let folder {
            prFolderItems(folder, repo: repo)
            // A review checkout has no branch of its own to copy.
            if worktree != nil {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pr.headRefName, forType: .string)
                } label: {
                    Label(Strings.RemotePRs.copyBranchName, systemImage: "doc.on.clipboard")
                }
            }
            Divider()
        }

        prRemoteItems(pr, repo: repo, worktree: worktree)
        Divider()

        if worktree != nil {
            Button {
                sidebarMode = .local
            } label: {
                Label(Strings.RemotePRs.showInLocal, systemImage: "arrow.turn.up.left")
            }
        } else {
            prCheckoutItems(pr, repo: repo, review: review)
        }

        let focuses = cachedFocuses(for: repo)
        if !focuses.isEmpty {
            Divider()
            prFocusDefaultItems(for: repo, focuses: focuses)
        }
    }

    /// The harness the PR menus launch: the repository's run harness, else its default.
    func prHarnessId(for repo: ObservableRepository) -> String? {
        ynhPersistence.runHarness(for: repo.path) ?? ynhPersistence.repoDefaultHarness(for: repo.path)
    }

    /// gh's path, only when it is signed in: the old menu offered checkouts only then.
    var readyGhPath: String? {
        if case .ready(let ghPath, _) = ghProbe.status { return ghPath }
        return nil
    }

    func cachedFocuses(for repo: ObservableRepository) -> [String] {
        prHarnessId(for: repo).flatMap { id in
            harnessRepository.cachedDetail(for: id)?.composition.focuses
        }.map { $0.keys.sorted() } ?? []
    }

    // MARK: Groups

    /// Run with Focus… and Quick Launch Focus ▸. With nothing on disk, both make a
    /// review checkout first.
    @ViewBuilder
    private func prHarnessItems(_ pr: GitHubPR, repo: ObservableRepository, folder: GitWorktree?) -> some View {
        let harnessId = prHarnessId(for: repo)
        let focuses = cachedFocuses(for: repo)
        let ghPath = readyGhPath

        if let folder {
            Button {
                runWithFocusContext = RunWithFocusContext(worktree: folder, repo: repo, prNumber: pr.number)
            } label: {
                Label(Strings.RemotePRs.runWithFocus, systemImage: "eye")
            }
        } else if let ghPath {
            Button {
                Task { await checkoutAndRunFocus(pr, repo: repo, ghPath: ghPath) }
            } label: {
                Label(Strings.RemotePRs.runWithFocus, systemImage: "eye")
            }
        }

        if let harnessId, !focuses.isEmpty, folder != nil || ghPath != nil {
            Menu(Strings.RemotePRs.quickLaunchFocus) {
                ForEach(focuses, id: \.self) { focusName in
                    Button(Strings.RemotePRs.runFocusItem(focusName)) {
                        if let folder {
                            quickLaunchFocus(
                                focusName, worktree: folder, repo: repo, prNumber: pr.number, harnessId: harnessId)
                        } else if let ghPath {
                            Task {
                                await checkoutAndQuickLaunch(
                                    focusName, pr: pr, repo: repo, ghPath: ghPath, harnessId: harnessId)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Quick Terminal, Create Terminal…, then the Local tab's reveal/open-in block.
    @ViewBuilder
    private func prFolderItems(_ folder: GitWorktree, repo: ObservableRepository) -> some View {
        Button {
            boardVM.newTerminal(at: folder.path, branch: folder.branch, repoName: orgRepoName(repoPath: repo.path))
        } label: {
            Label(Strings.Sidebar.newTerminal, systemImage: "terminal")
        }
        Button {
            boardVM.addTerminal(
                workingDirectory: folder.path, branch: folder.branch, repoName: orgRepoName(repoPath: repo.path))
        } label: {
            Label(Strings.Sidebar.createTerminal, systemImage: "plus.rectangle")
        }
        Divider()
        worktreeRevealMenuItems(folder)
    }

    @ViewBuilder
    private func prRemoteItems(_ pr: GitHubPR, repo: ObservableRepository, worktree: GitWorktree?) -> some View {
        Button {
            openPROnRemote(prNumber: pr.number, repo: repo)
        } label: {
            Label(Strings.RemotePRs.openPROnRemote, systemImage: "network")
        }
        Button {
            copyPRURL(prNumber: pr.number, repo: repo)
        } label: {
            Label(Strings.RemotePRs.copyPRURL, systemImage: "doc.on.clipboard")
        }
        if let worktree {
            Button {
                Task {
                    do { try await viewModel.pullBranch(worktree: worktree, repo: repo) } catch {
                        viewModel.operationError = error.localizedDescription
                    }
                }
            } label: {
                Label(Strings.Sidebar.updateFromOrigin, systemImage: "arrow.down.circle")
            }
        }
    }

    /// Checkout this PR (carrying a review checkout's changes across), Checkout
    /// Stack, and Remove Review Checkout.
    @ViewBuilder
    private func prCheckoutItems(_ pr: GitHubPR, repo: ObservableRepository, review: GitWorktree?) -> some View {
        if let ghPath = readyGhPath {
            let existingPath = viewModel.existingWorktreePath(for: pr.localBranchName(), repoID: repo.id)
            if existingPath != nil {
                Text(Strings.RemotePRs.worktreeExists).foregroundColor(.secondary)
                Button {
                    sidebarMode = .local
                } label: {
                    Label(Strings.RemotePRs.switchToExisting, systemImage: "arrow.turn.up.left")
                }
            } else {
                Button {
                    Task { await checkoutPRFromRemote(pr, repo: repo, ghPath: ghPath, review: review) }
                } label: {
                    Label(Strings.RemotePRs.checkoutAsWorktree, systemImage: "square.and.arrow.down")
                }
            }

            // Checking out one PR of a stack gives you a branch whose parent isn't
            // here — the stack UI stays dark and the diff reads against the wrong
            // base. When the PR belongs to a forge stack, offer to bring the whole
            // thing down instead.
            if let stack = stackContaining(pr: pr, repo: repo) {
                Button {
                    Task { await checkoutWholeStack(stack, repo: repo) }
                } label: {
                    Label(
                        Strings.Stacks.checkoutStack(stack.branchCount),
                        systemImage: "square.stack.3d.down.right")
                }
            }
        }
        if let review {
            Button(role: .destructive) {
                Task { await removeReviewCheckout(review, pr: pr, repo: repo) }
            } label: {
                Label(Strings.RemotePRs.removeReviewCheckout, systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func prFocusDefaultItems(for repo: ObservableRepository, focuses: [String]) -> some View {
        let currentFocus = ynhPersistence.runFocus(for: repo.path) ?? ""
        Menu {
            if !currentFocus.isEmpty {
                Button(Strings.RemotePRs.clearDefaultFocus) {
                    ynhPersistence.setRunFocus(nil, for: repo.path)
                }
                Divider()
            }
            ForEach(focuses, id: \.self) { name in
                Button(name) { ynhPersistence.setRunFocus(name, for: repo.path) }
            }
        } label: {
            if currentFocus.isEmpty {
                Label(Strings.RemotePRs.setDefaultFocus, systemImage: "scope")
            } else {
                Label(Strings.RemotePRs.defaultFocusSet(currentFocus), systemImage: "scope")
            }
        }
    }

    // MARK: Actions

    /// Make (or reuse) the review checkout, then launch `focusName` in it.
    func checkoutAndQuickLaunch(
        _ focusName: String, pr: GitHubPR, repo: ObservableRepository, ghPath: String, harnessId: String
    ) async {
        do {
            let worktree = try await viewModel.checkoutPRForFocus(pr, repo: repo, ghPath: ghPath)
            quickLaunchFocus(focusName, worktree: worktree, repo: repo, prNumber: pr.number, harnessId: harnessId)
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    /// Remove a review checkout. Refused while a terminal is working in it; asks first
    /// when it has changes or commits that would be lost.
    func removeReviewCheckout(_ review: GitWorktree, pr: GitHubPR, repo: ObservableRepository) async {
        let directories = { boardVM.board.activeCards.map(\.workingDirectory) }
        let name = URL(fileURLWithPath: review.path).lastPathComponent
        guard !ReviewCheckouts.hasOpenTerminal(at: review.path, cardDirectories: directories()) else {
            viewModel.operationError = Strings.RemotePRs.reviewKeptInUse(name)
            return
        }
        let dirty = await GitServiceShared.isWorktreeDirty(worktreePath: review.path)
        let committed = await WorktreeSidebarViewModel.hasLocalCommits(
            worktreePath: review.path, prHeadOid: pr.headRefOid)
        if dirty || committed {
            let confirmed = AlertBuilder.confirm(
                title: Strings.RemotePRs.removeReviewCheckoutTitle,
                message: Strings.RemotePRs.removeReviewCheckoutDirty,
                confirmButton: Strings.RemotePRs.pruneRemove,
                cancelButton: Strings.Common.cancel)
            guard confirmed else { return }
        }
        let failures = await viewModel.pruneFocusWorktrees(
            repo: repo, candidates: [FocusWorktreeCandidate(path: review.path, isDirty: dirty)],
            isInUse: { ReviewCheckouts.hasOpenTerminal(at: $0, cardDirectories: directories()) })
        if !failures.isEmpty {
            viewModel.operationError = Strings.RemotePRs.pruneFailed(failures.joined(separator: ", "))
        }
    }
}
