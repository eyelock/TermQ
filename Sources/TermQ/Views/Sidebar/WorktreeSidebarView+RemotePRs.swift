import AppKit
import SwiftUI
import TermQCore
import TermQShared

// MARK: - Remote Mode Content (Phase 3–4)

extension WorktreeSidebarView {
    @ViewBuilder
    func remoteWorktreeContent(for repo: ObservableRepository) -> some View {
        switch ghProbe.status {
        case .missing:
            EmptyView()
        case .unauthenticated:
            ghUnauthEmptyState()
        case .authCheckFailed:
            Text(Strings.RemotePRs.ghAuthCheckFailed)
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.leading, 4)
                .padding(.vertical, 4)
            Button(Strings.RemotePRs.ghRecheck) {
                Task { await ghProbe.reprobe() }
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .padding(.leading, 4)
        case .ready:
            remotePRList(for: repo)
        }
    }

    @ViewBuilder
    private func ghUnauthEmptyState() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Strings.RemotePRs.ghUnauthTitle)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(Strings.RemotePRs.ghUnauthMessage)
                .font(.caption2)
                .foregroundColor(.secondary)
            Button(Strings.RemotePRs.ghRecheck) {
                Task { await ghProbe.reprobe() }
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .padding(.leading, 4)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func remotePRList(for repo: ObservableRepository) -> some View {
        if prService.loadingRepos.contains(repo.path) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        } else if let errorMsg = prService.errorByRepo[repo.path] {
            let isNoRemote =
                errorMsg.lowercased().contains("no github")
                || errorMsg.lowercased().contains("not found")
            Text(isNoRemote ? Strings.RemotePRs.noGitHubRemote : errorMsg)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        } else if let prs = prService.prsByRepo[repo.path] {
            let worktrees = viewModel.worktrees[repo.id] ?? []
            let matches = GitHubPRService.matchPRsToWorktrees(prs: prs, worktrees: worktrees)
            let cap = ynhPersistence.remotePRFeedCap(for: repo.path) ?? settings.remotePRFeedCap
            let (feed, overflow) = GitHubPRService.prioritisedFeed(
                prs: prs, login: prService.login(for: repo.path), matches: matches, cap: cap)
            let hasClosedPRWorktrees = hasClosedPRWorktrees(worktrees: worktrees, openPRs: prs)

            if feed.isEmpty {
                Text(Strings.Sidebar.worktreesEmpty)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            } else {
                ForEach(feed) { pr in
                    prRow(pr, repo: repo, worktreePath: matches[pr.number])
                }
                if overflow > 0 {
                    Button {
                    } label: {
                        Text(Strings.RemotePRs.overflowMore(overflow))
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                    .padding(.top, 2)
                }
            }

            if hasClosedPRWorktrees {
                Button {
                    Task { await analysePruneClosedPRs(repo: repo) }
                } label: {
                    Label(Strings.RemotePRs.pruneClosedPRs, systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .padding(.top, 2)
            }
        } else {
            Text(Strings.Sidebar.worktreesPlaceholder)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
                .onAppear {
                    Task { await prService.refresh(repoPath: repo.path) }
                }
        }
    }

    /// Returns true if any local `pr-NNN` worktree is for a closed PR (not in the open list).
    private func hasClosedPRWorktrees(
        worktrees: [GitWorktree], openPRs: [GitHubPR]
    ) -> Bool {
        let openNumbers = Set(openPRs.map(\.number))
        return worktrees.contains { wt in
            let last = URL(fileURLWithPath: wt.path).lastPathComponent
            guard last.hasPrefix("pr-"), let prNumber = Int(last.dropFirst(3)) else { return false }
            return !openNumbers.contains(prNumber)
        }
    }

    // MARK: - PR Row (Phase 4)

    @ViewBuilder
    private func prRow(
        _ pr: GitHubPR, repo: ObservableRepository, worktreePath: String?
    ) -> some View {
        let login = prService.login(for: repo.path) ?? ghProbe.status.login
        let badges = PRRoleBadges(
            isAuthor: login.map { pr.author.login == $0 } ?? false,
            isReviewRequested: login.map { viewer in pr.reviewRequests.contains { $0.login == viewer } } ?? false,
            isAssigned: login.map { viewer in pr.assignees.contains { $0.login == viewer } } ?? false,
            isDraft: pr.isDraft,
            isCheckedOut: worktreePath != nil
        )
        let isActive: Bool = {
            guard let path = worktreePath, let card = boardVM.selectedCard else { return false }
            let wd = card.workingDirectory
            return wd == path || wd.hasPrefix(path + "/")
        }()

        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.pull")
                .imageScale(.small)
                .foregroundColor(.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("#\(pr.number) \(pr.title)")
                    .font(.system(.subheadline, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    if badges.isAuthor {
                        Text(Strings.RemotePRs.badgeAuthor)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    if badges.isReviewRequested {
                        Text(Strings.RemotePRs.badgeReviewRequested)
                            .font(.caption2).foregroundColor(.orange)
                    }
                    if badges.isAssigned {
                        Text(Strings.RemotePRs.badgeAssigned)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    if badges.isDraft {
                        Text(Strings.RemotePRs.badgeDraft)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    if badges.isCheckedOut {
                        Text(Strings.RemotePRs.badgeCheckedOut)
                            .font(.caption2).foregroundColor(.green)
                    }
                }
            }

            Spacer()
        }
        .padding(.leading, 4)
        .contextMenu {
            prRowContextMenu(pr, repo: repo, worktreePath: worktreePath)
        }
        .task(id: repo.path) {
            // Pre-fetch harness detail so the focuses submenu is ready when the user right-clicks.
            let harnessId =
                ynhPersistence.runHarness(for: repo.path)
                ?? ynhPersistence.repoDefaultHarness(for: repo.path)
            if let id = harnessId, harnessRepository.cachedDetail(for: id) == nil {
                await harnessRepository.fetchDetail(for: id)
            }
        }
    }

    @ViewBuilder
    private func prRowContextMenu(
        _ pr: GitHubPR, repo: ObservableRepository, worktreePath: String?
    ) -> some View {
        let worktree = worktreePath.flatMap { path in
            (viewModel.worktrees[repo.id] ?? []).first(where: { $0.path == path })
        }
        let harnessId =
            ynhPersistence.runHarness(for: repo.path)
            ?? ynhPersistence.repoDefaultHarness(for: repo.path)
        let cachedFocuses: [String] =
            harnessId.flatMap { id in
                harnessRepository.cachedDetail(for: id)?.composition.focuses
            }.map { $0.keys.sorted() } ?? []

        // ─── Group 1: Primary harness action ───
        if let worktree {
            Button {
                runWithFocusContext = RunWithFocusContext(
                    worktree: worktree, repo: repo, prNumber: pr.number)
            } label: {
                Label(Strings.RemotePRs.runWithFocus, systemImage: "eye")
            }

            if let harnessId, !cachedFocuses.isEmpty {
                Menu(Strings.RemotePRs.quickLaunchFocus) {
                    ForEach(cachedFocuses, id: \.self) { focusName in
                        Button(Strings.RemotePRs.runFocusItem(focusName)) {
                            quickLaunchFocus(
                                focusName, worktree: worktree, repo: repo,
                                prNumber: pr.number, harnessId: harnessId)
                        }
                    }
                }
            }

            Divider()

            // ─── Group 2: Terminal ───
            Button {
                boardVM.newTerminal(
                    at: worktree.path, branch: worktree.branch,
                    repoName: orgRepoName(repoPath: repo.path))
            } label: {
                Label(Strings.Sidebar.newTerminal, systemImage: "terminal")
            }
            Button {
                boardVM.addTerminal(
                    workingDirectory: worktree.path, branch: worktree.branch,
                    repoName: orgRepoName(repoPath: repo.path))
            } label: {
                Label(Strings.Sidebar.createTerminal, systemImage: "plus.rectangle")
            }

            Divider()

            // ─── Group 3: Reveal / copy ───
            Button {
                revealInFinder(path: worktree.path)
            } label: {
                Label(Strings.Sidebar.revealInFinder, systemImage: "folder")
            }
            Button {
                openInTerminal(path: worktree.path)
            } label: {
                Label(Strings.Sidebar.openInTerminal, systemImage: "apple.terminal")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.headRefName, forType: .string)
            } label: {
                Label(Strings.RemotePRs.copyBranchName, systemImage: "doc.on.clipboard")
            }

            Divider()
        }

        // ─── Group 4: Remote links ───
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

        Divider()

        // ─── Group 5: Navigation / checkout ───
        if worktree != nil {
            Button {
                sidebarMode = .local
            } label: {
                Label(Strings.RemotePRs.showInLocal, systemImage: "arrow.turn.up.left")
            }
        } else {
            if case .ready(let ghPath, _) = ghProbe.status {
                let localBranch = pr.localBranchName()
                let existingPath = viewModel.existingWorktreePath(for: localBranch, repoID: repo.id)
                if existingPath != nil {
                    Text(Strings.RemotePRs.worktreeExists).foregroundColor(.secondary)
                    Button {
                        sidebarMode = .local
                    } label: {
                        Label(Strings.RemotePRs.switchToExisting, systemImage: "arrow.turn.up.left")
                    }
                } else {
                    Button {
                        Task { await checkoutPRFromRemote(pr, repo: repo, ghPath: ghPath) }
                    } label: {
                        Label(Strings.RemotePRs.checkoutAsWorktree, systemImage: "square.and.arrow.down")
                    }
                }
            }
        }

        // ─── Group 6: Focus default (only when focuses are available) ───
        if !cachedFocuses.isEmpty {
            Divider()
            prFocusDefaultItems(for: repo, focuses: cachedFocuses)
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

    private func quickLaunchFocus(
        _ focusName: String, worktree: GitWorktree, repo: ObservableRepository,
        prNumber: Int, harnessId: String
    ) {
        let harness = harnessRepository.harnesses.first { $0.id == harnessId || $0.name == harnessId }
        let title = RunWithFocusSheet.makeCardTitleStatic(
            focus: focusName, profile: "", harnessId: harnessId,
            repoPath: repo.path, prNumber: prNumber)
        let config = HarnessLaunchConfig(
            harnessID: harnessId,
            vendorID: "",
            defaultVendor: harness?.defaultVendor ?? "",
            focus: focusName,
            profile: nil,
            workingDirectory: worktree.path,
            prompt: nil,
            backend: settings.backend,
            branch: worktree.branch,
            interactive: false,
            cardTitle: title
        )
        onRunWithFocus?(config)
    }
}

// MARK: - PR Helpers

extension WorktreeSidebarView {
    /// Returns the PR number that owns this worktree, if any.
    ///
    /// Uses SHA-primary matching via `GitHubPRService.matchPRsToWorktrees`.
    func linkedPRNumber(for worktree: GitWorktree, repo: ObservableRepository) -> Int? {
        let prs = prService.prsByRepo[repo.path] ?? []
        guard !prs.isEmpty else { return nil }
        let worktrees = viewModel.worktrees[repo.id] ?? []
        let matches = GitHubPRService.matchPRsToWorktrees(prs: prs, worktrees: worktrees)
        return matches.first(where: { $0.value == worktree.path })?.key
    }

    /// Open the PR web page.
    func openPROnRemote(prNumber: Int, repo: ObservableRepository) {
        Task {
            guard let raw = try? await GitService.shared.remoteURL(repoPath: repo.path),
                let base = remoteWebURL(from: raw)
            else { return }
            let urlStr = base.absoluteString + "/pull/\(prNumber)"
            if let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
        }
    }

    private func copyPRURL(prNumber: Int, repo: ObservableRepository) {
        Task {
            guard let raw = try? await GitService.shared.remoteURL(repoPath: repo.path),
                let base = remoteWebURL(from: raw)
            else { return }
            let urlStr = base.absoluteString + "/pull/\(prNumber)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urlStr, forType: .string)
        }
    }

    /// Three-step PR checkout: detach → cd → `gh pr checkout <n>`.
    /// Shows a cross-link toast on success; sets `operationError` on failure.
    private func checkoutPRFromRemote(
        _ pr: GitHubPR,
        repo: ObservableRepository,
        ghPath: String
    ) async {
        do {
            let path = try await viewModel.checkoutPR(pr, repo: repo, ghPath: ghPath)
            let branchName = URL(fileURLWithPath: path).lastPathComponent
            pendingToast = SidebarToast(
                message: Strings.RemotePRs.checkoutToast(branchName),
                actionLabel: Strings.RemotePRs.switchToLocal,
                action: { sidebarMode = .local }
            )
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    /// Discover closed-PR worktrees (`pr-NNN` directories not in the open list)
    /// and populate the prune candidates sheet.
    private func analysePruneClosedPRs(repo: ObservableRepository) async {
        await prService.refresh(repoPath: repo.path, force: true)
        // Abort if the refresh failed — treat a nil list as unknown, not "all closed"
        guard prService.prsByRepo[repo.path] != nil else {
            viewModel.operationError =
                prService.errorByRepo[repo.path]
                ?? Strings.RemotePRs.ghAuthCheckFailed
            return
        }
        let openNumbers = Set((prService.prsByRepo[repo.path] ?? []).map(\.number))
        let worktrees = viewModel.worktrees[repo.id] ?? []
        var closedPRNumbers: Set<Int> = []
        for wt in worktrees {
            let last = URL(fileURLWithPath: wt.path).lastPathComponent
            if last.hasPrefix("pr-"), let prNum = Int(last.dropFirst(3)), !openNumbers.contains(prNum) {
                closedPRNumbers.insert(prNum)
            }
        }
        guard !closedPRNumbers.isEmpty else {
            viewModel.operationError = Strings.RemotePRs.pruneClosedPRsNothingTitle
            return
        }
        let candidates = await viewModel.pruneClosedPRsDryRun(
            repo: repo, closedPRNumbers: closedPRNumbers, prService: prService)
        pruneClosedPRsCandidates = candidates
        isShowingPruneClosedPRsFor = repo
    }
}
