import SwiftUI
import TermQCore
import TermQShared

// MARK: - Add Branch to Stack Context

/// Carries the target repository and worktree into `AddBranchToStackSheet`.
struct AddBranchToStackContext: Identifiable {
    let id = UUID()
    let repo: ObservableRepository
    let worktree: GitWorktree
}

// MARK: - Submit Stack Context

/// Carries the submit scope and affected branches into `SubmitStackSheet`.
struct SubmitStackContext: Identifiable {
    let id = UUID()
    let repo: ObservableRepository
    let worktree: GitWorktree
    let branches: [StackBranch]
    let scope: StackScope
}

// MARK: - Worktree Row (stack-aware)

extension WorktreeSidebarView {
    /// Renders a worktree row, wrapping it in the sidebar grid: a fixed leading
    /// chevron slot (shared by every row when the repo has any stacked worktree) and
    /// the stack chain below when expanded. Lives here (not in the main view file) so
    /// all stack-awareness stays in one place.
    ///
    /// Emits exactly ONE view per worktree (chain and conflict banner folded into the
    /// same VStack) — multiple loose siblings per ForEach element inside nested
    /// disclosure content is a recipe for List row-height misaccounting.
    @ViewBuilder
    func worktreeRow(
        _ worktree: GitWorktree, repo: ObservableRepository, allWorktrees: [GitWorktree],
        showChevronSlot: Bool
    ) -> some View {
        let chain = stackChain(for: worktree, repo: repo)
        // Header row, chain entries, and conflict banner are SIBLING List rows —
        // StackDisclosureRow's ViewBuilder body emits them individually so per-row
        // selection and context menus keep working.
        Group {
            StackDisclosureRow(
                chain: chain.count > 1 ? chain : [],
                showChevronSlot: showChevronSlot,
                currentBranch: worktree.branch,
                rowID: Self.worktreeRowID(worktree),
                isHighlighted: stackHighlightWorktreeID == Self.worktreeRowID(worktree),
                onSwitch: { branch in
                    Task { await switchStackBranch(to: branch, worktree: worktree, repo: repo) }
                },
                onRestackFromHere: { branch in
                    Task { await restackStack(worktree: worktree, repo: repo, from: branch) }
                },
                onSubmitBranch: { branch in
                    submitStackContext = SubmitStackContext(
                        repo: repo, worktree: worktree, branches: [branch],
                        scope: .branch(branch.name))
                },
                baseMismatch: { branch in
                    stackBaseMismatch(for: branch, repo: repo)
                },
                checkedOutElsewherePath: { branch in
                    guard let owner = viewModel.worktree(forBranch: branch.name, repo: repo),
                        owner.path != worktree.path
                    else { return nil }
                    return owner.path
                },
                onJumpToWorktree: { branch in
                    if let owner = viewModel.worktree(forBranch: branch.name, repo: repo) {
                        revealWorktree(owner, repo: repo)
                    }
                },
                onBreakOut: { branch in
                    convertWorktreeContext = ConvertWorktreeContext(repo: repo, branch: branch.name)
                },
                label: {
                    worktreeRowContent(worktree, repo: repo, allWorktrees: allWorktrees)
                },
                headerContextMenu: {
                    worktreeContextMenu(worktree, repo: repo)
                }
            )

            stackConflictBanner(for: worktree, repo: repo)
        }
        .padding(.leading, 4)
    }

    /// Whether any worktree in `trees` participates in a stack — drives the shared
    /// chevron slot so all rows of the repo align in one column. Repos with no stacks
    /// render without the slot, pixel-identical to the pre-stacks layout.
    func repoHasStackedWorktrees(_ trees: [GitWorktree], repo: ObservableRepository) -> Bool {
        trees.contains { stackChain(for: $0, repo: repo).count > 1 }
    }

    /// Stable scroll-target identity for a worktree row (Stacks-section jump).
    static func worktreeRowID(_ worktree: GitWorktree) -> String {
        "worktree-row-\(worktree.path)"
    }

    /// The chain of stack branches containing `worktree`'s checked-out branch, or `[]`
    /// when the repo isn't stacked, the branch isn't tracked, or it's a lone branch
    /// stacked directly on trunk with nothing above it.
    private func stackChain(for worktree: GitWorktree, repo: ObservableRepository) -> [StackBranch] {
        guard let branch = worktree.branch, let graph = viewModel.stacks[repo.id] else { return [] }
        return graph.chain(containing: branch)
    }

    /// Warning text when the entry's open PR targets a different base than its stack
    /// parent (happens after a downstack merge, until Sync Repo retargets). `nil` when
    /// consistent, unknown, or no PR data.
    private func stackBaseMismatch(for branch: StackBranch, repo: ObservableRepository) -> String? {
        guard let parent = branch.parent,
            let pr = (prService.prsByRepo[repo.path] ?? []).first(where: { $0.headRefName == branch.name }),
            let base = pr.baseRefName,
            base != parent
        else { return nil }
        return Strings.Stacks.baseMismatch(base, parent)
    }
}

// MARK: - Stacks Inventory Section

extension WorktreeSidebarView {
    /// The per-repo Stacks section, between the worktree list and Local Branches.
    /// Hidden entirely when the provider is unavailable, the repo isn't initialized,
    /// or the graph has no tracked stacks — grouping decisions live in the view model.
    @ViewBuilder
    func stacksSection(for repo: ObservableRepository) -> some View {
        let groups = viewModel.stackGroups(for: repo)
        if stackService.isAvailable, !groups.isEmpty {
            StacksSectionView(
                groups: groups,
                worktreeForBranch: { viewModel.worktree(forBranch: $0, repo: repo) },
                baseMismatch: { stackBaseMismatch(for: $0, repo: repo) },
                onJumpToWorktree: { worktree in
                    revealWorktree(worktree, repo: repo)
                },
                onNewWorktree: { group in
                    // Anchor the stack: check its bottom branch out as a worktree via
                    // the existing convert-branch flow (the branch already exists, so
                    // the new-branch sheet doesn't apply).
                    convertWorktreeContext = ConvertWorktreeContext(repo: repo, branch: group.rootName)
                },
                onBreakOutBranch: { branch in
                    convertWorktreeContext = ConvertWorktreeContext(repo: repo, branch: branch.name)
                },
                onRestackFromHereBranch: { branch in
                    if let main = viewModel.mainWorktree(for: repo) {
                        Task { await restackStack(worktree: main, repo: repo, from: branch) }
                    }
                },
                onSubmitBranch: { branch in
                    if let main = viewModel.mainWorktree(for: repo) {
                        submitStackContext = SubmitStackContext(
                            repo: repo, worktree: main, branches: [branch],
                            scope: .branch(branch.name))
                    }
                },
                groupContextMenu: { group in
                    stackGroupContextMenu(group, repo: repo)
                }
            )
            // No trailing modifiers: StacksSectionView emits sibling List rows, and a
            // modifier here would re-apply to every one of them.
        }
    }
}

// MARK: - Stack Group Context Menu

extension WorktreeSidebarView {
    /// The STACKS group-header context menu. Anchored groups lead with the worktree
    /// conveniences DELEGATED to the anchoring worktree (the exact builders the
    /// worktree-row menu uses — zero new action logic), then the stack operations,
    /// then Reveal Worktree. Unanchored groups lead with New Worktree… (the enabling
    /// action) followed by the stack operations. Worktree-lifecycle items (lock,
    /// remove, destroy, harness assignment) stay exclusive to the worktree row — the
    /// group is not the worktree.
    ///
    /// Stack mutations execute with the repo's MAIN worktree as CWD (gs targets
    /// branches via --branch; no checkout needed) through the same per-repo mutation
    /// queue, spinners, and toasts; `.upstack(from: root)` covers the whole group.
    @ViewBuilder
    func stackGroupContextMenu(_ group: StackGroup, repo: ObservableRepository) -> some View {
        let anchoring = group.branches
            .compactMap { viewModel.worktree(forBranch: $0.name, repo: repo) }.first
        let isMutating = stackService.isMutating(repo: repo.path)

        if let anchoring {
            worktreeConvenienceMenuItems(anchoring, repo: repo)
        } else {
            Button {
                convertWorktreeContext = ConvertWorktreeContext(repo: repo, branch: group.rootName)
            } label: {
                Label(Strings.Stacks.groupNewWorktree, systemImage: "plus")
            }
            Divider()
        }

        Button {
            if let main = viewModel.mainWorktree(for: repo), let root = group.branches.first {
                Task { await restackStack(worktree: main, repo: repo, from: root) }
            }
        } label: {
            Label(Strings.Stacks.restackStack, systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(isMutating)

        Button {
            if let main = viewModel.mainWorktree(for: repo), let root = group.branches.first {
                submitStackContext = SubmitStackContext(
                    repo: repo, worktree: main, branches: group.branches,
                    scope: .upstack(from: root.name))
            }
        } label: {
            Label(Strings.Stacks.submitStack, systemImage: "paperplane")
        }
        .disabled(isMutating)

        Button {
            if let main = viewModel.mainWorktree(for: repo) {
                Task { await syncStackRepo(worktree: main, repo: repo) }
            }
        } label: {
            Label(Strings.Stacks.syncRepo, systemImage: "arrow.triangle.2.circlepath.circle")
        }
        .disabled(isMutating)

        if let anchoring {
            Divider()
            Button {
                revealWorktree(anchoring, repo: repo)
            } label: {
                Label(Strings.Stacks.revealWorktree, systemImage: "arrow.turn.down.left")
            }
        }
    }
}

// MARK: - Stack Actions

extension WorktreeSidebarView {
    /// Reveal a worktree row from anywhere (badge, menu items, chain indicators):
    /// expand its ancestors first — collapsed rows are not emitted, so scrollTo has
    /// nothing to find until they exist — then, after a runloop beat, scroll to the
    /// row and pulse a brief highlight so the user sees where the jump landed.
    func revealWorktree(_ worktree: GitWorktree, repo: ObservableRepository) {
        viewModel.prepareRevealWorktree(for: repo)
        let rowID = Self.worktreeRowID(worktree)
        Task { @MainActor in
            // One beat for SwiftUI to emit the newly expanded rows.
            try? await Task.sleep(nanoseconds: 80_000_000)
            stackJumpTargetWorktreeID = rowID
            stackHighlightWorktreeID = rowID
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if stackHighlightWorktreeID == rowID {
                stackHighlightWorktreeID = nil
            }
        }
    }

    /// Guarded switch — blocked errors surface through the standard error alert.
    func switchStackBranch(
        to branch: StackBranch, worktree: GitWorktree, repo: ObservableRepository
    ) async {
        do {
            try await viewModel.switchStackBranch(repo: repo, worktree: worktree, to: branch.name)
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    /// "Restack from Here" on a stack entry (`from` set) or "Restack Stack" from the
    /// worktree context menu (`from` nil). A conflict pause is not an error — the
    /// banner appears from `stackService.conflicts`. Success and no-op outcomes are
    /// surfaced via toast so the mutation never finishes silently.
    func restackStack(
        worktree: GitWorktree, repo: ObservableRepository, from branch: StackBranch? = nil
    ) async {
        do {
            let scope: StackScope = branch.map { .upstack(from: $0.name) } ?? .stack
            let report = try await viewModel.restack(repo: repo, worktree: worktree, scope: scope)
            var lines: [String] = []
            switch report.outcome {
            case .upToDate:
                lines.append(Strings.Stacks.restackUpToDate)
            case .restacked(let count):
                lines.append(Strings.Stacks.restackDone(count))
            case .paused:
                break  // the conflict banner reports it
            }
            if !report.skipped.isEmpty {
                lines.append(
                    Strings.Stacks.skippedNotice(
                        report.skipped.map(\.noticeLine).joined(separator: ", ")))
            }
            if !lines.isEmpty {
                showStackToast(lines.joined(separator: "\n"))
            }
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    func showStackToast(_ message: String) {
        pendingToast = SidebarToast(message: message, actionLabel: nil, action: nil)
    }

    /// Context-menu items for stack operations on a worktree. Empty when no provider
    /// is available or the repo isn't stack-initialized. Mutating actions are disabled
    /// while a stack mutation is already in flight for the repo — the queue serializes
    /// anyway, but the UI should reflect it rather than silently stacking requests.
    @ViewBuilder
    func stackContextMenuItems(_ worktree: GitWorktree, repo: ObservableRepository) -> some View {
        if stackService.isAvailable && stackService.isStacked(repo: repo.path) {
            let isMutating = stackService.isMutating(repo: repo.path)
            Divider()

            Button {
                addBranchToStackContext = AddBranchToStackContext(repo: repo, worktree: worktree)
            } label: {
                Label(Strings.Stacks.addBranch, systemImage: "square.stack.3d.up.badge.a")
            }
            .disabled(isMutating)

            if let branch = worktree.branch, viewModel.stacks[repo.id]?.isStacked(branch) == true {
                Button {
                    Task { await restackStack(worktree: worktree, repo: repo) }
                } label: {
                    Label(Strings.Stacks.restackStack, systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isMutating)
                Button {
                    let chain = viewModel.stacks[repo.id].map { $0.chain(containing: branch) } ?? []
                    submitStackContext = SubmitStackContext(
                        repo: repo, worktree: worktree, branches: chain, scope: .stack)
                } label: {
                    Label(Strings.Stacks.submitStack, systemImage: "paperplane")
                }
                .disabled(isMutating)
            }

            Button {
                Task { await syncStackRepo(worktree: worktree, repo: repo) }
            } label: {
                Label(Strings.Stacks.syncRepo, systemImage: "arrow.triangle.2.circlepath.circle")
            }
            .disabled(isMutating)
        }
    }

    /// Sync Repo from the context menu — always confirms completion: either the list
    /// of removed merged branches or an explicit "everything in sync".
    func syncStackRepo(worktree: GitWorktree, repo: ObservableRepository) async {
        do {
            let report = try await viewModel.syncStackRepo(for: repo, worktree: worktree)
            if stackService.conflicts[repo.path] != nil {
                return  // the conflict banner reports it
            }
            showStackToast(syncToastMessage(for: report))
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    /// Sync outcome line(s): removed-branches summary or "everything in sync", plus a
    /// notice for branches the cross-worktree sweep couldn't restack.
    func syncToastMessage(for report: StackSyncReport) -> String {
        var lines: [String] = []
        if report.removedBranches.isEmpty {
            lines.append(Strings.Stacks.syncClean)
        } else {
            lines.append(
                Strings.Stacks.syncCleaned(
                    report.removedBranches.count,
                    report.removedBranches.joined(separator: ", ")))
        }
        if !report.skipped.isEmpty {
            lines.append(
                Strings.Stacks.skippedNotice(
                    report.skipped.map(\.noticeLine).joined(separator: ", ")))
        }
        return lines.joined(separator: "\n")
    }

    /// Conflict banner shown below the worktree row while a stack operation is paused
    /// on conflicts in this worktree.
    @ViewBuilder
    func stackConflictBanner(for worktree: GitWorktree, repo: ObservableRepository) -> some View {
        if let conflict = stackService.conflicts[repo.path], conflict.worktree == worktree.path {
            StackConflictBanner(
                conflict: conflict,
                isWorking: stackConflictWorking,
                onContinue: {
                    Task { await resumeStackConflict(repo: repo, worktree: conflict.worktree) }
                },
                onAbort: {
                    Task { await abortStackConflict(repo: repo, worktree: conflict.worktree) }
                }
            )
            .padding(.leading, 22)
            .padding(.trailing, 4)
        }
    }

    private func resumeStackConflict(repo: ObservableRepository, worktree: String) async {
        stackConflictWorking = true
        defer { stackConflictWorking = false }
        do {
            try await viewModel.continueStackOperation(repo: repo, worktree: worktree)
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }

    private func abortStackConflict(repo: ObservableRepository, worktree: String) async {
        stackConflictWorking = true
        defer { stackConflictWorking = false }
        do {
            try await viewModel.abortStackOperation(repo: repo, worktree: worktree)
        } catch {
            viewModel.operationError = error.localizedDescription
        }
    }
}
